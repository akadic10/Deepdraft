#!/usr/bin/env python3
"""Runs a Godot script that has to draw, on a hidden screen and in an isolated profile.

Godot's --headless draws nothing, so menu pictures, galleries and rendered captures need a real
renderer. Run them through this tool instead of launching Godot yourself: no window opens on the
owner's desktop, and the player's real profile is never touched.
    python3 tools/run_offscreen.py [options] res://tools/Script.gd [the script's arguments]
  --name=<label>      the run's folder under tmp/offscreen/ (profile and log); default: the script's name
  --save              put a copy of the owner's quicksave in the profile first, where startup resume
                      finds it; the original is checked unchanged afterwards
  --resolution=<WxH>  the window Godot asks for (default 1600x1000; the hidden screen is 3840x2160)
  --timeout=<s>       default 900
The full log goes to tmp/offscreen/<label>/run.log; its errors and last lines are printed.

The hidden screen is a private KWin drawing to a virtual framebuffer (`kwin_wayland --virtual`)
with the real graphics card, so pictures come out byte for byte as they do in a window on the
desktop. It gets its own session bus and runtime folder, takes the isolated profile's settings
and is not told where the desktop is. It is 3840x2160 at 60 Hz and reports no pixel density, so
the game lays its interface out at 100%: a capture that shows the interface sets
`VideoSettings.dpi_override` to the density it wants (144 for 150%). The project starts
fullscreen, so a capture of the game's window makes it windowed and sets its size first.

Other tools import `run()` to put their own Godot command on the hidden screen.
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from run_job_reliability import PROJECT, TMP, find_godot, isolated_env

SCREEN = (3840, 2160)
DESKTOP = ("WAYLAND_DISPLAY", "WAYLAND_SOCKET", "DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS")
QUICKSAVE = Path.home() / ".local/share/godot/app_userdata/Deepdraft/saves/quicksave.json"
PROFILE_SAVES = "data/godot/app_userdata/Deepdraft/saves"
ERRORS = ("ERROR", "SCRIPT", "Parse", "TIMED OUT")
STILL_IN_USE = "still in use at exit"


def run(command: list[str], env: dict[str, str], cwd: Path = PROJECT, timeout: float = 900) -> tuple[int, str]:
    """Runs `command` on a hidden screen. Returns its exit code and its output, or -1 and the
    screen's own log when the screen never started it, or -9 when it ran out of time."""
    for tool in ("kwin_wayland", "dbus-run-session"):
        if not shutil.which(tool):
            sys.exit(f"The hidden screen needs `{tool}`, which is not installed.")
    # Sockets need a short path: the screen's runtime folder sits in the user's (a tmpfs).
    runtime = Path(tempfile.mkdtemp(prefix="deepdraft-offscreen-", dir=os.environ.get("XDG_RUNTIME_DIR")))
    job = runtime / "job.json"
    job.write_text(json.dumps({"command": [str(part) for part in command], "cwd": str(cwd)}))
    hidden = {name: value for name, value in env.items() if name not in DESKTOP}
    hidden["XDG_RUNTIME_DIR"] = str(runtime)
    screen = ["dbus-run-session", "--", "kwin_wayland", "--virtual", "--width", str(SCREEN[0]), "--height", str(SCREEN[1]),
              "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities", "--xwayland",
              "--exit-with-session", shlex.join([sys.executable, str(Path(__file__).resolve()), "--on-screen", str(job)])]
    late = False
    try:
        with open(runtime / "screen.log", "w") as log:
            process = subprocess.Popen(screen, env=hidden, cwd=cwd, stdin=subprocess.DEVNULL, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                late = True
            _end(process)
        output = (runtime / "output.log").read_text(errors="replace") if (runtime / "output.log").exists() else ""
        if late:
            return -9, output + f"\nTIMED OUT after {timeout:.0f} s"
        if not (runtime / "code").exists():
            return -1, output + "\nERROR: the hidden screen did not finish the command. Its log:\n" + (runtime / "screen.log").read_text(errors="replace")
        return int((runtime / "code").read_text()), output
    finally:
        shutil.rmtree(runtime, ignore_errors=True)


def _end(process: subprocess.Popen) -> None:
    """Ends whatever the hidden screen left running; it is its own process group."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
            for _ in range(20):
                time.sleep(.1)
                process.poll()
                os.killpg(process.pid, 0)
        except ProcessLookupError:
            return


def _on_screen(job: Path) -> None:
    """Inside the hidden screen: runs the job, keeping its output and exit code beside it."""
    spec = json.loads(job.read_text())
    with open(job.with_name("output.log"), "w") as out:
        code = subprocess.run(spec["command"], cwd=spec["cwd"], stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT).returncode
    job.with_name("code").write_text(str(code))


def main() -> int:
    args = sys.argv[1:]
    options: dict[str, str] = {}
    while args and not args[0].startswith("res://"):
        name, _, value = args.pop(0).partition("=")
        options[name] = value
    unknown = set(options) - {"--name", "--save", "--resolution", "--timeout"}
    if not args or unknown:
        print(__doc__)
        return 2
    script = args.pop(0)
    output = TMP / "offscreen" / (options.get("--name") or Path(script).stem)
    output.mkdir(parents=True, exist_ok=True)
    env = isolated_env(output / "profile")
    before = ""
    if "--save" in options:
        before = hashlib.sha256(QUICKSAVE.read_bytes()).hexdigest()
        saves = output / "profile" / PROFILE_SAVES
        saves.mkdir(parents=True, exist_ok=True)
        shutil.copy2(QUICKSAVE, saves / "quicksave.json")
    command = [find_godot(), "--audio-driver", "Dummy", "--accessibility", "disabled", "--windowed",
               "--resolution", options.get("--resolution") or "1600x1000", "--path", str(PROJECT), "--script", script, "--"] + args
    began = time.time()
    code, log = run(command, env, timeout=float(options.get("--timeout") or 900))
    (output / "run.log").write_text(log)
    lines = log.splitlines()
    print(f"exit {code} after {time.time() - began:.0f} s; log: {(output / 'run.log').relative_to(PROJECT)}")
    errors = [line for line in lines if any(key in line for key in ERRORS) and STILL_IN_USE not in line]
    print("\n".join(errors[-40:] + [line for line in lines[-8:] if line not in errors]))
    if before and hashlib.sha256(QUICKSAVE.read_bytes()).hexdigest() != before:
        print("ERROR: the owner's quicksave changed during the run.")
        return 1
    return 0 if code == 0 and not any("SCRIPT ERROR" in line or "Parse Error" in line for line in lines) else 1


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--on-screen":
        _on_screen(Path(sys.argv[2]))
    else:
        sys.exit(main())
