Legacy Mesa builds for the PS4 (stable RADV with DXVK)
======================================================

This folder is rebuilt by download-mesa.sh or install.sh. The binaries are not
committed to Git because some are larger than 100 MB.

Contents after installation
---------------------------
mesa-25.3.5/    Mesa 25.3.5 (ps4-video repo) + LLVM 21.1.8
mesa-26.0.4/    Mesa 26.0.4 (ps4-video repo) + LLVM 22.1.8
llvm-21/        libLLVM.so.21.1 (llvm-libs 21.1.8-1, archive.archlinux.org)
llvm-22/        libLLVM.so.22.1 (llvm-libs 22.1.8-2, archive.archlinux.org)
icd/*.json      Vulkan ICDs with an absolute library_path to each Mesa

Usage
-----
  /path/to/repo/vulkan-run.sh --mesa 25.3.5 -- <command>
  /path/to/repo/vulkan-run.sh --mesa 26.0.4 -- <command>

None of this is installed system-wide: remove it with "rm -rf ~/mesa-versions".
