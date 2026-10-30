#!/bin/sh
# ============================================================================
#  vulkan-env.sh — select the Mesa/RADV used by Vulkan in THIS process only.
#
#  Why: on this PS4 (Liverpool GPU) RADV from Mesa 26.0.8 hangs the GPU
#  (ring gfx timeout / GPU Recovery Failed -110) with DXVK. Mesa 25.3.5 and
#  26.0.4 work. This script installs nothing and touches nothing system-wide:
#  it only points VK_DRIVER_FILES at a copy of Mesa inside this repository
#  (or ~/mesa-versions) and prepends that copy's libraries to LD_LIBRARY_PATH.
#
#  The repository is located automatically, so it can be cloned, moved or
#  renamed to anything and the scripts keep working.
#
#  USAGE
#    . /path/to/repo/vulkan-env.sh --mesa 25.3.5
#    . .../vulkan-env.sh --mesa 26.0.4 --hud fps
#    . .../vulkan-env.sh --show          (only print what would be used)
#    bash -c '. .../vulkan-env.sh; my_program'      (bash/sh/zsh)
#    source .../vulkan-env.fish                      (fish)
#
#  OPTIONS
#    --mesa VER | auto   Mesa version (default: 25.3.5; auto = 26.0.4)
#    --hud [VALUE]       Enable DXVK_HUD (default "fps,devinfo")
#    --show              Print MESA=... / VK_DRIVER_FILES=... and exit
#    -q | --quiet        No messages
#    -h | --help         This help
#
#  EXPORTS
#    VK_DRIVER_FILES   (modern Vulkan loader)
#    VK_ICD_FILENAMES  (compatibility with old loaders)
#    LD_LIBRARY_PATH   (libvulkan_radeon + its libLLVM)
#    VULKAN_MESA_ACTIVE
#    VULKAN_SOLUTION_DIR (repository this file belongs to)
#    DXVK_HUD          (only when --hud is given)
#
#  ENVIRONMENT
#    VULKAN_MESA_DIR     Mesa directory to use first (default: automatic)
#    VULKAN_SOLUTION_DIR repository directory (default: automatic)
# ============================================================================

# ------------------------- locate this repository ---------------------------
# Different shells expose the sourced file differently. Try, in order:
# BASH_SOURCE (bash), the zsh source file, $0 when run directly, and finally
# the current directory if it looks like this repository.
VK_SELF="${BASH_SOURCE-}"
case "$VK_SELF" in
  *vulkan-env.sh) : ;;
  *) VK_SELF="" ;;
esac
if [ -z "$VK_SELF" ] && [ -n "${ZSH_VERSION:-}" ]; then
  eval 'VK_SELF=${(%):-%x}' 2>/dev/null || VK_SELF=""
fi
if [ -z "$VK_SELF" ] && [ "$(basename "$0" 2>/dev/null)" = "vulkan-env.sh" ]; then
  VK_SELF="$0"
fi
if [ -z "$VK_SELF" ] && [ -f "$PWD/vulkan-env.sh" ]; then
  VK_SELF="$PWD/vulkan-env.sh"
fi
if [ -z "$VK_SELF" ] && { [ -f "$PWD/vulkan-run.sh" ] || [ -d "$PWD/mesa-versions" ]; }; then
  VK_SELF="$PWD/vulkan-env.sh"
fi

if [ -n "$VK_SELF" ] && [ -d "$(dirname "$VK_SELF")" ]; then
  VK_DIR=$(cd "$(dirname "$VK_SELF")" && pwd)
else
  VK_DIR=$(pwd)
fi

# VULKAN_SOLUCION is kept as an input alias for backwards compatibility.
VULKAN_SOLUTION_DIR="${VULKAN_SOLUTION_DIR:-${VULKAN_SOLUCION:-$VK_DIR}}"
VULKAN_SOLUCION="$VULKAN_SOLUTION_DIR"
export VULKAN_SOLUTION_DIR

VULKAN_MESA="${VULKAN_MESA:-25.3.5}"
VK_QUIET="${VK_QUIET:-0}"
VK_HUD="${VK_HUD:-}"
VK_SHOW=0
VK_AUTO=26.0.4

# Was this file executed directly or sourced? (bash/sh)
VK_EXECUTED=0
[ "$VK_SELF" = "$0" ] && VK_EXECUTED=1

vk_msg() { [ "$VK_QUIET" = 1 ] || printf '%s\n' "$*" >&2; }
vk_fail() { printf 'vulkan-env: %s\n' "$*" >&2; }
vk_help() {
  awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$VK_SELF" 2>/dev/null || true
}

_vk_main() {
  # ---------------------------- arguments ---------------------------------
  while [ $# -gt 0 ]; do
    case "$1" in
      --mesa)
        [ $# -ge 2 ] || { vk_fail "missing value for --mesa"; return 1; }
        VULKAN_MESA="$2"; shift 2 ;;
      --mesa=*) VULKAN_MESA="${1#*=}"; shift ;;
      --hud)
        if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then VK_HUD="$2"; shift 2
        else VK_HUD="fps,devinfo"; shift; fi ;;
      --hud=*) VK_HUD="${1#*=}"; shift ;;
      --show) VK_SHOW=1; shift ;;
      -q|--quiet) VK_QUIET=1; shift ;;
      -h|--help) vk_help; return 0 ;;
      --) shift; break ;;
      *) vk_fail "unknown option: $1 (use --help)"; return 1 ;;
    esac
  done

  [ "$VULKAN_MESA" = "auto" ] && VULKAN_MESA="$VK_AUTO"

  # ----------------------- locate Mesa and LLVM ----------------------------
  # Search order: explicit VULKAN_MESA_DIR, this repository's own copy, then
  # ~/mesa-versions (kept for old Steam launch options). The repository is
  # never assumed to have a particular name or location.
  vk_try_base() {
    [ -n "${1:-}" ] || return 1
    [ -f "$1/icd/mesa-$VULKAN_MESA.json" ] && \
      [ -f "$1/mesa-$VULKAN_MESA/usr/lib/libvulkan_radeon.so" ]
  }
  vk_base=""
  for b in "${VULKAN_MESA_DIR:-}" "$VULKAN_SOLUTION_DIR/mesa-versions" "$HOME/mesa-versions"; do
    if vk_try_base "$b"; then
      vk_base="$b"; break
    fi
  done

  if [ -z "$vk_base" ]; then
    disp=$( { for b in "${VULKAN_MESA_DIR:-}" "$VULKAN_SOLUTION_DIR/mesa-versions" "$HOME/mesa-versions"; do
                   [ -d "$b" ] && ls -d "$b"/mesa-* 2>/dev/null
                 done | sed 's#.*/mesa-##' | sort -u | tr '\n' ' '; } )
    vk_fail "cannot find Mesa $VULKAN_MESA. Available: ${disp:-none}"
    vk_fail "run install.sh or download-mesa.sh, or set VULKAN_MESA_DIR."
    return 1
  fi

  vk_mesa_lib="$vk_base/mesa-$VULKAN_MESA/usr/lib"
  vk_icd="$vk_base/icd/mesa-$VULKAN_MESA.json"
  vk_lib="$vk_mesa_lib/libvulkan_radeon.so"

  # The stored ICD contains an absolute path. If the repository was moved or
  # renamed after install, that path is stale; write a corrected ICD.
  if ! grep -Fq "\"library_path\": \"$vk_lib\"" "$vk_icd" 2>/dev/null; then
    vk_new_icd="$vk_base/icd"
    [ -w "$vk_new_icd" ] || vk_new_icd="$VULKAN_SOLUTION_DIR/run/icd"
    mkdir -p "$vk_new_icd" 2>/dev/null || vk_new_icd="${TMPDIR:-/tmp}/vulkan-solution-icd"
    mkdir -p "$vk_new_icd" 2>/dev/null || true
    if [ -d "$vk_new_icd" ]; then
      cat > "$vk_new_icd/mesa-$VULKAN_MESA.json" <<EOF 2>/dev/null && vk_icd="$vk_new_icd/mesa-$VULKAN_MESA.json"
{
    "ICD": {
        "api_version": "1.4.328",
        "library_arch": "64",
        "library_path": "$vk_lib"
    },
    "file_format_version": "1.0.1"
}
EOF
    fi
  fi

  # libLLVM required by this Mesa (libLLVM.so.NN)
  vk_need=""
  if command -v readelf >/dev/null 2>&1; then
    vk_need=$(readelf -d "$vk_mesa_lib/libvulkan_radeon.so" 2>/dev/null \
              | sed -n 's/.*libLLVM\.so\.\([0-9][0-9]*\).*/llvm-\1/p' | head -n1)
  fi
  if [ -z "$vk_need" ] && command -v strings >/dev/null 2>&1; then
    vk_need=$(strings "$vk_mesa_lib/libvulkan_radeon.so" 2>/dev/null \
              | sed -n 's/^libLLVM\.so\.\([0-9][0-9]*\).*/llvm-\1/p' | head -n1)
  fi

  vk_llvm_lib=""
  if [ -n "$vk_need" ]; then
    for b in "$vk_base" "${VULKAN_MESA_DIR:-}" "$VULKAN_SOLUTION_DIR/mesa-versions" "$HOME/mesa-versions"; do
      [ -n "$b" ] || continue
      if ls "$b/$vk_need"/usr/lib/libLLVM.so.* >/dev/null 2>&1; then
        vk_llvm_lib="$b/$vk_need/usr/lib"; break
      fi
    done
  fi

  if [ -z "$vk_llvm_lib" ]; then
    vk_fail "cannot find libLLVM ($vk_need) for Mesa $VULKAN_MESA"
    return 1
  fi

  # ------------------------------- export ----------------------------------
  vk_add_ld() {
    case ":${LD_LIBRARY_PATH-}:" in
      *":$1:"*) : ;;
      *) LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
    esac
  }
  vk_add_ld "$vk_mesa_lib"
  vk_add_ld "$vk_llvm_lib"
  export LD_LIBRARY_PATH

  # ---- optional 32-bit support --------------------------------------------
  # PE32 games need a 32-bit libvulkan_radeon.so. There is no old 32-bit Mesa
  # with its 32-bit libLLVM here, so this is normally 0 and vulkan-run warns
  # that --wined3d must be used.
  vk_lib32=""; vk_icd32=""
  for b in "$vk_base" "${VULKAN_MESA_DIR:-}" "$VULKAN_SOLUTION_DIR/mesa-versions" "$HOME/mesa-versions"; do
    [ -n "$b" ] || continue
    l32dir="$b/lib32-mesa-$VULKAN_MESA/usr/lib32"
    [ -f "$l32dir/libvulkan_radeon.so" ] || continue
    n32=$(readelf -d "$l32dir/libvulkan_radeon.so" 2>/dev/null \
          | sed -n 's/.*libLLVM\.so\.\([0-9][0-9]*\).*/\1/p' | head -n1)
    for c in "$b/lib32-llvm-$n32/usr/lib32" "$b/llvm32-$n32/usr/lib32"; do
      if ls "$c"/libLLVM.so."$n32".* >/dev/null 2>&1; then
        vk_lib32="$l32dir:$c"; break
      fi
    done
    [ -n "$vk_lib32" ] || continue
    for j in "$b/icd/mesa-$VULKAN_MESA.i686.json" "$b/lib32-mesa-$VULKAN_MESA/usr/share/vulkan/icd.d/radeon_icd.i686.json"; do
      [ -f "$j" ] && { vk_icd32="$j"; break; }
    done
    break
  done

  if [ -n "$vk_lib32" ]; then
    oldifs="$IFS"; IFS=:
    for d in $vk_lib32; do vk_add_ld "$d"; done
    IFS="$oldifs"
    export LD_LIBRARY_PATH
    VK_DRIVER_FILES="$vk_icd${vk_icd32:+:$vk_icd32}"
    VK_LIB32_SUPPORT=1
  else
    VK_DRIVER_FILES="$vk_icd"
    VK_LIB32_SUPPORT=0
  fi
  export VK_LIB32_SUPPORT

  export VK_DRIVER_FILES
  VK_ICD_FILENAMES="$VK_DRIVER_FILES"; export VK_ICD_FILENAMES
  VULKAN_MESA_ACTIVE="$VULKAN_MESA"; export VULKAN_MESA_ACTIVE
  [ -n "$VK_HUD" ] && { DXVK_HUD="$VK_HUD"; export DXVK_HUD; }

  # -------------------------------- --show ---------------------------------
  if [ "$VK_SHOW" = 1 ]; then
    printf 'MESA=%s\n' "$VULKAN_MESA"
    printf 'VULKAN_MESA_ACTIVE=%s\n' "$VULKAN_MESA_ACTIVE"
    printf 'VK_DRIVER_FILES=%s\n' "$VK_DRIVER_FILES"
    printf 'LD_LIBRARY_PATH=%s\n' "$LD_LIBRARY_PATH"
    [ -n "$VK_HUD" ] && printf 'DXVK_HUD=%s\n' "$VK_HUD"
    return 0
  fi

  # -------------------------------- log ------------------------------------
  VK_LOG="${VULKAN_LOG:-$VULKAN_SOLUTION_DIR/activation.log}"
  if [ -d "$(dirname "$VK_LOG" 2>/dev/null)" ]; then
    printf '%s mesa=%s shell=%s llvm=%s\n' \
      "$(date -Is)" "$VULKAN_MESA" "${0##*/}" "$(basename "$(dirname "$(dirname "$vk_llvm_lib")")")" \
      >> "$VK_LOG" 2>/dev/null || true
  fi

  vk_msg "vulkan-env: Mesa $VULKAN_MESA ($(basename "$vk_base")) | $(basename "$(dirname "$(dirname "$vk_llvm_lib")")")"
  [ -n "$VK_HUD" ] && vk_msg "vulkan-env: DXVK_HUD=$VK_HUD"
  return 0
}

_vk_main "$@"
_vk_status=$?
if [ "$VK_EXECUTED" = 1 ]; then
  [ "$VK_SHOW" != 1 ] && [ "$_vk_status" = 0 ] && {
    printf '%s\n' "Warning: executed directly; the variables only apply to that process." >&2
    printf '%s\n' "Use:  . $VK_SELF --mesa $VULKAN_MESA    (or vulkan-run.sh)" >&2
  }
  exit "$_vk_status"
fi
return "$_vk_status"
