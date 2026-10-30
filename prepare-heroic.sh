#!/bin/bash
# ============================================================================
#  prepare-heroic.sh — make Heroic ready to use Mesa 25.3.5
#  with heroic-mesa.sh, whether Heroic is Flatpak or native.
#
#  Flatpak: grant sandbox permissions and copy the libraries it lacks.
#  Native:  nothing is needed (it sees /dev/dri and the Mesa directory);
#           this only checks that RADV loads.
#
#  Usage:  ./prepare-heroic.sh
# ============================================================================
set -u

APP="com.heroicgameslauncher.hgl"
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -d "$SELF_DIR/mesa-versions/deps" ]; then
  DEPS="$SELF_DIR/mesa-versions/deps"
elif [ -d "$HOME/mesa-versions/deps" ]; then
  DEPS="$HOME/mesa-versions/deps"
else
  DEPS="$SELF_DIR/mesa-versions/deps"
fi
SRC_MESA=""
[ -d "$SELF_DIR/mesa-versions" ] && SRC_MESA="$SELF_DIR/mesa-versions"
[ -z "$SRC_MESA" ] && [ -d "$HOME/mesa-versions" ] && SRC_MESA="$HOME/mesa-versions"
NATIVE=$(command -v heroic heroic-games-launcher 2>/dev/null | head -n1)

echo "=================================================================="
echo " Preparing Heroic for Mesa 25.3.5"
echo "=================================================================="
echo

if flatpak info "$APP" >/dev/null 2>&1; then
  MODE="flatpak"
  echo "Heroic detected: Flatpak ($APP)"
elif [ -n "$NATIVE" ]; then
  MODE="native"
  echo "Heroic detected: native ($NATIVE)"
else
  echo "ERROR: cannot find Heroic (neither Flatpak $APP nor a native binary)." >&2
  echo "       Install it and run this script again." >&2
  exit 1
fi
echo

if [ "$MODE" = "flatpak" ]; then
  # ------------------------------------------------------------- permissions
  echo "--- 1) Flatpak permissions --------------------------------------"
  flatpak override --user --device=all "$APP"
  flatpak override --user --filesystem="$SELF_DIR" "$APP"
  [ -n "$SRC_MESA" ] && flatpak override --user --filesystem="$SRC_MESA" "$APP"
  echo "  devices=all + access to $SELF_DIR${SRC_MESA:+ and $SRC_MESA}"
  echo

  # ------------------------------------------------------------------- deps
  echo "--- 2) Libraries missing inside the sandbox ---------------------"
  mkdir -p "$DEPS"
  for l in libdisplay-info.so.3 libSPIRV-Tools.so libedit.so.0; do
    if [ -f "$DEPS/$l" ]; then
      echo "  already present: $l"
      continue
    fi
    if [ -f "/usr/lib/$l" ]; then
      cp -L "/usr/lib/$l" "$DEPS/$l" && echo "  copied: $l"
    else
      echo "  WARNING: cannot find /usr/lib/$l on the system" >&2
    fi
  done
  echo
else
  echo "--- 1-2) Native: no sandbox, no permissions or deps needed ------"
  echo "  Native Heroic already sees /dev/dri, the Mesa directory and system libraries."
  echo
fi

# ------------------------------------------------------------- Vulkan test
echo "--- 3) RADV test with Mesa 25.3.5 -------------------------------"
if [ ! -f "$SELF_DIR/check-heroic.py" ]; then
  echo "  (check-heroic.py is missing, skipping the test)" >&2
else
  if [ "$MODE" = "flatpak" ]; then
    timeout 90 flatpak run --command="$SELF_DIR/heroic-mesa.sh" "$APP" \
      python3 "$SELF_DIR/check-heroic.py" 2>&1 | sed 's/^/  /'
  else
    timeout 90 "$SELF_DIR/heroic-mesa.sh" \
      python3 "$SELF_DIR/check-heroic.py" 2>&1 | sed 's/^/  /'
  fi
  rc=${PIPESTATUS[0]}
  echo
  if [ "$rc" = 0 ]; then
    echo "  RESULT: Mesa 25.3.5 works in Heroic ($MODE)."
  else
    echo "  RESULT: something failed (read the message above)." >&2
  fi
fi

cat <<EOF

==================================================================
 DONE. In Heroic, for each game (64-bit):

   Game settings (⚙) → Advanced → Wrapper command
     Wrapper:    $SELF_DIR/heroic-mesa.sh
     Arguments:  (empty)

 Optional, in the same game's Environment Variables:
   HEROIC_MESA_HUD=fps     FPS counter
   HEROIC_MESA=26.0.4      use the other stable Mesa
   HEROIC_WINED3D=1        32-bit games (OpenGL, no RADV)

 If you just applied the Flatpak permissions, restart Heroic.
==================================================================
EOF
