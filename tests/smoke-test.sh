#!/bin/bash
# ============================================================================
#  smoke-test.sh — verify the translation and the main code paths
#
#  It does not download anything. It checks syntax, help texts, Mesa selection,
#  the fish wrapper, the monitor report writer and, with --with-vulkan, the
#  actual RADV device enumeration.
#
#  USAGE
#    ./tests/smoke-test.sh
#    ./tests/smoke-test.sh --with-vulkan
# ============================================================================
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WITH_VULKAN=0
for arg in "$@"; do
  case "$arg" in
    --with-vulkan) WITH_VULKAN=1 ;;
    -h|--help)
      awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
      exit 0 ;;
    *) echo "smoke-test: unknown option: $arg" >&2; exit 2 ;;
  esac
done

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$*"; fi; }

echo "=================================================================="
echo " Vulkan Solution — smoke test"
echo "=================================================================="
echo

echo "--- Shell syntax -------------------------------------------------"
for f in "$ROOT"/vulkan-env.sh "$ROOT"/vulkan-run.sh "$ROOT"/download-mesa.sh \
         "$ROOT"/check.sh "$ROOT"/prepare-heroic.sh "$ROOT"/install.sh \
         "$ROOT"/monitor/ps4-monitor.sh "$ROOT"/monitor/ps4-monitor-stop.sh \
         "$ROOT"/monitor/ps4-monitor-status.sh "$ROOT"/tests/smoke-test.sh; do
  check bash -n "$f"
done
check sh -n "$ROOT/heroic-mesa.sh"
if command -v fish >/dev/null 2>&1; then
  check fish -n "$ROOT/vulkan-env.fish"
else
  echo "  skip fish syntax (fish not installed)"
fi
if command -v python3 >/dev/null 2>&1; then
  check python3 -m py_compile "$ROOT/check-heroic.py"
  rm -rf "$ROOT/__pycache__"
else
  echo "  skip Python syntax (python3 not installed)"
fi
echo

echo "--- Translation leak check ---------------------------------------"
LEAKS=$(grep -RInE \
  --exclude-dir=.git --exclude-dir=mesa-versions --exclude-dir=reports \
  --exclude='*.log' --exclude='smoke-test.sh' \
  '\b(descargar|comprobar|preparar|carpeta|fichero|pantalla|fallo|salida|versión|también|ejecuta|archivo|ninguna|reiniciar|lanzador|escritorio|conector)\b' \
  "$ROOT"/*.sh "$ROOT"/*.fish "$ROOT"/*.py "$ROOT"/monitor "$ROOT"/tests 2>/dev/null || true)
if [ -z "$LEAKS" ]; then
  ok "no Spanish wording left in scripts"
else
  bad "Spanish wording left in scripts:"
  printf '%s\n' "$LEAKS" | sed 's/^/       /'
fi
echo

echo "--- Help texts ----------------------------------------------------"
check "$ROOT/vulkan-env.sh" --help
check "$ROOT/vulkan-run.sh" --help
check "$ROOT/download-mesa.sh" --help
check "$ROOT/check.sh" --help
check "$ROOT/install.sh" --help
echo

echo "--- Mesa selection -----------------------------------------------"
mapfile -t VERS < <("$ROOT/check.sh" --list 2>/dev/null || true)
if [ ${#VERS[@]} -eq 0 ]; then
  bad "no Mesa versions found"
else
  for v in "${VERS[@]}"; do
    out=$(VULKAN_LOG=/dev/null "$ROOT/vulkan-env.sh" --show --mesa "$v" 2>/dev/null || true)
    icd=$(printf '%s\n' "$out" | sed -n 's/^VK_DRIVER_FILES=//p')
    libs=$(printf '%s\n' "$out" | sed -n 's/^LD_LIBRARY_PATH=//p')
    if [ -f "$icd" ] && [ -n "$libs" ]; then
      missing=0
      oldifs=$IFS; IFS=:
      for d in $libs; do [ -d "$d" ] || missing=1; done
      IFS=$oldifs
      [ "$missing" = 0 ] && ok "Mesa $v selects existing ICD and libraries" \
                         || bad "Mesa $v has a missing library directory"
    else
      bad "Mesa $v does not produce a valid environment"
    fi
  done
fi
echo

echo "--- Portability (moved / renamed repository) ----------------------"
ASSUMPTIONS=$(grep -RInE --exclude-dir=.git --exclude-dir=mesa-versions \
  --exclude-dir=logs --exclude-dir=run --exclude='*.log' --exclude='smoke-test.sh' \
  'vulkan-solucion|/home/USER/vulkan' "$ROOT" 2>/dev/null || true)
if [ -z "$ASSUMPTIONS" ]; then
  ok "no hardcoded repository name or location"
else
  bad "hardcoded repository name/location found:"
  printf '%s\n' "$ASSUMPTIONS" | sed 's/^/       /'
fi

MOVED=$(mktemp -d "${TMPDIR:-/tmp}/renamed-repo.XXXXXX")
cp -p "$ROOT/vulkan-env.sh" "$ROOT/vulkan-run.sh" "$ROOT/heroic-mesa.sh" "$MOVED/" 2>/dev/null || true
mkdir -p "$MOVED/mesa-versions/icd"
for d in "$ROOT"/mesa-versions/mesa-* "$ROOT"/mesa-versions/llvm-*; do
  [ -e "$d" ] && ln -s "$d" "$MOVED/mesa-versions/$(basename "$d")"
done
cp -p "$ROOT"/mesa-versions/icd/*.json "$MOVED/mesa-versions/icd/" 2>/dev/null || true

if [ ${#VERS[@]} -gt 0 ]; then
  v="${VERS[0]}"
  out=$(cd /tmp && bash -c ". '$MOVED/vulkan-env.sh' --show --mesa '$v'" 2>/dev/null || true)
  icd=$(printf '%s\n' "$out" | sed -n 's/^VK_DRIVER_FILES=//p')
  icd_lib=$(sed -n 's/.*"library_path": "\(.*\)".*/\1/p' "$icd" 2>/dev/null | head -n1)
  if [ -f "$icd" ] && [ -f "$icd_lib" ]; then
    ok "auto-detects a renamed repository from another directory"
  else
    bad "renamed repository was not detected correctly"
  fi
  out=$(cd "$MOVED" && sh -c ". ./vulkan-env.sh --show --mesa '$v'" 2>/dev/null || true)
  [ -n "$(printf '%s\n' "$out" | sed -n 's/^VK_DRIVER_FILES=//p')" ] \
    && ok "works when sourced from a POSIX sh in the repository" \
    || bad "POSIX sh sourcing failed"
  if "$MOVED/vulkan-run.sh" --mesa "$v" -- true >/dev/null 2>&1; then
    ok "launcher works from the renamed repository"
  else
    bad "launcher failed in the renamed repository"
  fi
else
  echo "  skip relocation test (no Mesa installed)"
fi
rm -rf "$MOVED"
echo

echo "--- fish wrapper --------------------------------------------------"
if command -v fish >/dev/null 2>&1; then
  if fish -c "source '$ROOT/vulkan-env.fish' --mesa 25.3.5 --quiet; test -n \"\$VK_DRIVER_FILES\"; and test -n \"\$VULKAN_MESA_ACTIVE\"" >/dev/null 2>&1; then
    ok "fish wrapper exports VK_DRIVER_FILES and VULKAN_MESA_ACTIVE"
  else
    bad "fish wrapper did not export the environment"
  fi
else
  echo "  skip (fish not installed)"
fi
echo

echo "--- Installer dry run ---------------------------------------------"
if "$ROOT/install.sh" --dry-run --yes >/dev/null 2>&1; then
  ok "install.sh --dry-run"
else
  bad "install.sh --dry-run"
fi
echo

echo "--- Monitor -------------------------------------------------------"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ps4-monitor-test.XXXXXX")
export PS4_MONITOR_LOG_DIR="$TMP/logs"
export PS4_MONITOR_RUN_DIR="$TMP/run"
export PS4_MONITOR_ERROR_FILE="$TMP/ps4-monitor-error.log"
export PS4_MONITOR_CONNECTOR="/sys/class/drm/card0-HDMI-A-1/status"
if "$ROOT/monitor/ps4-monitor.sh" --test-report >/dev/null 2>&1 \
   && [ -s "$PS4_MONITOR_ERROR_FILE" ] \
   && grep -q 'ERROR REPORT' "$PS4_MONITOR_ERROR_FILE"; then
  ok "monitor writes an error report"
else
  bad "monitor error report"
fi

rm -rf "$TMP"; mkdir -p "$TMP/logs" "$TMP/run"
if "$ROOT/monitor/ps4-monitor.sh" >/dev/null 2>&1; then
  for _ in 1 2 3 4 5; do
    [ -f "$TMP/run/main.pid" ] && break
    sleep 1
  done
  if [ -f "$TMP/run/main.pid" ] && kill -0 "$(cat "$TMP/run/main.pid" 2>/dev/null)" 2>/dev/null; then
    sleep 2
    SESSION=$(cat "$TMP/run/current" 2>/dev/null || true)
    if [ -f "$SESSION" ] && grep -q 'temp=' "$SESSION"; then
      ok "monitor starts and samples state"
    else
      bad "monitor did not sample state"
    fi
    "$ROOT/monitor/ps4-monitor-stop.sh" >/dev/null 2>&1 || true
    if [ -f "$TMP/run/main.pid" ]; then
      bad "monitor did not stop"
    else
      ok "monitor stops cleanly"
    fi
  else
    bad "monitor did not start"
  fi
else
  bad "monitor start command"
fi
rm -rf "$TMP"
unset PS4_MONITOR_LOG_DIR PS4_MONITOR_RUN_DIR PS4_MONITOR_ERROR_FILE PS4_MONITOR_CONNECTOR
echo

echo "--- Public repository check ---------------------------------------"
PERSONAL=$(grep -RInE --exclude-dir=.git --exclude-dir=mesa-versions \
  --exclude-dir=reports --exclude-dir=logs --exclude-dir=run --exclude='*.log' --exclude='smoke-test.sh' \
  '/home/user/|/run/media/user/|Disco De Abraham' "$ROOT" 2>/dev/null || true)
if [ -z "$PERSONAL" ]; then
  ok "no personal absolute paths in scripts/docs"
else
  bad "personal absolute paths found:"
  printf '%s\n' "$PERSONAL" | sed 's/^/       /'
fi
echo

if [ "$WITH_VULKAN" = 1 ]; then
  echo "--- Vulkan device enumeration -------------------------------------"
  if "$ROOT/check.sh" --no-gui; then
    ok "check.sh --no-gui"
  else
    bad "check.sh --no-gui"
  fi
  echo
fi

echo "=================================================================="
echo " Result: $PASS passed, $FAIL failed"
echo "=================================================================="
[ "$FAIL" -eq 0 ]
