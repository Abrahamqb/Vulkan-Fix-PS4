# Vulkan Solution — PS4 Artix (Liverpool GPU)

**Language:** [Español](README.md) · [English](README.en.md)

Self-contained folder with the diagnosis, stable Mesa builds, launchers and a
GPU monitor to play with **Vulkan/DXVK without hanging the GPU** on this PS4.

Date: 2026-10-29 · Reference kernel: `7.0.8-Strawberry-FullLTO-Baikal-+` ·
System Mesa: 26.0.8

> Examples use fictional paths (`/home/USER/...`,
> `/run/media/USER/External/Games/...`). Replace them with your own. Inside the
> scripts everything is resolved from `$HOME` and the real repository folder, so
> you can clone it anywhere.

---

## 0. Installation

### Recommended: one command

```bash
git clone https://github.com/Abrahamqb/Vulkan-Fix-PS4
cd Vulkan-Fix-PS4
./install.sh
```

The repository and folder name
do not matter: every script detects its own location, so you can clone, move or
rename it without editing anything.

`install.sh` does everything:

1. Detects the distribution. **It is only supported on Arch Linux and
   Arch-based distributions that use pacman** (Artix, EndeavourOS, Manjaro,
   Garuda, CachyOS…). On anything else it warns and asks whether to continue.
2. Checks the required tools and offers to install them with `pacman`.
3. Starts `ps4-monitor` in the background **before** touching anything, so a
   GPU hang or video loss is recorded.
4. Downloads Mesa 25.3.5 + LLVM 21 and Mesa 26.0.4 + LLVM 22, verifies their
   `sha256` and generates the ICDs.
5. Runs a general RADV check and then **verifies each version individually**.
6. On success it explains how to use the launchers. On failure it keeps the
   logs and the monitor report.

Useful options:

```bash
./install.sh --dry-run        # show the plan without changing anything
./install.sh --yes            # accept every question
./install.sh --skip-download  # use the Mesa copies already downloaded
./install.sh --skip-tests     # do not run Vulkan tests
./install.sh --no-monitor     # do not start the monitor
./install.sh --no-desktop     # do not create menu shortcuts
```

### Manual installation

```bash
./download-mesa.sh      # download Mesa/LLVM and generate the ICDs (~650 MB)
./check.sh              # verify RADV with every version
./check.sh 25.3.5       # verify one specific version
```

The repository **does not include the binaries** (Mesa + LLVM are about 650 MB
and GitHub rejects files larger than 100 MB). `download-mesa.sh` fetches them
from the original sources (the `ps4-video` repo and Arch Archive), verifies their
`sha256` and stores them in `mesa-versions/`.

### Steam + Proton (recommended)

Install **Proton 8.0-5** in Steam **even if your games do not come from Steam**.
`vulkan-run.sh --proton` uses Steam's Proton (and the Steam Linux Runtime) for
any Windows `.exe`, whether it is a Steam game or not. Proton 8.0-5 is the
tested version; if Proton 8.0 is missing, the launcher falls back to another
installed Proton, but that combination is not verified.

This is not needed for native Linux games, `check.sh`, `vkcube`,
`vulkan-env.sh` or Heroic (Heroic uses its own Wine-GE/Proton-GE).

Also, some games require the **Steam client to be running** because they use the
Steam API (for example the PES/Football Life titles), even when launched with
`vulkan-run.sh`.

`install.sh` creates a `~/mesa-versions -> <repo>/mesa-versions` symlink when
that path does not exist, so old Steam launch options keep working. If you
already have `~/mesa-versions`, it asks whether to use it.

---

## 1. The problem in 30 seconds

With the system Mesa 26.0.8, RADV hangs the GPU on the first frame of a game
using DXVK:

```
amdgpu: ring gfx timeout, signaled seq=... emitted seq=...
amdgpu:  Process <game> on pi ... thread dxvk-submit ...
amdgpu: GPU Recovery Failed: -110      -> black screen, reboot required
```

OpenGL (radeonsi) and `vkcube` always work: **the bug is in RADV when it
compiles/runs DXVK pipelines** on the gfx7 "Liverpool" GPU.

Tested and ruled out: temperature (69 °C at failure), low clocks (`glxgears`
1621 FPS), `amdgpu.dpm=0`, wined3d, LLVM, GPL off, etc. Full details in
[`reports/ps4-vulkan-diagnosis.md`](reports/ps4-vulkan-diagnosis.md).

**Solution:** use RADV from **Mesa 25.3.5** (or 26.0.4) only for the game.
Nothing is installed or modified system-wide.

| RADV | Result |
|---|---|
| 26.0.8 (system) | hang after 10–20 s |
| **25.3.5** | stable (420 s tested, 33–52 FPS) |
| **26.0.4** | stable (240 s tested, 35–60 FPS) |

---

## 2. Folder contents

```
repo/
├── README.md               Spanish documentation
├── README.en.md            this document (English)
├── install.sh              full installation (download, monitor, tests)
├── vulkan-env.sh           core: selects Mesa (use with source)
├── vulkan-env.fish         same for fish
├── vulkan-run.sh           universal launcher (Steam, non-Steam, anything)
├── heroic-mesa.sh          wrapper for Heroic Launcher (Flatpak or native)
├── prepare-heroic.sh       permissions + deps + test for Heroic
├── check.sh                verify RADV/Mesa for each version
├── check-heroic.py         minimal Vulkan test (works inside the sandbox)
├── download-mesa.sh        rebuild mesa-versions/ with sha256
├── steam-options.txt       ready-to-paste Steam texts
├── activation.log          activation history (local, not committed)
├── mesa-versions/          stable Mesas + LLVM + ICDs (not committed)
├── monitor/
│   ├── ps4-monitor.sh          background GPU/video monitor
│   ├── ps4-monitor-stop.sh     stop it
│   └── ps4-monitor-status.sh   status and last lines
├── logs/                   sessions, install and error logs (local)
├── run/                    monitor PIDs (local)
├── reports/
│   ├── ps4-vulkan-diagnosis.md  full technical report
│   ├── tests-2026-10-29.md      test timeline
│   ├── mesa-versions-README.txt mesa-versions inventory
│   └── logs/                    historical monitor logs
├── desktop/                .desktop templates
└── tests/smoke-test.sh     smoke test (syntax, translation, monitor)
```

Working copies can also live in `~/mesa-versions` (used by old Steam launch
options). The scripts use `repo/mesa-versions` first and fall back to
`~/mesa-versions`; you can force another folder with
`VULKAN_MESA_DIR=/path/to/mesa-versions`.

---

## 3. Quick start

### 3.1 Fish (default shell)

```fish
source /path/to/repo/vulkan-env.fish
# from now on, everything you launch uses RADV from Mesa 25.3.5
```

With another version or the HUD:

```fish
source /path/to/repo/vulkan-env.fish --mesa 26.0.4
source /path/to/repo/vulkan-env.fish --mesa 25.3.5 --hud fps
```

### 3.2 Bash / sh / zsh

```bash
. /path/to/repo/vulkan-env.sh              # Mesa 25.3.5
. /path/to/repo/vulkan-env.sh --mesa 26.0.4
. /path/to/repo/vulkan-env.sh --hud fps,devinfo
```

The variables stay in that terminal. For a single command:

```bash
bash -c '. /path/to/repo/vulkan-env.sh; ./my_program'
```

### 3.3 Universal launcher (without touching the shell)

```bash
vulkan-run.sh --mesa 25.3.5 -- vkcube
vulkan-run.sh --mesa 25.3.5 --hud -- ./linux_program
vulkan-run.sh --wined3d --proton -- "/path/to/game32bits.exe"
```

Run `vulkan-run.sh -h` to see every option.

---

## 4. Steam (Steam game)

Game Properties → **Launch Options**. Two valid forms:

**A) With the launcher (recommended, respects Steam's `%command%`):**

```
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command% -force-d3d11
```

**B) With `source` (shorter):**

```
bash -c '. /path/to/repo/vulkan-env.sh --mesa 25.3.5; exec "$@"' _ %command% -force-d3d11
```

Replace `/path/to/repo` with the real path of your clone. For Mesa
26.0.4 change `--mesa 25.3.5` to `--mesa 26.0.4`. `-force-d3d11` is only needed
for Unity games that try D3D12.

To confirm the game uses the right Mesa: add `--hud=fps,devinfo` (form A) or
`DXVK_HUD=devinfo` (form B); the top-left corner should say
`Mesa 25.3.5 (git-39f24bf409)`.

---

## 5. Non-Steam games

### Option 1 — without Steam (the launcher creates one prefix per game)

```bash
/path/to/repo/vulkan-run.sh --proton -- "/run/media/USER/External/Games/Example Game/game.exe"
```

The prefix is stored in `~/.local/share/vulkan-proton/<game-name>/`.
You can force another one with `--prefix`:

```bash
/path/to/repo/vulkan-run.sh --proton --prefix ~/.local/share/wine/example -- "/path/game.exe"
```

### Option 2 — added to Steam (Steam-managed prefix)

1. Steam → *Add a Game* → *Add a Non-Steam Game* → choose the `.exe`.
2. Properties → *Force the use of a specific Steam Play compatibility tool* →
   **Proton 8.0**.
3. Launch Options:

```
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command%
```

### ⚠️ 32-bit games

32-bit `.exe` files need a 32-bit RADV, and **there is no** old version: only
`lib32-llvm` 23.x exists, which does not work with Mesa 25.3.5/26.0.4. The
launcher detects this and warns.

For those games use **wined3d (OpenGL)**, which is stable on this PS4:

```bash
/path/to/repo/vulkan-run.sh --wined3d --proton -- "/path/game32.exe"
```

In Steam, for a 32-bit game: `PROTON_USE_WINED3D=1 %command%`.

---

## 5-bis. Heroic Games Launcher (Flatpak or native)

Works with **Heroic Flatpak and native Heroic**. The wrapper is the same; only
the preparation differs:

- **Flatpak**: it lives in a sandbox that cannot see `/dev/dri` or the Mesa
  folder, and it lacks 3 libraries the runtime does not ship.
  `prepare-heroic.sh` fixes that.
- **Native**: no sandbox, it already sees `/dev/dri` and `/usr/lib`; nothing is
  needed, the wrapper works as-is (the script only checks that RADV loads).

```bash
./prepare-heroic.sh     # detects whether Heroic is Flatpak or native
```

In Flatpak, that script (no root) does:

1. `flatpak override --user` to give Heroic `--device=all` and access to the
   repository folder and `~/mesa-versions`.
2. Copies to `mesa-versions/deps/` the 3 libraries missing from the runtime
   (`libdisplay-info.so.3`, `libSPIRV-Tools.so`, `libedit.so.0`).
3. Checks that RADV loads and sees the GPU (inside the sandbox or on the system,
   depending on the Heroic type).

Then, **for each game** (64-bit): Game settings (⚙) → **Advanced** →
**Wrapper command**:

```
Wrapper:    /path/to/repo/heroic-mesa.sh
Arguments:  (empty)
```

Optionally, in the same game's **Environment Variables**:

| Variable | Value | Effect |
|---|---|---|
| `HEROIC_MESA_HUD` | `fps` | DXVK FPS counter |
| `HEROIC_MESA` | `26.0.4` | use the other stable Mesa |
| `HEROIC_WINED3D` | `1` | **32-bit** games: OpenGL/wined3d |

Notes:

- Heroic does not ship Wine: install **Wine-GE** or **Proton-GE** first from
  *Wine Manager* (side menu). The wrapper works with both.
- Old RADV does not work for 32-bit (no LLVM 21/22 lib32): use
  `HEROIC_WINED3D=1`.
- If you reinstall Heroic, run `./prepare-heroic.sh` again.
- Native Heroic uses system libraries: `mesa-versions/deps/` is only needed in
  the Flatpak.
- The wrapper appends its paths to `LD_LIBRARY_PATH`, so it does not override
  the Wine libraries Heroic sets.

---

## 6. Check and diagnose

```bash
/path/to/repo/check.sh              # vulkaninfo + vkcube with each Mesa
/path/to/repo/check.sh 25.3.5       # only one version
/path/to/repo/vulkan-env.sh --show  # paths that would be used
tail -f /path/to/repo/activation.log  # activation history
```

### GPU monitor

`install.sh` and `vulkan-run.sh --monitor` start the monitor in the background.
It records `dmesg`, temperature, fan, VRAM/GTT, RAM, Xorg and the video
connector.

```bash
/path/to/repo/monitor/ps4-monitor-status.sh
/path/to/repo/monitor/ps4-monitor-stop.sh
```

If it detects a GPU hang, video loss, Xorg crash or out-of-memory event, it
writes a readable report **that survives a reboot**:

```
/path/to/repo/ps4-monitor-error.log
/path/to/repo/logs/ps4-monitor-error-<date>.log
```

The report explains what happened, the system state at that moment and what to
do (reboot, use Mesa 25.3.5, `--wined3d` for 32-bit, etc.). Full sessions are
kept in `logs/session-*.log`.

---

## 7. Revert / undo

Nothing is installed system-wide:

- Remove the Steam launch option → the system goes back to Mesa 26.0.8.
- `rm -rf ~/mesa-versions /path/to/repo ~/.local/share/vulkan-proton`
- Shortcuts: delete the `.desktop` files from `~/.local/share/applications`.
- Monitor: `./monitor/ps4-monitor-stop.sh`.

---

## 8. Add another Mesa version (optional)

1. Download the `mesa-ps4-<ver>-x86_64.pkg.tar.zst` package from the
   `ps4-video` (DionKill) repo at the matching commit.
2. Extract it: `mkdir mesa-<ver> && bsdtar -xf package.zst -C mesa-<ver>`
3. Extract its LLVM (`llvm-libs` package from Arch Archive) into `llvm-<N>/`.
4. Copy the ICD and point `library_path` at
   `~/mesa-versions/mesa-<ver>/usr/lib/libvulkan_radeon.so`.
5. `./check.sh <ver>` and, if it passes, use it with `--mesa <ver>`.

`vulkan-env.sh` detects the `libLLVM` each Mesa needs by reading the ELF.

---

## 9. Translation / development test

```bash
./tests/smoke-test.sh                # syntax, texts, Mesa selection, monitor
./tests/smoke-test.sh --with-vulkan  # also enumerates the GPU with each Mesa
```

The test checks that no personal paths or Spanish wording remain in the
scripts, that `fish`/`bash`/Python syntax is valid, that the monitor writes
reports, and that each Mesa produces a valid environment.

---

## 10. Notes

- Use of artificial intelligence in the project: [Info IA](use_of_AI.md)
- Mesa 26.0.8 is a build from the `ps4-video` repo; the PS4 patch only adds
  LIVERPOOL/GLADIUS as GFX7, so older Mesas from the same repo are compatible.
- The bug is in RADV, not in the kernel or the hardware: OpenGL and
  "light-load" Vulkan work fine.
- If the system Mesa is ever updated and the bug disappears, simply stop using
  the launcher (or use `--mesa` with the new version).
- This is a public repository: it contains no user paths or proprietary
  binaries. Examples use `/home/USER` and fictional paths.
