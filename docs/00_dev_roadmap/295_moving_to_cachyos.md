# 295 — Moving to CachyOS

2026-11-02. A plan; nothing is built. The owner is moving the project from Windows to CachyOS
(Arch-based, KDE Plasma on Wayland) and will run Claude Code in a terminal there. There is no dual
boot: once CachyOS is installed there is no Windows to check anything on, and whatever was not
pushed or backed up is gone. The owner backs up first ("Before the install"); the first Linux
session does the rest ("First Linux session"). The facts below come from a scan of the project and
a check of the Claude Code docs, both on 2026-11-02.

From the owner:
- "I want to move this project to CachyOS, we will use claude code there in the terminal".
- "I won't be dual booting, we will only run CachyOS".
- Offered the tooling port on Windows before the move, so the new test runner could be compared
  with the old one: "Just write the doc". The port happens on Linux with no Windows run to compare
  against, which is why step 5 of the first Linux session checks the isolation first.

## What carries over

- **File name case.** Every `res://` path and project path in the code, data, scenes and tools,
  and every path in the git index, matches the file on disk exactly. Names built at runtime from
  ids are only proven by running the gate on Linux, where a wrong case fails to load.
- **Saves and settings** hold no Windows paths. They copy over as they are.
- **The engine side.** GDScript only, with no add-ons, GDExtension or C#. The fonts are bundled
  (`assets/ui/fonts/`), and Jolt is built into Godot.
- **Rendering.** `project.godot` sets Direct3D 12 for Windows only
  (`rendering_device/driver.windows`), so Linux uses Vulkan with no change. Expect the same look.
- **Input and the desktop.** The camera only hides the cursor; it never moves or captures it,
  which Wayland would refuse. Opening the saves and blueprints folders (`OS.shell_open`) and
  deleting a save to the bin (`OS.move_to_trash`) work on KDE.
- **The art pipeline.** The Python and Node scripts use `pathlib` and start only `node`.
- **Git.** `.gitattributes` stores text as LF, so a fresh clone has LF everywhere. The 137 files
  saved as CRLF in the Windows working tree don't matter. There is no Git LFS.

## What breaks on Linux

- **The test runner**, `tools/run_job_reliability.ps1`: Windows PowerShell 5.1, the Steam `.exe`
  path, the `py` launcher, `Start-Process -WindowStyle Hidden` and `\` in paths. It isolates each
  test by setting `APPDATA` and `LOCALAPPDATA`, which Godot ignores on Linux. A careless port
  would run tests in the player's real profile and could overwrite the saves. Port it to Python
  ("The runner in Python", below).
- **The headless import**, `tools/voxel_assets/Import.ps1`, needed after every new WAV, PNG or
  GLB: the same problems. Port it with the runner.
- **15 other PowerShell scripts**: `tools/voxel_assets/Run.ps1`, `tools/sky_art/` (`Run`,
  `Verify`), `tools/terrain_art/` (`Capture`, `CaptureShoreline`, `Verify`) and nine in
  `tools/performance/`. Port an art script when art work needs it. Performance work is paused:
  delete those, or port them when it resumes.
- **15 scripts check the `APPDATA` variable** and refuse to run on Linux: six tests
  (`CaveGenerationTest`, `ResourceProgressionTest`, `WorldGenerationTest`, `WorldLayoutTest`,
  `WorldResourceBalanceTest`, `WorldResourceDiagnosticsTest`) and nine previews in `tools/`
  (`ArrivalLivePreview`, `BoulderLivePreview`, `CaveLivePreview`, `DuckLivePreview`,
  `FlowerLivePreview`, `RabbitLivePreview`, `ReedLivePreview`, `ShrubLivePreview`,
  `WorldLayoutLivePreview`). None is in the gate. Check `OS.get_user_data_dir()` instead, as 32
  other scripts already do: it lies inside the isolated profile on both systems.
- **Windows paths in files**: the Steam `.exe` in the PowerShell scripts; the owner's quicksave
  under `C:/Users/akadi/AppData/Roaming/` in four scripts in `tools/performance/`
  (`AnalyzeSteadyRendering.py`, `CollectDuckUpdateEvidence.py`, `CollectEvents.py`,
  `CollectLighting.py`); `C:/Windows/Fonts` in `tools/render_world_layout_gallery.py`; and
  `export_path="D:/Deepdraft.exe"` in `export_presets.cfg`.
- **The colony-check reminder** is a Claude desktop scheduled task, and CachyOS gets no desktop
  app. Rebuild it ("The colony-check reminder", below).
- **Comparison sheets** were drawn with PowerShell WPF (memory `deepdraft_windowed_captures`).
  Use Pillow or ImageMagick.
- **Instructions** in CLAUDE.md, seven docs and ten memory files give Windows commands ("Docs and
  memory to update", below).
- **Performance numbers** in the docs were measured with Direct3D 12 and don't compare with
  Vulkan.

## Where things live

| | Windows | CachyOS |
|---|---|---|
| Godot | Steam 4.7.2: `S:\STEAM\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` | 4.7.2 from Steam's Linux build (`~/.local/share/Steam/steamapps/common/Godot Engine/`; check the binary's name) or the official download |
| Renderer | Direct3D 12 | Vulkan |
| Player profile (`user://`) | `%APPDATA%\Godot\app_userdata\Deepdraft\` | `~/.local/share/godot/app_userdata/Deepdraft/` |
| Isolating a profile | `APPDATA`, `LOCALAPPDATA` | `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` |
| Editor settings | `editor_data\` beside the Steam `.exe` (the build is self-contained) | Beside the binary if the Linux build is self-contained too, else `~/.config/godot/` |
| Python | `py`, `py -3` | `python3` (Arch's `python` is Python 3 too) |
| Claude's memory | `~\.claude\projects\P--Deepdraft\memory\` | `~/.claude/projects/<folder>/memory/`, most likely `-home-<user>-Deepdraft` |
| Claude's shell | Git Bash or PowerShell | bash or zsh, never fish (CachyOS's default); commands here are bash |

## Before the install (the owner, on Windows)

1. **Commit and push everything.** On 2026-11-02 that was 410 modified, 39 deleted and 305
   untracked files, including `tools/audio_sources/` (106 MB of lossless masters, never committed;
   the largest file is 8.8 MB, under GitHub's 100 MB limit) and the new `tools/generate_*.py`.
2. **Copy the project folder to an external drive**, without `.godot/` (427 MB, rebuilt by the
   first import). It is the only copy of `tmp/` (3.5 GB, ignored by git). About 30 of its folders
   (≈1.6 GB) are still named in the docs and memory: the concept studies behind recent picks
   (`peeled_logs_20261028`, `grill_concepts_20261031`, `ranger_concepts_20261101`,
   `mason_carpenter_concepts_20261101`, `storage_concepts_20261102`), the audio audit
   (`audio_audit_20261028`, 818 MB) and the UI reviews with the Stonehearth references
   (`ui_review_20261023`). Copy all of it rather than choosing.
3. **Copy the player profile**, `%APPDATA%\Godot\app_userdata\Deepdraft\`: `saves\` (the
   quicksave, the autosave and `named\gunberg_summer_day_1.json`, 20 MB), `blueprints\`,
   `ui_layout.json`, `video.cfg`, `audio.cfg` and `item_stamper.cfg`. Leave `shader_cache\`,
   `vulkan\`, `logs\` and the old test folders (`berry_probe`, `ladder_probe`,
   `loading_screen_test`, `save_worker_faults`, `terrain_startup_test`, `tmp`).
4. **Copy Claude's memory**, `C:\Users\akadi\.claude\projects\P--Deepdraft\memory\`. Not the
   transcripts (1.4 GB) or `.credentials.json`; Claude Code logs in again on Linux.
5. **Optional:** Godot's editor settings (`editor_data\`, above), though setting them again is
   usually easier; and screenshots in Play of day, night, fog, water, sky and an underground
   slice, to compare with Vulkan by eye.
6. **Optional:** a last gate run on Windows, recorded under "Baseline" below.

Everything else on the disks goes with the install.

## First Linux session

1. **Install**, with pacman unless noted:
   - Godot 4.7.2: Steam (`steam`, then its "Godot Engine" app) or the official download. Use the
     distro's `godot` package only while it is 4.7.x; a newer version upgrades the project.
   - `git` and `github-cli` (then `gh auth login`); `python` and `nodejs`; `vulkan-tools`
     (`vulkaninfo` should list the GPU).
   - `bubblewrap` and `socat` for Claude Code's sandbox; without them its commands run
     unsandboxed.
   - `python-pillow` for comparison sheets; `libnotify` for `notify-send` if KDE lacks it.
   - A virtual environment for the audio generators (`numpy`, `soundfile`): Arch refuses
     `pip install` outside one.
   - Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`.
   - Optional: Google Chrome (AUR `google-chrome`) for Claude in Chrome.
2. **Clone** `https://github.com/akadic10/Deepdraft.git` to a folder on the Linux drive (for
   example `~/Deepdraft`) and set `git config user.name` and `user.email`.
3. **Restore** from the backup: `tmp/` into the clone, and the player profile into
   `~/.local/share/godot/app_userdata/Deepdraft/`. Start `claude` once in the project, find the
   folder it made under `~/.claude/projects/`, and copy the memory files into its `memory/`.
4. **Import once**: `godot --headless --editor --path ~/Deepdraft --import`, or open the project in
   the editor. Headless tests can't load assets before this.
5. **Port the runner and the import** ("The runner in Python", below). Before the first gate, run
   one test with `--keep-output` and check that nothing in the real profile changed (its file
   times) and that the test's `user://` lay inside `tmp/`.
6. **Switch the 15 `APPDATA` checks** to `OS.get_user_data_dir()`.
7. **Run the gate**, then the areas holding the switched tests. A failure is now either the port or
   a real Linux difference; read the log before fixing.
8. **Update CLAUDE.md, the docs and memory** ("Docs and memory to update"), and delete the
   replaced PowerShell scripts.
9. **Rebuild the colony-check reminder** ("The colony-check reminder").
10. **The owner's look in Play** under Vulkan: fog, water, sky, night light, fullscreen at
    2560 × 1440, UI scale 150 and the sound. Compare with the Windows screenshots.

## The runner in Python

Keep `tools/test_suite.json` and everything the runner does; only the language and the isolation
change. A name such as `tools/run_job_reliability.py` keeps the docs' references short.

- **Selection.** No options: the gate and the lint. `--area` takes groups from `test_suite.json`,
  `--tests` takes names or wildcards, `--all` runs every `*Test.gd` in `scripts/tests` and the
  lint, and `--list` prints the selection and stops.
- **A run.** `godot --headless --path <project> --script res://scripts/tests/<Test>.gd`, with a
  phase's extra arguments after `--`. A test's `phases` run in order.
- **Profiles.** Every test gets its own. Tests in a `profile_roots` group get it under
  `tmp/<root>/run_<stamp>/<Test>`, because their checks look for that path; the rest under the
  log folder's `profiles/`. On Linux, point `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and
  `XDG_CACHE_HOME` at folders inside the profile, in the child's environment only.
- **Scheduling.** Eight at a time (`--parallel`), longest timeout first; `timeouts` default to
  180 s. Tests in one `shared_output` group never run together.
- **Passing.** Exit 0, the marker in the last phase's output (`_OK`, `_PASS` or `<Test>: PASS`)
  and no `SCRIPT ERROR:` on stderr apart from lines in `expected_errors`. `ERROR:` and `WARNING:`
  lines alone don't fail a test.
- **Reporting.** For a failure, up to 8 error lines (distinct script errors first, each with its
  `at:` line, then `ERROR:` lines) and up to 5 `FAIL` lines from the output; with none, its last 8
  lines. One summary line, `N/M passed in Xs (P parallel)`, and `results.json` in the log folder
  (by default `tmp/test_run_<stamp>/`).
- **Tidiness.** Warn when the run changed tracked files (`git status --porcelain` before and
  after). After a fully green run, delete the profiles and the `tmp/` folders the run made, unless
  `--keep-output`; otherwise print the log folder.
- **Exit 1** on a failed test or a failed lint (`python3 tools/lint_project.py`).
- **Godot** from a `GODOT` environment variable, then the Steam path, then `godot` on `PATH`.
- **The import**, replacing `Import.ps1`: `godot --headless --editor --path <project> --import` in
  an isolated profile, failing on a non-zero exit.

**Baseline.** The newest gate count in the changelog is 55/55 on Windows, on 2026-10-31.

## Docs and memory to update

At the switch, not before: until then they describe the machine in use.
- **CLAUDE.md:** the identity table (the engine row's "Direct3D 12 on Windows", the Godot install
  path), the test bullets (`tools/run_job_reliability.ps1`, `py tools/lint_project.py`) and
  "Builds only when asked" ("Windows playtest").
- **`13_architecture.md`:** the performance commands (around lines 1318–1350), the export section
  (1368–1371, `build/windows/manual_export/Deepdraft.exe`) and the test runner section
  (1380–1391, `APPDATA`/`LOCALAPPDATA`).
- **`61_voxel_art_guide.md`:** the `py -3` commands, `Import.ps1` (lines 76, 116 and 155), the
  runner (79) and the `APPDATA` note (160).
- **`23_user_interface.md`** line 1967 (`Import.ps1`) and **`21_camera.md`** line 129
  (`tools/performance/Run.ps1`).
- **`00_colony_checks.md`:** the reminder paragraph and step 2 (a scratch `Run.ps1`, `%TEMP%`).
- **`00_todo.md`** lines 279, 318 and 360, and **`00_open_issues.md`** line 79: runner and
  performance commands.
- The changelog keeps its history as written.
- **Memory:** `deepdraft_safe_test_runs` (the Godot path, PowerShell 5.1 notes, `APPDATA`),
  `deepdraft_audio_tooling` (the Python venv, `Import.ps1`), `deepdraft_save_replay_probe` (the
  save path, the runner), `deepdraft_windowed_captures` (`APPDATA`, WPF sheets),
  `deepdraft_retired_asset_imports` (`Import.ps1`), `deepdraft_hall_modules`
  (`tmp/goods_panel_20261027/Run.ps1`), `deepdraft_storage_furniture` (the Git Bash `sed` note),
  `deepdraft_prune_over_repair` (the runner's name), `deepdraft_time_budget` (the reminder) and
  `deepdraft_linux_move`, with their lines in `MEMORY.md`.

## The colony-check reminder

The desktop task `deepdraft-colony-check-reminder` is lost with Windows. What it did:
- Mondays at 9:00 it read the log in `00_colony_checks.md`; the first row's date is the last
  check (no rows: never run).
- It read the top of `00_changelog.md`. Entries are newest first, separated by `---`, each
  starting with a bold title that ends in its date, such as
  `**Storage priority and the tool rack (2026-11-02):**`. It collected the entries dated on or
  after the last check (that day's entries may not have been covered).
- A check was due when 7 days or more had passed, or none had run, and at least one entry was
  found. Then it sent one desktop notification, a single line under 200 characters, such as
  "Deepdraft colony check due: last run 2026-11-02, 7 days ago; 4 changes since. Ask Claude to run
  the weekly colony check." Otherwise nothing.
- It only reminded: it never ran the check, started Godot or edited a file.

On Linux this needs no Claude: a small Python script (for example
`tools/colony_check_reminder.py`) that calls `notify-send`, run by a systemd user timer.
`Persistent=true` makes a Monday spent switched off fire at the next login.

```ini
# ~/.config/systemd/user/deepdraft-colony-check.service
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/Deepdraft/tools/colony_check_reminder.py

# ~/.config/systemd/user/deepdraft-colony-check.timer
[Timer]
OnCalendar=Mon *-*-* 09:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it with `systemctl --user enable --now deepdraft-colony-check.timer`.

## Claude Code in a terminal

From the Claude Code docs on 2026-11-02:
- **No desktop app.** The Linux desktop app is a beta for Debian and Ubuntu; the docs send Arch
  users to the terminal. Gone with it: local scheduled tasks, the browser pane, the task list and
  next-step box, session cards and the terminal panel.
- **Scheduling.** `/loop` runs only while a session is open. `/schedule` runs in the cloud on a
  fresh clone and can't see local files or saves.
- **Images.** Ctrl+V pastes a screenshot; dragging a file in or giving its path works too.
- **Konsole** shows no desktop notification when Claude finishes: set `preferredNotifChannel` to
  `"terminal_bell"` or add a Notification hook. Ctrl+J starts a new line.
- **Claude in Chrome.** The Linux setup is documented for Google Chrome and Edge.
- **Memory** lives under `~/.claude/projects/`, in a folder named from the project path;
  `autoMemoryDirectory` can set it.

## Later

- The art capture scripts when art work needs them; the performance scripts deleted, or ported
  when performance work resumes.
- **Builds**, only when the owner asks: `export_presets.cfg` has one preset, "Windows Desktop",
  exporting to `D:/Deepdraft.exe`. Install the 4.7.2 export templates and add a Linux preset.
  Windows builds still export from Linux, with no Windows to test them on (Proton or Wine can run
  one). `tools/windows_playtest/README.txt` stays for Windows players.
