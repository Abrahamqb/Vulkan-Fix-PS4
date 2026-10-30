#!/bin/bash
# ============================================================================
#  vulkan-run.sh — universal launcher (Steam, non-Steam games, anything)
#
#  Starts ANY program with the chosen Mesa/RADV, without touching the system.
#
#  USAGE
#    vulkan-run.sh [options] -- command [args...]
#    vulkan-run.sh [options] --proton -- "C:/path/game.exe" [args...]
#
#  OPTIONS
#    -m, --mesa VER     25.3.5 (default) | 26.0.4 | auto
#        --hud[=VALUE]  Show DXVK_HUD (default fps,devinfo)
#    -p, --proton       Run a .exe with Proton + Steam Linux Runtime
#        --prefix DIR   Wine prefix to use (default: one per game)
#        --appid N      Use the Steam compatdata/N prefix
#        --proton-dir D Proton folder (default: "Proton 8.0")
#        --log          Write the Proton log to <repo>/logs/proton/
#        --monitor      Start the GPU monitor if it is not running
#        --wined3d      Use OpenGL (wined3d) instead of Vulkan: for 32-bit
#                        games, where there is no stable 32-bit RADV
#        --force        Ignore the "32-bit game" warning
#    -h, --help         Help
#
#  EXAMPLES
#    vulkan-run.sh --mesa 25.3.5 -- vkcube
#    vulkan-run.sh --proton -- "/run/media/USER/External/Games/Example Game/game.exe"
#    vulkan-run.sh --proton --appid 123456 -- "$HOME/.local/share/Steam/steamapps/common/Example Game/Game.exe" -force-d3d11
#
#  In Steam (Launch Options):
#    /path/to/repo/vulkan-run.sh --mesa 25.3.5 -- %command% -force-d3d11
#
#  The repository is located automatically, so it can be cloned, moved or
#  renamed without editing anything.
# ============================================================================
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"

MESA="${VULKAN_MESA:-25.3.5}"
HUD=""
MODE="cmd"
PREFIX=""
APPID=""
PROTON_DIR=""
PROTON_LOG_ON=0
MONITOR=0
WINED3D=0
FORCE=0
GAME_ARGS=()

msg() { printf '%s\n' "$*" >&2; }
die() { msg "vulkan-run: $*"; exit 1; }
usage() {
  awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--mesa)     [ $# -ge 2 ] || die "missing value for --mesa"; MESA="$2"; shift 2 ;;
    --mesa=*)      MESA="${1#*=}"; shift ;;
    --hud=*)       HUD="${1#*=}"; shift ;;
    --hud)
      HUD="fps,devinfo"
      if [ $# -ge 2 ]; then
        case "$2" in
          fps|devinfo|frametimes|memory|gpuload|drawcalls|submissions|pipeline|descriptors|compiler|marker|full|1)
            HUD="$2"; shift ;;
          *,*) case "$2" in *[!a-z0-9,]*) : ;; *) HUD="$2"; shift ;; esac ;;
        esac
      fi
      shift ;;
    -p|--proton)   MODE="proton"; shift ;;
    --prefix)      [ $# -ge 2 ] || die "missing value for --prefix"; PREFIX="$2"; shift 2 ;;
    --appid)       [ $# -ge 2 ] || die "missing value for --appid"; APPID="$2"; shift 2 ;;
    --proton-dir)  [ $# -ge 2 ] || die "missing value for --proton-dir"; PROTON_DIR="$2"; shift 2 ;;
    --log)         PROTON_LOG_ON=1; shift ;;
    --monitor)     MONITOR=1; shift ;;
    --wined3d)     WINED3D=1; shift ;;
    --force)       FORCE=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; break ;;
    -*)            die "unknown option: $1 (use --help)" ;;
    *)             break ;;
  esac
done

[ $# -gt 0 ] || die "missing command (use --help)"

# ------------------------------ environment ---------------------------------
if [ "$WINED3D" = 1 ]; then
  # System OpenGL (radeonsi): stable, and it does have a 32-bit driver.
  export PROTON_USE_WINED3D=1
  msg "vulkan-run: wined3d mode (OpenGL, system Mesa)"
else
  # shellcheck disable=SC1090
  . "$SELF_DIR/vulkan-env.sh" --mesa "$MESA" ${HUD:+--hud="$HUD"} || exit 1
fi
: "${VULKAN_MESA_ACTIVE:=system}"

if [ "$MONITOR" = 1 ]; then
  mp="$SELF_DIR/run/monitor.pid"
  if [ -f "$mp" ] && kill -0 "$(cat "$mp" 2>/dev/null)" 2>/dev/null; then
    msg "vulkan-run: GPU monitor already running"
  elif [ -x "$SELF_DIR/monitor/ps4-monitor.sh" ]; then
    setsid nohup "$SELF_DIR/monitor/ps4-monitor.sh" >/dev/null 2>&1 < /dev/null &
    msg "vulkan-run: GPU monitor started ($SELF_DIR/logs)"
  fi
fi

# ----------------------------- command mode ----------------------------------
if [ "$MODE" = "cmd" ]; then
  msg "vulkan-run: Mesa $VULKAN_MESA_ACTIVE -> $*"
  exec "$@"
fi

# ------------------------------ Proton mode ----------------------------------
GAME="$1"; shift
[ -f "$GAME" ] || die "executable does not exist: $GAME"
GAME_DIR=$(cd "$(dirname "$GAME")" && pwd)
EXE="$GAME_DIR/$(basename "$GAME")"

# Proton to use
if [ -z "$PROTON_DIR" ]; then
  PROTON_DIR="$STEAM_ROOT/steamapps/common/Proton 8.0"
  if [ ! -d "$PROTON_DIR" ]; then
    PROTON_DIR=$(ls -d "$STEAM_ROOT"/steamapps/common/Proton\ * 2>/dev/null | head -n1 || true)
  fi
fi
[ -n "$PROTON_DIR" ] && [ -x "$PROTON_DIR/proton" ] || die "cannot find Proton in '$PROTON_DIR'"

SNIPER="$STEAM_ROOT/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point"

# Wine prefix
if [ -n "$APPID" ]; then
  PREFIX="$STEAM_ROOT/steamapps/compatdata/$APPID"
elif [ -z "$PREFIX" ]; then
  slug=$(basename "$GAME_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')
  [ -n "$slug" ] || slug="game"
  PREFIX="$HOME/.local/share/vulkan-proton/$slug"
fi
mkdir -p "$PREFIX" "$(dirname "$PREFIX")"

export STEAM_COMPAT_DATA_PATH="$PREFIX"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT"
export STEAM_COMPAT_INSTALL_PATH="$GAME_DIR"
export STEAM_COMPAT_APP_ID="${APPID:-}"

if [ "$PROTON_LOG_ON" = 1 ]; then
  export PROTON_LOG=1
  export PROTON_LOG_DIR="${PROTON_LOG_DIR:-$SELF_DIR/logs/proton}"
  mkdir -p "$PROTON_LOG_DIR"
fi

msg "vulkan-run: Mesa $VULKAN_MESA_ACTIVE | Proton $(basename "$PROTON_DIR") | prefix $PREFIX"
msg "vulkan-run: $EXE $*"

# Warning for 32-bit executables (PE32): no old 32-bit RADV is available.
if [ "$WINED3D" != 1 ] && [ "${VK_LIB32_SUPPORT:-0}" != 1 ] && [ "$FORCE" != 1 ]; then
  if file -b "$EXE" 2>/dev/null | grep -q 'PE32 executable'; then
    msg "vulkan-run: WARNING — '$EXE' is 32-bit."
    msg "vulkan-run: only the 32-bit RADV from Mesa 26.0.8 is available (the one that hangs)."
    msg "vulkan-run: use --wined3d (OpenGL, stable) or --force to try anyway."
    exit 2
  fi
fi

cd "$GAME_DIR" || die "cannot enter $GAME_DIR"

if [ -x "$SNIPER" ]; then
  exec "$SNIPER" --verb=waitforexitandrun -- "$PROTON_DIR/proton" waitforexitandrun "$EXE" "$@"
else
  msg "vulkan-run: warning, SteamLinuxRuntime_sniper not found; using proton run directly"
  exec "$PROTON_DIR/proton" run "$EXE" "$@"
fi
