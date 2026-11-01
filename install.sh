#!/bin/bash
# ============================================================================
#  install.sh — one-shot installer for Vulkan Solution (PS4 / Arch)
#
#  What it does:
#    1. Detects the distribution. This project is only supported on Arch Linux
#       and Arch-based distributions that use pacman. On anything else it warns
#       and asks whether to continue.
#    2. Checks/installs the required tools.
#    3. Starts the PS4 monitor in the background (so a GPU/video failure is
#       recorded even if this installer is interrupted).
#    4. Downloads Mesa 25.3.5 and 26.0.4 plus their LLVM libraries.
#    5. Runs a general RADV check and then verifies every Mesa version
#       individually.
#    6. Reports the result, writes logs, and explains how to use everything.
#
#  If the screen goes black or the PS4 hangs, look for this file in the repo:
#      ps4-monitor-error.log
#  It contains the error detected by ps4-monitor and the last kernel lines.
#
#  USAGE
#    ./install.sh                 # interactive
#    ./install.sh --yes           # accept all questions
#    ./install.sh --skip-download # use the Mesa copies already present
#    ./install.sh --skip-tests    # do not run Vulkan tests
#    ./install.sh --no-monitor    # do not start the background monitor
#    ./install.sh --no-desktop    # do not install menu shortcuts
#    ./install.sh --dry-run       # show what would be done and exit
#    ./install.sh --help
# ============================================================================
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
LOG_DIR="$ROOT/logs"
RUN_DIR="$ROOT/run"
mkdir -p "$LOG_DIR" "$RUN_DIR"

TS=$(date +%Y%m%d-%H%M%S)
INSTALL_LOG="$LOG_DIR/install-$TS.log"
MARKER="$RUN_DIR/install-start-$TS"
ERROR_REPORT="$ROOT/ps4-monitor-error.log"

ASSUME_YES=0
SKIP_DOWNLOAD=0
SKIP_TESTS=0
START_MONITOR=1
INSTALL_DESKTOP=1
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)       ASSUME_YES=1; shift ;;
    --skip-download) SKIP_DOWNLOAD=1; shift ;;
    --skip-tests)   SKIP_TESTS=1; shift ;;
    --no-monitor)   START_MONITOR=0; shift ;;
    --no-desktop)   INSTALL_DESKTOP=0; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    -h|--help)
      awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
      exit 0 ;;
    *) echo "install: unknown option: $1 (use --help)" >&2; exit 2 ;;
  esac
done

# Everything from here on is also saved to the install log.
exec > >(tee -a "$INSTALL_LOG") 2>&1

FAILED=0
MONITOR_STARTED=0
CHECK_FAILED=0
DOWNLOAD_FAILED=0
VERS=()

confirm() { # prompt, default (y/n)
  local prompt="$1" default="${2:-n}" answer
  if [ "$ASSUME_YES" = 1 ]; then
    echo "$prompt [y/N] y (--yes)"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "$prompt [y/N] n (no terminal; use --yes to accept)"
    return 1
  fi
  printf '%s [y/N] ' "$prompt"
  read -r answer || answer=""
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) [ "$default" = "y" ] && return 0; return 1 ;;
  esac
}

finish() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    local errfile="$LOG_DIR/install-error-$TS.log"
    {
      echo "=============================================================="
      echo " INSTALL FAILED — $(date -Is)"
      echo "=============================================================="
      echo "Exit status: $rc"
      echo
      echo "Last 60 lines of the install log:"
      tail -60 "$INSTALL_LOG" 2>/dev/null
      echo
      echo "Full install log: $INSTALL_LOG"
      [ -f "$ERROR_REPORT" ] && echo "Monitor error report: $ERROR_REPORT"
    } > "$errfile" 2>&1
    echo
    echo "install: FAILED. Error summary: $errfile"
  fi
  rm -f "$MARKER" 2>/dev/null || true
}
trap finish EXIT

touch "$MARKER" 2>/dev/null || true

echo "=============================================================="
echo " Vulkan Solution — installer"
echo " Repository: $ROOT"
echo " Log:        $INSTALL_LOG"
echo " Date:       $(date -Is)"
echo "=============================================================="
echo

# ---------------------------------------------------------------------------
# 1) Distribution detection
# ---------------------------------------------------------------------------
OS_ID="unknown"; OS_LIKE=""; OS_NAME="unknown"
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
fi

SUPPORTED=0
case " $OS_ID $OS_LIKE " in
  *" arch "*|*" artix "*|*" endeavouros "*|*" manjaro "*|*" garuda "*|*" cachyos "*)
    SUPPORTED=1 ;;
esac
command -v pacman >/dev/null 2>&1 || SUPPORTED=0

echo "Distribution: $OS_NAME (ID=$OS_ID${OS_LIKE:+, ID_LIKE=$OS_LIKE})"
if [ "$SUPPORTED" = 1 ]; then
  echo "[OK] Arch-based distribution with pacman detected."
else
  echo
  echo "WARNING: this installer is only supported on Arch Linux and"
  echo "         Arch-based distributions that use pacman."
  echo "         Detected: $OS_NAME"
  echo
  echo "         On Debian/Ubuntu/Fedora/etc. the scripts can still be used"
  echo "         manually, but package names and paths will differ."
  echo
  if ! confirm "Do you want to continue anyway?" n; then
    echo "Aborted by the user."
    exit 1
  fi
fi
echo

if [ "$DRY_RUN" = 1 ]; then
  echo "DRY RUN — no download, no monitor, no tests, no changes."
  echo "Planned Mesa directory: $ROOT/mesa-versions"
  echo "Planned logs:           $LOG_DIR"
  echo "Would download:        Mesa 25.3.5 + LLVM 21, Mesa 26.0.4 + LLVM 22"
  echo "Would verify:          general check + each version individually"
  [ "$START_MONITOR" = 1 ] && echo "Would start:           monitor/ps4-monitor.sh"
  [ "$INSTALL_DESKTOP" = 1 ] && echo "Would install:         desktop shortcuts in ~/.local/share/applications"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2) Required tools
# ---------------------------------------------------------------------------
echo "--- Checking required tools ------------------------------------"
declare -A PKG_FOR=(
  [curl]=curl [bsdtar]=libarchive [readelf]=binutils [sha256sum]=coreutils
  [ldd]=glibc [file]=file [awk]=gawk [timeout]=coreutils [flock]=util-linux
)
MISSING_PKGS=()
for cmd in curl bsdtar readelf sha256sum ldd file awk timeout; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  missing: $cmd"
    MISSING_PKGS+=("${PKG_FOR[$cmd]:-$cmd}")
  fi
done
command -v flock >/dev/null 2>&1 || MISSING_PKGS+=("${PKG_FOR[flock]}")

OPTIONAL_PKGS=()
command -v vulkaninfo >/dev/null 2>&1 || OPTIONAL_PKGS+=(vulkan-tools)
command -v vkcube >/dev/null 2>&1 || OPTIONAL_PKGS+=(vulkan-tools)
command -v glxinfo >/dev/null 2>&1 || OPTIONAL_PKGS+=(mesa-utils)
command -v xrandr >/dev/null 2>&1 || OPTIONAL_PKGS+=(xorg-xrandr)

# Print unique, non-empty entries so an empty array never turns into a bogus
# package name (printf with no arguments still emits one empty line).
dedupe_pkgs() {
  local -a items=()
  local item
  for item in "$@"; do
    [ -n "$item" ] && items+=("$item")
  done
  [ ${#items[@]} -gt 0 ] || return 0
  printf '%s\n' "${items[@]}" | sort -u
}

if [ ${#MISSING_PKGS[@]} -gt 0 ] || [ ${#OPTIONAL_PKGS[@]} -gt 0 ]; then
  # Remove duplicates and empty entries.
  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    mapfile -t MISSING_PKGS < <(dedupe_pkgs "${MISSING_PKGS[@]}")
  fi
  if [ ${#OPTIONAL_PKGS[@]} -gt 0 ]; then
    mapfile -t OPTIONAL_PKGS < <(dedupe_pkgs "${OPTIONAL_PKGS[@]}")
  fi
  if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "  Required packages missing: ${MISSING_PKGS[*]}"
    if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
      echo "ERROR: install them manually with pacman (no sudo found):" >&2
      echo "  pacman -S --needed ${MISSING_PKGS[*]}" >&2
      exit 1
    fi
    if confirm "Install them with pacman now?" y; then
      if [ "$(id -u)" -eq 0 ]; then
        pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || { echo "ERROR: pacman failed." >&2; exit 1; }
      else
        sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}" || { echo "ERROR: pacman failed." >&2; exit 1; }
      fi
    else
      echo "ERROR: required tools are missing." >&2
      exit 1
    fi
  fi
  if [ ${#OPTIONAL_PKGS[@]} -gt 0 ]; then
    echo "  Optional tools missing: ${OPTIONAL_PKGS[*]}"
    if confirm "Install optional tools now (recommended for the checks)?" y; then
      if [ "$(id -u)" -eq 0 ]; then
        pacman -S --needed --noconfirm "${OPTIONAL_PKGS[@]}" || echo "  WARNING: optional packages were not installed; checks may be limited."
      else
        sudo pacman -S --needed --noconfirm "${OPTIONAL_PKGS[@]}" || echo "  WARNING: optional packages were not installed; checks may be limited."
      fi
    fi
  fi
else
  echo "  all required tools are present"
fi
echo

# ---------------------------------------------------------------------------
# 3) Start the monitor before doing anything risky
# ---------------------------------------------------------------------------
if [ "$START_MONITOR" = 1 ]; then
  echo "--- Starting PS4 monitor in the background ---------------------"
  if [ -x "$ROOT/monitor/ps4-monitor.sh" ]; then
    "$ROOT/monitor/ps4-monitor.sh" || true
    for _ in 1 2 3 4 5; do
      [ -f "$RUN_DIR/main.pid" ] && kill -0 "$(cat "$RUN_DIR/main.pid" 2>/dev/null)" 2>/dev/null && break
      sleep 1
    done
    if [ -f "$RUN_DIR/main.pid" ] && kill -0 "$(cat "$RUN_DIR/main.pid" 2>/dev/null)" 2>/dev/null; then
      MONITOR_STARTED=1
      echo "  monitor running (pid $(cat "$RUN_DIR/main.pid"))"
      echo "  session log: $(cat "$RUN_DIR/current" 2>/dev/null)"
    else
      echo "  WARNING: monitor did not start; continuing without it."
    fi
  else
    echo "  WARNING: monitor/ps4-monitor.sh is missing; continuing without it."
  fi
  echo
fi

# ---------------------------------------------------------------------------
# 4) Download Mesa
# ---------------------------------------------------------------------------
echo "--- Mesa directories -------------------------------------------"
DEST="$ROOT/mesa-versions"
USER_MESA="$HOME/mesa-versions"
if [ -e "$USER_MESA" ]; then
  if [ -L "$USER_MESA" ]; then
    DEST="$(readlink -f "$USER_MESA" 2>/dev/null || echo "$DEST")"
    echo "  using existing symlink: $USER_MESA -> $DEST"
  else
    echo "  found existing directory: $USER_MESA"
    if confirm "Use that directory for this installation instead of the repository copy?" y; then
      DEST="$USER_MESA"
    else
      echo "  NOTE: the scripts use the repository copy first, then ~/mesa-versions."
    fi
  fi
else
  echo "  will download into $DEST"
fi

if [ "$SKIP_DOWNLOAD" = 1 ]; then
  echo "  --skip-download: keeping the Mesa copies already present."
  if [ ! -d "$DEST" ]; then
    echo "ERROR: $DEST does not exist and --skip-download was used." >&2
    exit 1
  fi
else
  echo "--- Downloading Mesa 25.3.5 and 26.0.4 -------------------------"
  if ! "$ROOT/download-mesa.sh" --dest "$DEST"; then
    DOWNLOAD_FAILED=1
    echo "ERROR: download/extract failed." >&2
  fi
fi

if [ "$DOWNLOAD_FAILED" != 0 ]; then
  echo "Cannot continue while Mesa files are missing." >&2
  exit 1
fi

# Create a ~/mesa-versions symlink only when that path is free, so the legacy
# Steam launch options and ~/mesa-versions keep pointing at the same files.
if [ ! -e "$USER_MESA" ] && [ ! -L "$USER_MESA" ] && [ "$DEST" = "$ROOT/mesa-versions" ]; then
  if ln -s "$DEST" "$USER_MESA" 2>/dev/null; then
    echo "  created symlink: $USER_MESA -> $DEST"
  fi
fi
echo

# Keep only real version lines; a diagnostic message must never be treated as
# a Mesa version.
mapfile -t VERS < <("$ROOT/check.sh" --list 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+$' || true)
if [ ${#VERS[@]} -eq 0 ]; then
  echo "ERROR: no Mesa versions found after the download." >&2
  exit 1
fi
echo "Available versions: ${VERS[*]}"
echo

# ---------------------------------------------------------------------------
# 5) General check, then each version individually
# ---------------------------------------------------------------------------
if [ "$SKIP_TESTS" = 1 ]; then
  echo "--- Verification skipped (--skip-tests) -----------------------"
else
  echo "--- Step 1/2: general RADV check ------------------------------"
  if ! "$ROOT/check.sh" --no-gui; then
    CHECK_FAILED=1
    echo "WARNING: the general check reported a failure." >&2
  fi
  echo

  echo "--- Step 2/2: individual verification -------------------------"
  for v in "${VERS[@]}"; do
    echo ">>> Mesa $v"
    if ! "$ROOT/check.sh" "$v"; then
      CHECK_FAILED=1
      echo "WARNING: Mesa $v failed its individual verification." >&2
    fi
    echo
  done
fi

# ---------------------------------------------------------------------------
# 6) Desktop shortcuts
# ---------------------------------------------------------------------------
if [ "$INSTALL_DESKTOP" = 1 ] && [ -d "$ROOT/desktop" ]; then
  echo "--- Installing desktop shortcuts -------------------------------"
  APPS_DIR="$HOME/.local/share/applications"
  mkdir -p "$APPS_DIR"
  for f in "$ROOT"/desktop/*.desktop; do
    [ -f "$f" ] || continue
    out="$APPS_DIR/$(basename "$f")"
    sed "s|@ROOT@|$ROOT|g" "$f" > "$out"
    echo "  installed: $out"
  done
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  echo
fi

# ---------------------------------------------------------------------------
# 7) Final report
# ---------------------------------------------------------------------------
MONITOR_ERROR_NEW=0
if [ -f "$ERROR_REPORT" ] && [ -n "$MARKER" ] && [ "$ERROR_REPORT" -nt "$MARKER" ]; then
  MONITOR_ERROR_NEW=1
fi

echo "=============================================================="
if [ "$CHECK_FAILED" != 0 ] || [ "$MONITOR_ERROR_NEW" != 0 ]; then
  echo " RESULT: PROBLEMS DETECTED"
  echo "=============================================================="
  [ "$CHECK_FAILED" != 0 ] && echo " - One or more Mesa versions failed the Vulkan verification."
  if [ "$MONITOR_ERROR_NEW" != 0 ]; then
    echo " - ps4-monitor detected a GPU/video error during the install:"
    echo "     $ERROR_REPORT"
    echo "   Read that file first; it explains what happened and what to do."
  fi
  echo
  echo " Logs: $INSTALL_LOG"
  echo " Monitor session: $(cat "$RUN_DIR/current" 2>/dev/null || echo 'not available')"
  echo
  echo " You can still try Mesa 25.3.5 with:"
  echo "   $ROOT/vulkan-run.sh --mesa 25.3.5 -- vkcube"
  echo "=============================================================="
  FAILED=1
else
  echo " RESULT: INSTALLATION COMPLETED SUCCESSFULLY"
  echo "=============================================================="
  echo
  if [ "$SKIP_TESTS" = 1 ]; then
    echo "Mesa versions available: ${VERS[*]} (verification skipped)"
  else
    echo "Mesa versions verified:  ${VERS[*]}"
  fi
  echo "Install log:            $INSTALL_LOG"
  if [ "$MONITOR_STARTED" = 1 ]; then
    echo "Monitor:                running (logs in $LOG_DIR)"
    echo "                        stop with $ROOT/monitor/ps4-monitor-stop.sh"
  else
    echo "Monitor:                not started"
  fi
  echo
  cat <<EOF
HOW TO USE EVERYTHING
---------------------
1) One command with the stable Mesa (recommended):

     $ROOT/vulkan-run.sh --mesa 25.3.5 -- vkcube

   Any program works:

     $ROOT/vulkan-run.sh --mesa 25.3.5 -- your-program

   Choose Mesa 26.0.4 with --mesa 26.0.4, or show FPS with --hud=fps.

2) Current shell (fish):

     source $ROOT/vulkan-env.fish --mesa 25.3.5

   bash / sh / zsh:

     . $ROOT/vulkan-env.sh --mesa 25.3.5

3) Steam → game Properties → Launch Options:

     $ROOT/vulkan-run.sh --mesa 25.3.5 -- %command% -force-d3d11

   Remove -force-d3d11 unless the game is Unity/D3D12.

4) Non-Steam games through Proton:

     $ROOT/vulkan-run.sh --proton -- "/run/media/USER/External/Games/Example Game/game.exe"

   For 32-bit games (no stable 32-bit RADV):

     $ROOT/vulkan-run.sh --wined3d --proton -- "/path/to/game32.exe"

5) Heroic Launcher:

     $ROOT/prepare-heroic.sh

   Then set Wrapper: $ROOT/heroic-mesa.sh

6) Verify at any time:

     $ROOT/check.sh
     $ROOT/check.sh 25.3.5

7) Monitor:

     $ROOT/monitor/ps4-monitor-status.sh
     $ROOT/monitor/ps4-monitor-stop.sh

   If something crashes or the video is lost, read:

     $ERROR_REPORT

   It is written automatically by ps4-monitor and survives a reboot.

Full documentation: $ROOT/README.en.md
Spanish version:    $ROOT/README.md
EOF
fi

[ "$FAILED" = 0 ] || exit 1
exit 0
