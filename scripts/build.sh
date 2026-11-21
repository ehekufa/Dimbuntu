#!/usr/bin/env bash
# Dimbuntu Tiny -- remaster of Tiny Core Linux (CorePlus) with Russian keyboard
# and project branding. Result: a bootable hybrid ISO of ~110 MB (BIOS/legacy).
# Pipeline: download CorePlus -> bsdtar extract -> edit isolinux.cfg -> xorriso repack.
set -euo pipefail
trap 'printf "BUILD-FAILED: line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

TC_VERSIONS="${TC_VERSIONS:-16.1 16.0 15.1 15.0}"   # candidates, newest first
ISO_NAME="${ISO_NAME:-dimbuntu-tiny}"
HOSTNAME_T="${HOSTNAME_T:-dimbuntu}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
STAGING="$BUILD_DIR/iso-src"
ISO_OUT="$BUILD_DIR/${ISO_NAME}.iso"

MIRRORS=( http://tinycorelinux.net http://repo.tinycorelinux.net http://distro.ibiblio.org/tinycorelinux )
DL_DIR="$BUILD_DIR/download"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

for tool in curl bsdtar xorriso sha256sum md5sum; do
  command -v "$tool" >/dev/null 2>&1 || \
    die "Missing tool: $tool (install: curl libarchive-tools xorriso coreutils)"
done

rm -rf "$STAGING"
mkdir -p "$BUILD_DIR" "$STAGING" "$DL_DIR"

# ---------------------------------------------------------------- 1. Download
download_coreplus() {
  for V in $TC_VERSIONS; do
    major="${V%%.*}"
    for M in "${MIRRORS[@]}"; do
      base="$M/$major.x/x86/release"
      log "Trying $base/CorePlus-$V.iso"
      if curl -fSL --retry 2 --connect-timeout 15 --max-time 900 \
           -o "$DL_DIR/CorePlus-$V.iso" "$base/CorePlus-$V.iso" \
        && curl -fsSL --retry 2 --connect-timeout 15 --max-time 60 \
           -o "$DL_DIR/CorePlus-$V.iso.md5.txt" "$base/CorePlus-$V.iso.md5.txt" \
        && ( cd "$DL_DIR" && md5sum -c "CorePlus-$V.iso.md5.txt" ); then
        TC_V="$V"
        return 0
      fi
      log "Download/verify failed for $base -- trying next mirror"
      rm -f "$DL_DIR/CorePlus-$V.iso" "$DL_DIR/CorePlus-$V.iso.md5.txt"
    done
  done
  return 1
}

log "Downloading CorePlus (Tiny Core Linux base)"
TC_V=""
download_coreplus || die "Could not download any CorePlus ISO. Tried versions: $TC_VERSIONS"
ISO_FILE="$BUILD_DIR/CorePlus-$TC_V.iso"
log "CorePlus-$TC_V downloaded: $(du -h "$ISO_FILE" | cut -f1)"

# ---------------------------------------------------------------- 2. Extract
log "Extracting ISO tree"
bsdtar -x -f "$ISO_FILE" -C "$STAGING"
# files come out of ISO9660 read-only; make them writable for sed/cat
chmod -R u+w "$STAGING"

ISOCFG="$(find "$STAGING" -name isolinux.cfg -type f | head -n 1)"
[ -n "$ISOCFG" ] || die "isolinux.cfg not found in extracted ISO"
ISODIR_REL="$(dirname "${ISOCFG#"$STAGING/"}")"
[ -f "$STAGING/$ISODIR_REL/isolinux.bin" ] || die "isolinux.bin missing next to isolinux.cfg"

log "Original isolinux.cfg:"
cat "$ISOCFG"

# ---------------------------------------------------------------- 3. Customize
log "Customizing boot menu (Dimbuntu branding + Russian keyboard entry)"
cp "$ISOCFG" "$BUILD_DIR/isolinux.cfg.original"
sed -i -e 's/TINYCORE/DIMBUNTU/g' -e 's/TinyCore/Dimbuntu/g' \
       -e 's/COREPLUS/DIMBUNTU/g' -e 's/CorePlus/Dimbuntu/g' "$ISOCFG"
sed -i '/menu default/Id' "$ISOCFG"

# grab boot paths from the first (main) menu entry of the stock config
grep -v '^[[:space:]]*#' "$ISOCFG" > "$BUILD_DIR/isolinux.cfg.clean"
KPATH="$(grep -m1 -i '^[[:space:]]*KERNEL[[:space:]]' "$BUILD_DIR/isolinux.cfg.clean" | awk '{print $2}')"
[ -n "$KPATH" ] || die "No KERNEL line found in isolinux.cfg"
IINITRD="$(grep -m1 -i '^[[:space:]]*INITRD[[:space:]]' "$BUILD_DIR/isolinux.cfg.clean" | awk '{print $2}')"
INITRD_LINE=""
[ -n "$IINITRD" ] && INITRD_LINE="initrd $IINITRD"
APPENDARGS="$(grep -m1 -i '^[[:space:]]*APPEND[[:space:]]' "$BUILD_DIR/isolinux.cfg.clean" | sed -E 's/^[[:space:]]*[Aa][Pp][Pp][Ee][Nn][Dd][[:space:]]+//')"

cat >> "$ISOCFG" <<EOF

label dimbuntu-ru
  menu label Dimbuntu Tiny (Russian keyboard)
  menu default
  kernel $KPATH
  $INITRD_LINE
  append $APPENDARGS kmap=ru host=$HOSTNAME_T
EOF

log "New isolinux.cfg:"
cat "$ISOCFG"

# ---------------------------------------------------------------- 4. Repack
log "Repacking hybrid ISO with xorriso"
rm -f "$ISO_OUT"
ISOHYBRID_MBR=/usr/lib/ISOLINUX/isohdpfx.bin
if [ -f "$ISOHYBRID_MBR" ]; then
  xorriso -as mkisofs -o "$ISO_OUT" -isohybrid-mbr "$ISOHYBRID_MBR" \
    -b "$ISODIR_REL/isolinux.bin" -c "$ISODIR_REL/boot.cat" \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -V "DIMBUNTU_TINY" -J -r -joliet-long "$STAGING"
else
  log "isohybrid MBR not found -- building CD-only image"
  xorriso -as mkisofs -o "$ISO_OUT" \
    -b "$ISODIR_REL/isolinux.bin" -c "$ISODIR_REL/boot.cat" \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -V "DIMBUNTU_TINY" -J -r -joliet-long "$STAGING"
fi

# ---------------------------------------------------------------- 5. Checksums
( cd "$BUILD_DIR" && sha256sum "$(basename "$ISO_OUT")" > SHA256SUMS )

log "Done"
ls -lh "$ISO_OUT"
echo "ISO ready: $ISO_OUT"
