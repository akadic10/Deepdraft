#!/usr/bin/env python3
"""Headless Godot import (replaces tools/voxel_assets/Import.ps1).

Run it after adding or changing a WAV, PNG or GLB, before tests load the new asset:
    python3 tools/import_assets.py [label]
Godot runs in an isolated profile under tmp/asset_import/<label>/, so the player's real
profile is never touched. Fails on a non-zero exit.
"""
import subprocess
import sys

from run_job_reliability import PROJECT, TMP, find_godot, isolated_env


def main() -> int:
    label = sys.argv[1] if len(sys.argv) > 1 else "import"
    output = TMP / "asset_import" / label
    output.mkdir(parents=True, exist_ok=True)
    command = [find_godot(), "--headless", "--editor", "--path", str(PROJECT), "--import"]
    with open(output / "run.out", "wb") as out, open(output / "run.err", "wb") as err:
        run = subprocess.run(command, cwd=PROJECT, env=isolated_env(output / "profile"),
                             stdin=subprocess.DEVNULL, stdout=out, stderr=err)
    if run.returncode != 0:
        print(f"Import failed: exit {run.returncode}. Logs: {output}")
        return 1
    print(f"Import complete: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
