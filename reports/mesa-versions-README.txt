Legacy Mesa builds for the PS4 (stable RADV with DXVK) — 2026-10-29
================================================================

Problem: Mesa 26.0.8 (ps4-video repo) hangs the GPU (ring gfx timeout,
dxvk-submit thread, GPU Recovery Failed -110) on the first DXVK frame.

Solution: use RADV from an older Mesa ONLY for the game.

Contents
--------
mesa-25.3.5/    Mesa 25.3.5 (commit 890b048a of the ps4-video repo) + LLVM 21.1.8
mesa-26.0.4/    Mesa 26.0.4 (commit 76d656a0 of the ps4-video repo) + LLVM 22.1.8
llvm-21/        libLLVM.so.21.1 (llvm-libs 21.1.8-1, archive.archlinux.org)
llvm-22/        libLLVM.so.22.1 (llvm-libs 22.1.8-2, archive.archlinux.org)
icd/*.json      Vulkan ICDs with an absolute library_path to each Mesa

Usage
-----
  VK_DRIVER_FILES=$HOME/mesa-versions/icd/mesa-25.3.5.json \
  LD_LIBRARY_PATH=$HOME/mesa-versions/mesa-25.3.5/usr/lib:$HOME/mesa-versions/llvm-21/usr/lib \
  <command>

or simply:  /path/to/repo/vulkan-run.sh --mesa 25.3.5 -- <command>
            /path/to/repo/vulkan-run.sh --mesa 26.0.4 -- <command>

None of this is installed system-wide: remove it with "rm -rf ~/mesa-versions".
