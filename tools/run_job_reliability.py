#!/usr/bin/env python3
"""Runs headless Godot tests, each in its own throwaway user-data profile, several at a time.

With no selection it runs the job gate from tools/test_suite.json, plus tools/lint_project.py
(also run with --all).
  --tests  names or wildcards (Hauling*, LadderTest)   --area  groups from test_suite.json
  --all    every *Test.gd in scripts/tests              --list  print the selection and stop
A test passes when it exits 0, prints its pass marker and logs no SCRIPT ERROR to stderr.
Output is one summary line plus details for failures; --show-passes lists passes too.
On full success the run's logs, profiles and new tmp/ output are deleted unless --keep-output.

Isolation: Godot on Linux puts user:// under $XDG_DATA_HOME (default ~/.local/share), so every
test gets its own XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME inside its profile folder.
They are set in the child's environment only; the player's real profile is never touched.

Godot comes from $GODOT, then the Steam install, then `godot` on PATH.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
TMP = PROJECT / "tmp"
STEAM_GODOT = [
    Path.home() / "Storage/STEAM/SteamLibrary/steamapps/common/Godot Engine/godot.x11.opt.tools.64",
    Path.home() / ".local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64",
]
DEFAULT_TIMEOUT = 180


def find_godot() -> str:
    """$GODOT, then the Steam install, then `godot` on PATH."""
    env = os.environ.get("GODOT")
    if env:
        return env
    for path in STEAM_GODOT:
        if path.is_file():
            return str(path)
    found = shutil.which("godot")
    if found:
        return found
    sys.exit("Godot not found: set GODOT, install it through Steam, or put `godot` on PATH.")


def isolated_env(profile: Path) -> dict[str, str]:
    """A copy of this environment with Godot's user, config and cache folders inside `profile`."""
    env = dict(os.environ)
    for var, sub in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        folder = profile / sub
        folder.mkdir(parents=True, exist_ok=True)
        env[var] = str(folder)
    return env


@dataclass
class Job:
    test: str
    index: int
    phases: list[list[str]]
    profile: Path
    lock: str | None
    timeout: int
    allowed: list[str]
    phase: int = 0
    process: subprocess.Popen | None = None
    started: float = 0.0
    out: Path | None = None
    err: Path | None = None
    passed: bool = False
    exit: int | None = None
    timed_out: bool = False
    seconds: float = 0.0
    script_errors: int = 0
    failure: str = ""
    handles: list = field(default_factory=list)


def find_group(table: dict | None, test: str) -> str | None:
    for name, members in (table or {}).items():
        if test in members:
            return name
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--tests", nargs="+", default=[], metavar="NAME")
    parser.add_argument("--area", nargs="+", default=[], metavar="AREA")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--parallel", type=int, default=8)
    parser.add_argument("--show-passes", action="store_true")
    parser.add_argument("--keep-output", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--log-directory", default="")
    args = parser.parse_args()

    suite = json.loads((TOOLS / "test_suite.json").read_text(encoding="utf-8"))
    available = sorted(p.stem for p in (PROJECT / "scripts/tests").glob("*Test.gd"))

    def expand(patterns: list[str]) -> list[str]:
        found = []
        for pattern in patterns:
            hits = [t for t in available if fnmatch.fnmatchcase(t, pattern)]
            if not hits:
                sys.exit(f"No test matches '{pattern}'")
            found += hits
        return found

    selected: list[str] = list(available) if args.all else []
    for name in args.area:
        if name not in suite["areas"]:
            sys.exit(f"Unknown area '{name}'. Areas: " + ", ".join(suite["areas"]))
        selected += expand(suite["areas"][name])
    if args.tests:
        selected += expand(args.tests)
    gate_run = not args.all and not args.area and not args.tests
    if gate_run:
        selected = expand(suite["gate"])
    selected = list(dict.fromkeys(selected))
    if args.list:
        print("\n".join(selected))
        return 0

    # The gate and full runs also check the mechanical code rules (tools/lint_project.py).
    lint_failed = False
    if args.all or gate_run:
        lint = subprocess.run([sys.executable, str(TOOLS / "lint_project.py")], cwd=PROJECT)
        lint_failed = lint.returncode != 0

    godot = find_godot()
    stamp = time.strftime("%Y%m%d_%H%M%S")
    TMP.mkdir(exist_ok=True)
    tmp_before = {p.name for p in TMP.iterdir() if p.is_dir()}
    log_dir = Path(args.log_directory) if args.log_directory else TMP / f"test_run_{stamp}"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_dir = log_dir.resolve()
    has_git = shutil.which("git") is not None

    def git_status() -> list[str]:
        if not has_git:
            return []
        run = subprocess.run(["git", "-C", str(PROJECT), "status", "--porcelain"], capture_output=True, text=True)
        return run.stdout.splitlines()

    git_before = git_status()

    # Tests whose guard checks the profile path get a profile under that folder; the rest share the run folder.
    profile_runs: list[Path] = []
    jobs: list[Job] = []
    for index, test in enumerate(selected):
        root = find_group(suite.get("profile_roots"), test)
        base = TMP / root / f"run_{stamp}" if root else log_dir / "profiles"
        if root:
            profile_runs.append(base)
        jobs.append(Job(
            test=test, index=index,
            phases=(suite.get("phases") or {}).get(test) or [[]],
            profile=base / test,
            lock=find_group(suite.get("shared_output"), test),
            timeout=int((suite.get("timeouts") or {}).get(test) or DEFAULT_TIMEOUT),
            allowed=list((suite.get("expected_errors") or {}).get(test) or []),
        ))
    # Long tests first so they don't finish last on their own.
    pending = sorted(jobs, key=lambda j: (-j.timeout, j.index))

    def start_phase(job: Job) -> None:
        suffix = f".p{job.phase + 1}" if len(job.phases) > 1 else ""
        job.out = log_dir / f"{job.test}{suffix}.out"
        job.err = log_dir / f"{job.test}{suffix}.err"
        command = [godot, "--headless", "--path", str(PROJECT), "--script", f"res://scripts/tests/{job.test}.gd"]
        extra = list(job.phases[job.phase])
        if extra:
            command += ["--", *extra]
        out, err = open(job.out, "wb"), open(job.err, "wb")
        job.handles = [out, err]
        job.process = subprocess.Popen(command, cwd=PROJECT, env=isolated_env(job.profile),
                                       stdin=subprocess.DEVNULL, stdout=out, stderr=err)
        job.started = time.monotonic()

    def complete_phase(job: Job) -> bool | None:
        for handle in job.handles:
            handle.close()
        output = job.out.read_text(encoding="utf-8", errors="replace")
        errors = job.err.read_text(encoding="utf-8", errors="replace")
        # A test that exercises an error path lists the error lines it expects.
        for text in job.allowed:
            errors = "\n".join(line for line in errors.splitlines()
                               if not (re.match(r"^(SCRIPT )?ERROR:", line) and text in line))
        # A runtime error ends only the coroutine it happens in, so the test can still print its
        # marker and exit 0 with its later checks skipped: any SCRIPT ERROR fails it. ERROR and
        # WARNING lines (audio drivers, push_warning backtraces) don't. Each match keeps its "at:" line.
        script_errors = re.findall(r"(?m)^SCRIPT ERROR:.*(?:\r?\n\s+at: .*)?", errors)
        job.script_errors = len(script_errors)
        job.exit = job.process.returncode
        job.seconds += round(time.monotonic() - job.started, 1)
        final = job.phase == len(job.phases) - 1
        marker = r"_OK\b|_PASS\b|" + re.escape(job.test) + r": PASS\b"
        ok = (not job.timed_out and job.exit == 0 and not script_errors
              and (not final or re.search(marker, output) is not None))
        if not ok:
            # Up to 8 error lines, distinct script errors first, then up to 5 FAIL lines.
            lines = [l for e in dict.fromkeys(script_errors) for l in e.splitlines()]
            lines += [l for l in errors.splitlines() if l.startswith("ERROR:")]
            lines = lines[:8]
            lines += [l for l in output.splitlines() if "FAIL" in l][:5]
            if not lines:
                lines = [l for l in output.splitlines() if l.strip()][-8:]
            job.failure = "\n".join("    " + l.strip() for l in lines)
            return False
        if not final:
            job.phase += 1
            start_phase(job)
            return None
        job.passed = True
        return True

    clock = time.monotonic()
    running: list[Job] = []
    held: set[str] = set()
    finished: list[Job] = []
    try:
        while pending or running:
            while len(running) < max(1, args.parallel):
                nxt = next((j for j in pending if not j.lock or j.lock not in held), None)
                if nxt is None:
                    break
                pending.remove(nxt)
                if nxt.lock:
                    held.add(nxt.lock)
                start_phase(nxt)
                running.append(nxt)
            time.sleep(0.25)
            for job in list(running):
                if job.process.poll() is None:
                    if time.monotonic() - job.started <= job.timeout:
                        continue
                    job.process.kill()
                    job.timed_out = True
                job.process.wait()
                result = complete_phase(job)
                if result is None:
                    continue
                running.remove(job)
                if job.lock:
                    held.discard(job.lock)
                finished.append(job)
                if not job.passed:
                    why = f"timed out after {job.timeout}s" if job.timed_out else f"exit {job.exit}, {job.seconds}s"
                    if job.script_errors:
                        why += f", script errors: {job.script_errors}"
                    print(f"FAIL {job.test} ({why})")
                    if job.failure:
                        print(job.failure)
                elif args.show_passes:
                    print(f"PASS {job.test} ({job.seconds}s)")
                sys.stdout.flush()
    except KeyboardInterrupt:
        for job in running:
            job.process.kill()
        print(f"Interrupted. Logs: {log_dir}")
        return 1

    results = [{"test": j.test, "passed": j.passed, "exit": j.exit, "seconds": j.seconds,
                "timeout": j.timed_out, "scriptErrors": j.script_errors} for j in finished]
    (log_dir / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    failed = [j for j in finished if not j.passed]
    print(f"{len(finished) - len(failed)}/{len(finished)} passed in {round(time.monotonic() - clock)}s ({args.parallel} parallel)")

    touched = [line for line in git_status() if line not in git_before]
    if touched:
        print("WARNING: the run changed tracked files:")
        for line in touched:
            print("    " + line)

    if not failed and not args.keep_output:
        # Remove profiles and the review folders tests created in tmp/; leave folders that existed before.
        for folder in dict.fromkeys(profile_runs):
            shutil.rmtree(folder, ignore_errors=True)
        for folder in TMP.iterdir():
            if folder.is_dir() and folder.name not in tmp_before:
                shutil.rmtree(folder, ignore_errors=True)
    else:
        print(f"Logs: {log_dir}")
    return 1 if failed or lint_failed else 0


if __name__ == "__main__":
    sys.exit(main())
