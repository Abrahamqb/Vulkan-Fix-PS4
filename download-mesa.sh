#!/bin/bash
# ============================================================================
#  download-mesa.sh — rebuild mesa-versions/ from the original sources
#
#  The GitHub repository does NOT include the binaries (Mesa + LLVM are about
#  650 MB and GitHub rejects files larger than 100 MB). This script downloads
#  them, verifies them and leaves everything ready for vulkan-env.sh /
#  vulkan-run.sh.
#
#  USAGE
#    ./download-mesa.sh                    # into ./mesa-versions
#    ./download-mesa.sh --dest ~/mesa-versions
#    ./download-mesa.sh --ver 25.3.5       # only one version
#    ./download-mesa.sh --list             # show known versions
#
#  REQUIREMENTS: curl, bsdtar (libarchive), readelf (binutils), sha256sum,
#                about 800 MB free.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/mesa-versions"
VER="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="${2:?missing path}"; shift 2 ;;
    --ver)  VER="${2:?missing version}"; shift 2 ;;
    --list) VER="__list__"; shift ;;
    -h|--help)
      awk 'NR==1{next} /^# ============================================================================$/{if (++n==2) exit} {print}' "$0"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

MESA_BASE="https://raw.githubusercontent.com/DionKill/ps4-video-archlinux"
LLVM_BASE="https://archive.archlinux.org/packages/l/llvm-libs"

# version|repo commit|mesa package|sha256|llvm package|sha256|llvm dir
DATA="
25.3.5|890b048aa4f1c7ce9bd1d70ba740e33e880e483b|mesa-ps4-25.3.5.214264.39f24bf4091.d9a8cd9-1-x86_64.pkg.tar.zst|e2d086cf0a7382b6a13512d5e384d83878ce7f5995011f3c3ba42fecddea3520|llvm-libs-21.1.8-1-x86_64.pkg.tar.zst|8a8d86d63f6b6e4443003537bb0c49df854d9139723547f95b9d2923f72383f9|llvm-21
26.0.4|76d656a0faabed675504c822d043346865005ac5|mesa-ps4-26.0.4.217906.bbc23bed47f.2fc1477-1-x86_64.pkg.tar.zst|b868ee6e39849d7c06e93cc61f6f8376c0f5caa42c5dd4d5643dbd973371ea96|llvm-libs-22.1.8-2-x86_64.pkg.tar.zst|ad4454d1b969192e7a878066400a583b984210322d67c6fa8958ad1175342658|llvm-22
"

if [ "$VER" = "__list__" ]; then
  printf '%s\n' "$DATA" | while IFS='|' read -r v _; do [ -n "$v" ] && echo "$v"; done
  exit 0
fi

if [ "$VER" != "all" ]; then
  found=0
  while IFS='|' read -r v _; do
    [ "$v" = "$VER" ] && found=1
  done <<< "$DATA"
  if [ "$found" != 1 ]; then
    echo "ERROR: unknown Mesa version: $VER" >&2
    echo "Known versions:" >&2
    printf '%s\n' "$DATA" | while IFS='|' read -r v _; do [ -n "$v" ] && echo "  $v" >&2 || true; done
    exit 2
  fi
fi

for cmd in curl bsdtar readelf sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing program: $cmd" >&2; exit 1; }
done

mkdir -p "$DEST/icd" "$DEST/tmp"
DEST="$(cd "$DEST" && pwd)"

download() { # url output sha256
  local url="$1" out="$2" sum="$3"
  if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$sum" ]; then
    echo "  already exists and matches: $(basename "$out")"
    return 0
  fi
  echo "  downloading $(basename "$out") ..."
  curl -fL --retry 3 --max-time 600 -o "$out.part" "$url"
  if [ "$(sha256sum "$out.part" | cut -d' ' -f1)" != "$sum" ]; then
    echo "  ERROR: sha256 mismatch for $(basename "$out")" >&2
    rm -f "$out.part"; exit 1
  fi
  mv "$out.part" "$out"
}

while IFS='|' read -r v commit pkg_mesa sha_mesa pkg_llvm sha_llvm dir_llvm; do
  [ -n "${v:-}" ] || continue
  [ "$VER" = "all" ] || [ "$VER" = "$v" ] || continue

  echo
  echo "=== Mesa $v ==============================================="

  # 1) Mesa
  if [ -d "$DEST/mesa-$v/usr/lib" ] && [ -f "$DEST/mesa-$v/usr/lib/libvulkan_radeon.so" ]; then
    echo "  Mesa $v already extracted"
  else
    download "$MESA_BASE/$commit/repo/$pkg_mesa" "$DEST/tmp/$pkg_mesa" "$sha_mesa"
    mkdir -p "$DEST/mesa-$v"
    bsdtar -xf "$DEST/tmp/$pkg_mesa" -C "$DEST/mesa-$v"
    rm -f "$DEST/tmp/$pkg_mesa"
  fi

  # 2) LLVM it needs
  if [ -d "$DEST/$dir_llvm/usr/lib" ]; then
    echo "  $dir_llvm already extracted"
  else
    download "$LLVM_BASE/$pkg_llvm" "$DEST/tmp/$pkg_llvm" "$sha_llvm"
    mkdir -p "$DEST/$dir_llvm"
    bsdtar -xf "$DEST/tmp/$pkg_llvm" -C "$DEST/$dir_llvm"
    rm -f "$DEST/tmp/$pkg_llvm"
  fi

  # 3) ICD with an absolute path
  cat > "$DEST/icd/mesa-$v.json" <<EOF
{
    "ICD": {
        "api_version": "1.4.328",
        "library_arch": "64",
        "library_path": "$DEST/mesa-$v/usr/lib/libvulkan_radeon.so"
    },
    "file_format_version": "1.0.1"
}
EOF

  # 4) check dependencies
  if LD_LIBRARY_PATH="$DEST/mesa-$v/usr/lib:$DEST/$dir_llvm/usr/lib" \
       ldd "$DEST/mesa-$v/usr/lib/libvulkan_radeon.so" 2>/dev/null | grep -q 'not found'; then
    echo "  ERROR: missing libraries for Mesa $v:" >&2
    LD_LIBRARY_PATH="$DEST/mesa-$v/usr/lib:$DEST/$dir_llvm/usr/lib" \
      ldd "$DEST/mesa-$v/usr/lib/libvulkan_radeon.so" | grep 'not found' >&2
    exit 1
  fi
  echo "  OK: Mesa $v + $dir_llvm ready (ICD at $DEST/icd/mesa-$v.json)"
done <<< "$DATA"

rmdir "$DEST/tmp" 2>/dev/null || true

echo
echo "=============================================================="
echo " Done. Use:"
echo "   source $ROOT/vulkan-env.fish --mesa 25.3.5      (fish)"
echo "   . $ROOT/vulkan-env.sh --mesa 25.3.5             (bash/sh)"
echo "   $ROOT/check.sh                                  (verify)"
echo "=============================================================="
