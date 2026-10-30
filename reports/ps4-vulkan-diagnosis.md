# PS4 Slim Baikal diagnosis — Vulkan / Proton / Steam

Date: 2026-10-29 · Device: PS4-Artix · Kernel `7.0.8-Strawberry-FullLTO-Baikal-+`

> ## ✅ SOLUTION (resolved on 29/10 at 22:15)
>
> The hang is caused by **RADV from Mesa 26.0.8**. With **Mesa 25.3.5** (or
> **26.0.4**) the game runs fullscreen with DXVK/ACO, without hangs:
>
> - **Universal launcher + all the material:** `/path/to/repo/`
>   (`vulkan-env.sh` for `source`, `vulkan-run.sh` for any game, reports, a copy
>   of `mesa-versions` and the complete guide in `README.md`).
> - **Steam launch option** (Properties → Launch Options):
>   ```
>   VK_DRIVER_FILES=/home/USER/mesa-versions/icd/mesa-25.3.5.json LD_LIBRARY_PATH=/home/USER/mesa-versions/mesa-25.3.5/usr/lib:/home/USER/mesa-versions/llvm-21/usr/lib %command% -force-d3d11
>   ```
> - Only affects that game: the system keeps its Mesa 26.0.8.
> - To use Mesa 26.0.4 instead:
>   `/path/to/repo/vulkan-run.sh --mesa 26.0.4 -- %command%`
>   (ICD `mesa-26.0.4.json` and `llvm-22/usr/lib`).
>
> See **§5-quater** for the tests and results.

## 1. Executive summary

The graphics stack **is properly installed and works**:

| Component | Status |
|---|---|
| amdgpu (GPU `1002:9923` Liverpool) | OK, `/dev/dri/card0` and `renderD128` nodes |
| OpenGL (radeonsi/ACO, Mesa 26.0.8) | OK, 4.5 core, `glxgears` works |
| Vulkan RADV 64-bit and 32-bit | OK, Vulkan 1.3.335 / loader 1.4.363 |
| `vkcube` 64-bit | OK (renders until killed) |
| DXVK 2.3 (D3D11) | OK, `d3ddriverquery64.exe` exits with EXIT=0 |
| VKD3D-Proton 2.11 (D3D12) | **FAILS**: `D3D12CreateDevice 0x80070057`, feature level 12_0 unsupported |
| Real game (Pineapple on pizza, Unity + D3D12) | **HANGS THE GPU** |

The problem **is not Vulkan**. Under real 3D load, the amdgpu graphics ring
hangs and the driver **cannot recover**:

```
amdgpu 0000:00:01.0: ring gfx timeout, signaled seq=208812, emitted seq=208815
amdgpu 0000:00:01.0: GPU reset begin!. Source: 1
amdgpu 0000:00:01.0: GPU reset succeeded, trying to resume
amdgpu 0000:00:01.0: VRAM is lost due to GPU reset!
amdgpu 0000:00:01.0: [drm:amdgpu_ring_test_helper] *ERROR* ring gfx test failed (-110)
amdgpu 0000:00:01.0: resume of IP block <gfx_v7_0> failed -110
amdgpu 0000:00:01.0: GPU Recovery Failed: -110
```

After that, `glxinfo` and `vkcube` hang (timeout). **The only recovery is a
reboot** (or writing 1 to `/sys/class/drm/card0/device/reset` as root).

## 2. Probable causes (ordered by evidence)

1. **`amdgpu.dpm=0` + `radeon.dpm=0` in the boot arguments.**
   DPM (dynamic clock/voltage management) is disabled. dmesg shows
   `Liverpool CLK: readback DID mismatch — expected 1 got 0`, meaning the clock
   programming of the Liverpool block is not being verified. Without DPM the
   clocks stay fixed and the hardware can enter an invalid state under load.
   **Prime suspect.**

2. **Temperature at the limit.** `temp1_input = 80–83 °C` with `temp1_crit = 80 °C`
   (ps4-fan sensor). There is no thermal shutdown, but the fan went from 13 to
   90 during the test. A gfx ring hang due to thermal/voltage instability is
   plausible on a console with dried thermal paste.

3. **Memory pressure.** Total RAM 4.8 GiB, **swap = 0**, VRAM = 3 GiB.
   During game startup about 2.4 GiB were free. Unity + DXVK + Proton need more;
   without swap, OOM or fragmentation can cause strange failures. The payload
   also reserves 3 GiB of VRAM, taking it away from the system.

4. **Unity's D3D12 path.** The game ships `D3D12/D3D12Core.dll` and
   `D3D12SDKPath`. VKD3D-Proton 2.11 (Proton 8.0) **does not support** the
   feature level the GPU requests: this is a known, separate failure, not
   related to the hang.

5. **`ps4-mesa-lock: built without PS4_MESA_LOCK_TOKEN`.** The packaged Mesa is
   a custom PS4 build that expects a verification token. It does not block
   Vulkan/GL here, but it shows the build is not "clean".

6. **Very new kernel (7.0.8) with Mesa 26.0.8**: a poorly tested combination on
   Liverpool; a possible `gfx_v7_0`/amdgpu regression.

## 3. What is NOT the problem

- Vulkan is present: ICDs `radeon_icd.x86_64.json` and `radeon_icd.i686.json`
  load.
- It is not permissions: the user is in `video`, `render` is 666, `renderD128` is
  OK.
- It is not the Steam runtime: `vulkaninfo`, `vkcube` and DXVK 2.3 work.
- It is not the game: any sustained 3D load can trigger the same hang.

## 4. Proposed correction plan

### Phase A — no root (can be done now)
- Add `-force-d3d11` to the launch options of Pineapple on pizza.
- Add `RADV_DEBUG=nocompute` (and optionally `mesa_glthread=true`) to the
  graphical session environment.
- Watch temperature/fan during tests.

### Phase B — with root (requires password)
- **Create 4–8 GiB of swap** in `/swapfile` (or zram). Essential with 4.8 GiB.
- **Remove `amdgpu.dpm=0` and `radeon.dpm=0`** from `bootargs.txt` (with a
  backup). Let DPM manage clocks; this is the most important test.
- Optional: create `vram.txt` with `2048` to give 1 GiB back to system RAM
  (at the cost of VRAM; 3 GiB is tight for Unity but 2 GiB may be worse).
- Optional: install `vulkan-tools` and the native `mesa-vulkan-radeon` package.

### Phase C — if it persists
- Try Proton Experimental / GE-Proton (better VKD3D, more extensions).
- Try another kernel (an older one) to rule out a `gfx_v7_0` regression.
- Clean/replace the thermal paste if the temperature stays at 80 °C idle.

## 5. Pending tests (after rebooting)

1. `vulkaninfo --summary` 64/32-bit → confirm the device.
2. `vkcube` 64-bit for 60 s → does it survive sustained load without DPM?
3. Game with `-force-d3d11` + `dmesg`/temperature monitor.
4. Repeat with DPM enabled (without `amdgpu.dpm=0`).
5. If D3D12 is mandatory, update Proton/VKD3D and verify feature level 12_0.

## 5-bis. Evidence captured with a persistent log (29/10 21:23)

Continuous monitoring was added (`ps4-monitor`, logs in `logs/`) with `dmesg -w`,
temperature, fan, VRAM/GTT, memory, Xorg and connector state every second/5 s.

Test: game with `-force-d3d11` under Proton 8.0 (DXVK/RADV/ACO), launch at 21:23:39.

```
21:23:49  vram_used = 241 MB   (DXVK initializing)
21:23:58  vram_used = 615 MB   (first frame / texture upload)
21:23:59  amdgpu: ring gfx timeout, signaled seq=91154, emitted seq=91156
21:23:59  amdgpu:  Process Pineapple on pi pid 5221 thread dxvk-submit pid 5333
21:23:59  GPU reset begin!  ->  VRAM is lost due to GPU reset!
21:23:59  ring gfx test failed (-110) / GPU Recovery Failed: -110
21:24:12  xrandr stops responding (Xorg blocked)  -> black screen / no signal
```

- `temp` at the moment of failure: **69 °C** → not thermal.
- `glxgears` at 1080p without vsync: **1621 FPS** → clocks are NOT limited;
  the "slow GPU hits the timeout" hypothesis is ruled out.
- The hanging work is submitted by **dxvk-submit** (DXVK over RADV).

### Comparative tests (same game)

| Configuration | Result |
|---|---|
| DXVK + RADV **ACO** (default) | **Total GPU hang** after ~20 s |
| DXVK + `RADV_DEBUG=llvm` | No hang, but `vkCreateGraphicsPipelines` fails (assert in winevulkan) and the game exits with rc=3 |
| DXVK + LLVM + GPL disabled | Same: `vkCreateGraphicsPipelines` fails |
| **wined3d (OpenGL)** `PROTON_USE_WINED3D=1` | **WORKS**: 120 s, scene rendered, no hangs, 75 °C |
| **Mesa 25.3.5 + DXVK/ACO** (RADV) | **WORKS**: 90 s + 35 s + 150 s + 70 s (via sniper) + 75 s (launcher) without a single failure |
| **Mesa 26.0.4 + DXVK/ACO** (RADV) | **WORKS**: 60 s + 180 s, 35 FPS in scene, without a single failure |

Conclusion: the problem is in the **Vulkan (RADV) path of this Mesa 26.0.8 with
gfx7 "Liverpool"**. OpenGL (radeonsi) is stable.

## 5-ter. Plan C: wined3d (OpenGL) — alternative without Vulkan

Steam launch option for the game:

```
PROTON_USE_WINED3D=1 %command% -force-d3d11
```

or from a terminal:

```
PROTON_USE_WINED3D=1 DXVK_HUD=1 \
  "$HOME/.local/share/Steam/steamapps/common/Proton 8.0/proton" run \
  "Pineapple on pizza.exe" -force-d3d11
```

Cost: wined3d translates D3D11 to OpenGL, slower than DXVK, but stable.

## 5-quater. REAL SOLUTION: Mesa 25.3.5 (or 26.0.4) only for the game

### How it was done (no root, no system packages touched)

The `ps4-video` repo (DionKill) only publishes Mesa 26.0.8 today, but its Git
history has binaries of older versions. They were downloaded and extracted into
`~/mesa-versions/`:

| Version | Source | Required LLVM |
|---|---|---|
| Mesa 25.3.5 | commit `890b048a` of the repo (tag 25.3.5) | `libLLVM.so.21.1` (`llvm-libs 21.1.8`, Arch Archive) |
| Mesa 26.0.4 | commit `76d656a0` of the repo | `libLLVM.so.22.1` (`llvm-libs 22.1.8`, Arch Archive) |

Each version has its own ICD with an absolute path:

```
~/mesa-versions/icd/mesa-25.3.5.json
~/mesa-versions/icd/mesa-26.0.4.json
```

and is selected **only for the game process** with:

```bash
export VK_DRIVER_FILES=$HOME/mesa-versions/icd/mesa-25.3.5.json
export LD_LIBRARY_PATH=$HOME/mesa-versions/mesa-25.3.5/usr/lib:$HOME/mesa-versions/llvm-21/usr/lib
```

The rest of the system (Xorg, desktop, video, OpenGL) keeps using the installed
Mesa 26.0.8; no package or `/etc` file was modified.

Previous checks: `vulkaninfo --summary` and `vkcube` detect
`AMD Liverpool (PlayStation 4) (RADV LIVERPOOL)` with both versions.

### Results (same game, `-force-d3d11`, Proton 8.0, DXVK/ACO, 1920×1080)

| RADV version | Total tested time | Result | FPS |
|---|---|---|---|
| 26.0.8 (system) | ~10–20 s per attempt | **hang** `ring gfx timeout` in `dxvk-submit` | — |
| **25.3.5** | 90 + 35 + 150 + 70 + 75 s | **stable**, 0 dmesg failures | 52 FPS logo / 33 FPS scene |
| **26.0.4** | 60 + 180 s | **stable**, 0 dmesg failures | 60 FPS load / 35 FPS scene |

Every test showed the playable scene rendered (screenshots in `/tmp/fps30.png`,
`/tmp/fps60.png`, `/tmp/m2604b155.png`) and the temperature stayed at 68–75 °C.
The persistent log did not record a single `ring gfx timeout`.

It was also verified that it **works through the Steam container**
(`SteamLinuxRuntime_sniper`): `_v2-entry-point` propagates the user's
`LD_LIBRARY_PATH` as `PRESSURE_VESSEL_APP_LD_LIBRARY_PATH`, and DXVK inside the
container reports `Driver : radv 25.3.5`. There is no glibc version problem.

### Daily use

**Option A — launcher (recommended, does not depend on Steam):**

```bash
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command%
/path/to/repo/vulkan-run.sh --mesa 26.0.4 -- %command%
/path/to/repo/vulkan-run.sh --mesa 25.3.5 --hud=fps -- %command%
```

Or loading the environment in the shell: `source /path/to/repo/vulkan-env.fish`
(fish) / `. /path/to/repo/vulkan-env.sh` (bash/sh).

**Option B — from Steam** (game Properties → Launch Options):

```
VK_DRIVER_FILES=/home/USER/mesa-versions/icd/mesa-25.3.5.json LD_LIBRARY_PATH=/home/USER/mesa-versions/mesa-25.3.5/usr/lib:/home/USER/mesa-versions/llvm-21/usr/lib %command% -force-d3d11
```

For Mesa 26.0.4, change `mesa-25.3.5`→`mesa-26.0.4`, `llvm-21`→`llvm-22` and the
`.json`.

**Check which Mesa the game is using:** `DXVK_HUD=devinfo,fps` (top-left corner)
should say `Mesa 25.3.5 (git-39f24bf409)`.

**Go back:** remove the launch option (or stop using the launcher). Nothing is
installed system-wide to undo. To free space:
`rm -rf ~/mesa-versions` (~250 MB).

Notes:
- Do not update the system Mesa to 26.x while this bug is present; if it is
  updated, the launcher will keep working because it uses its own copies.
- This bug affects RADV; OpenGL (wined3d) never failed, which is why the
  `PROTON_USE_WINED3D=1` alternative (§5-ter) remains valid as plan C.

## 6. Incident record

- `/tmp/dmesg-ps4.txt`: dump with the `ring gfx timeout` and the failed recovery.
- Approximate failure time: uptime 1579 s (≈20:55), 60 s after launching the game.
- State afterwards: unrecoverable GPU, `glxinfo`/`vkcube` timeout.

## 7. Launchers and delivered material (29/10, 22:50)

```
/path/to/repo/
├── README.md              complete guide (usage, Steam, non-Steam, revert)
├── vulkan-env.sh          core: selects Mesa (load with source)
├── vulkan-env.fish        fish equivalent
├── vulkan-run.sh          universal launcher (Steam / non-Steam / any command)
├── check.sh               vulkaninfo + vkcube with each version
├── steam-options.txt      ready-to-paste Steam texts
├── activation.log         activation history
├── monitor/               ps4-monitor (background GPU/video monitor)
├── mesa-versions/         self-contained copy (Mesa 25.3.5, 26.0.4, LLVM 21/22, ICDs)
└── reports/               this report + timeline + historical monitor logs
```

Desktop and application-menu shortcuts:
*Vulkan Solution* and *Check Vulkan*.

Ways to use it:

```bash
# fish
source /path/to/repo/vulkan-env.fish --mesa 25.3.5
# bash/sh
. /path/to/repo/vulkan-env.sh --mesa 26.0.4 --hud fps
# any command
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- command ...
```

Steam (launch options):

```
/path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command% -force-d3d11
```

or with source:

```
bash -c '. /path/to/repo/vulkan-env.sh --mesa 25.3.5; exec "$@"' _ %command% -force-d3d11
```

### Known limitation: 32-bit games

A PE32 executable needs a 32-bit `libvulkan_radeon.so`. There is no
`lib32-llvm` 21.x/22.x (only 23.x), so Mesa 25.3.5/26.0.4 cannot be used in
32-bit. For those games (GTA San Andreas, PES, …) use **wined3d (OpenGL)**,
which is stable:

```bash
/path/to/repo/vulkan-run.sh --wined3d --proton -- "/path/game32.exe"
```

Verified with GTA San Andreas: it starts and renders without hangs.
