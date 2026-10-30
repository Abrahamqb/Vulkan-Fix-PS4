#!/bin/sh
# ============================================================================
#  heroic-mesa.sh — wrapper for Heroic Games Launcher (Flatpak or native)
#
#  Makes the game start with RADV from Mesa 25.3.5 (stable on this PS4)
#  instead of the system/runtime Mesa, without touching the system.
#
#  HOW TO USE IT IN HEROIC
#    Game settings (⚙) → Advanced → "Wrapper command"
#      Wrapper:    /path/to/repo/heroic-mesa.sh
#      Arguments:  (empty)
#
#  OPTIONAL VARIABLES (Advanced → Environment Variables for the game)
#    HEROIC_MESA=26.0.4     use the other stable Mesa
#    HEROIC_WINED3D=1      32-bit games: OpenGL (wined3d), no RADV
#    HEROIC_MESA_HUD=fps    show the DXVK FPS counter
#    HEROIC_MESA_DIR=DIR    Mesa directory override (default: automatic)
#
#  The repository path is detected automatically, so it can be cloned, moved
#  or renamed. This script runs INSIDE the Heroic Flatpak sandbox; that is why
#  access to the Mesa directory and this repository must be granted with
#  prepare-heroic.sh (or manually with flatpak override).
# ============================================================================
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
VER="${HEROIC_MESA:-25.3.5}"

# --- 32-bit games: OpenGL/wined3d, without touching Vulkan ------------------
if [ "${HEROIC_WINED3D:-0}" = "1" ]; then
  export PROTON_USE_WINED3D=1
  # Force Wine's d3d/gi (wined3d) even if the prefix has DXVK installed.
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}d3d9,d3d10core,d3d11,dxgi=b"
  printf 'heroic-mesa: wined3d (OpenGL) for a 32-bit game\n' >&2
  exec "$@"
fi

# --- locate Mesa (explicit override, repo copy, then ~/mesa-versions) -------
BASE=""
for b in "${HEROIC_MESA_DIR:-}" "$SELF_DIR/mesa-versions" "$HOME/mesa-versions"; do
  [ -n "$b" ] || continue
  if [ -f "$b/icd/mesa-$VER.json" ] && [ -f "$b/mesa-$VER/usr/lib/libvulkan_radeon.so" ]; then
    BASE="$b"; break
  fi
done
if [ -z "$BASE" ]; then
  printf 'heroic-mesa: cannot find Mesa %s (did you run install.sh?)\n' "$VER" >&2
  exec "$@"
fi
DEPS="$BASE/deps"

# --- ICD (fix an absolute path left over from a moved repository) -----------
ICD="$BASE/icd/mesa-$VER.json"
LIB="$BASE/mesa-$VER/usr/lib/libvulkan_radeon.so"
if ! grep -Fq "\"library_path\": \"$LIB\"" "$ICD" 2>/dev/null; then
  NEWDIR="$BASE/icd"
  [ -w "$NEWDIR" ] || NEWDIR="$SELF_DIR/run/icd"
  mkdir -p "$NEWDIR" 2>/dev/null || NEWDIR="${TMPDIR:-/tmp}/vulkan-solution-icd"
  mkdir -p "$NEWDIR" 2>/dev/null || true
  if [ -d "$NEWDIR" ]; then
    cat > "$NEWDIR/mesa-$VER.json" <<EOF 2>/dev/null && ICD="$NEWDIR/mesa-$VER.json"
{
    "ICD": {
        "api_version": "1.4.328",
        "library_arch": "64",
        "library_path": "$LIB"
    },
    "file_format_version": "1.0.1"
}
EOF
  fi
fi

# --- libLLVM required by this version ---------------------------------------
case "$VER" in
  25.3.5) LLVM="$BASE/llvm-21/usr/lib" ;;
  26.0.4) LLVM="$BASE/llvm-22/usr/lib" ;;
  *)      LLVM=$(ls -d "$BASE"/llvm-*/usr/lib 2>/dev/null | head -n1) ;;
esac
[ -d "$LLVM" ] || LLVM=""

# --- environment --------------------------------------------------------------
# APPEND so we do not override the Wine libraries that Heroic sets first.
LIBS="$BASE/mesa-$VER/usr/lib${LLVM:+:$LLVM}"
[ -d "$DEPS" ] && LIBS="$LIBS:$DEPS"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$LIBS"
export VK_DRIVER_FILES="$ICD"
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
[ -n "${HEROIC_MESA_HUD:-}" ] && export DXVK_HUD="$HEROIC_MESA_HUD"

printf 'heroic-mesa: Mesa %s | VK_DRIVER_FILES=%s\n' "$VER" "$VK_DRIVER_FILES" >&2

exec "$@"
