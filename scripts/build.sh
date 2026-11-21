#!/usr/bin/env bash
# Dimbuntu -- build a Xubuntu-style live ISO out of Ubuntu 24.04 LTS.
# Pipeline: debootstrap -> chroot (Xfce + casper) -> mksquashfs -> grub-mkrescue (BIOS+UEFI).
set -euo pipefail
trap 'printf "BUILD-FAILED: line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

DISTRO="${DISTRO:-noble}"          # base Ubuntu release
VERSION="${VERSION:-24.04}"        # Dimbuntu version
ARCH="amd64"
MIRROR="http://archive.ubuntu.com/ubuntu"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
CHROOT="$BUILD_DIR/chroot"
STAGING="$BUILD_DIR/iso"
ISO_OUT="$BUILD_DIR/dimbuntu-${VERSION}-${ARCH}.iso"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Please run as root: sudo ./scripts/build.sh"
for tool in debootstrap mksquashfs grub-mkrescue xorriso mformat chroot; do
  command -v "$tool" >/dev/null 2>&1 || \
    die "Missing tool: $tool (install: debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools)"
done

mkdir -p "$BUILD_DIR" "$STAGING/casper" "$STAGING/boot/grub"

# ---------------------------------------------------------------- 1. Base system
if [ ! -e "$CHROOT/etc/debian_version" ]; then
  log "debootstrap: base Ubuntu $DISTRO (minbase)"
  debootstrap --arch="$ARCH" --variant=minbase --include=ca-certificates \
    "$DISTRO" "$CHROOT" "$MIRROR"
fi

MOUNTED=0
mount_chroot() {
  [ "$MOUNTED" -eq 1 ] && return 0
  mkdir -p "$CHROOT/dev/pts" "$CHROOT/proc" "$CHROOT/sys" "$CHROOT/run" "$CHROOT/tmp"
  mount --bind /dev "$CHROOT/dev"
  mount --bind /dev/pts "$CHROOT/dev/pts"
  mount -t proc proc "$CHROOT/proc"
  mount --bind /sys "$CHROOT/sys"
  MOUNTED=1
}
umount_chroot() {
  [ "$MOUNTED" -eq 0 ] && return 0
  for m in "$CHROOT/dev/pts" "$CHROOT/dev" "$CHROOT/proc" "$CHROOT/sys"; do
    umount -l "$m" 2>/dev/null || true
  done
  MOUNTED=0
}
trap umount_chroot EXIT
mount_chroot

# dirs mksquashfs excludes must exist
mkdir -p "$CHROOT/mnt" "$CHROOT/media" "$CHROOT/lost+found" 2>/dev/null || true

ch() {
  chroot "$CHROOT" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" \
    DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 "$@"
}

# DNS inside the chroot (runners often use systemd-resolved stub)
rm -f "$CHROOT/etc/resolv.conf"
if [ -f /run/systemd/resolve/resolv.conf ]; then
  cp /run/systemd/resolve/resolv.conf "$CHROOT/etc/resolv.conf"
else
  cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"
fi

# do not start services inside the chroot
cat > "$CHROOT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

cat > "$CHROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $DISTRO main restricted universe multiverse
deb $MIRROR ${DISTRO}-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${DISTRO}-security main restricted universe multiverse
EOF

# ---------------------------------------------------------------- 2. Packages
log "apt-get update"
ch /bin/sh -ec 'apt-get -o Acquire::Retries=3 update'

log "Installing system core + kernel + casper (required for a live ISO)"
ch /bin/sh -ec '
  apt-get -o Acquire::Retries=3 install -y \
    systemd systemd-sysv dbus sudo locales console-setup \
    linux-image-generic linux-firmware casper
' || die "Kernel/casper install failed -- cannot build a live ISO"

log "Installing Xfce desktop (the long part, 10-20 min)"
if ! ch /bin/sh -ec 'apt-get -o Acquire::Retries=3 install -y xubuntu-core'; then
  log "xubuntu-core failed -- falling back to plain xfce4"
  ch /bin/sh -ec 'apt-get -o Acquire::Retries=3 install -y xfce4 xubuntu-default-settings thunar' \
    || die "Could not install any Xfce desktop"
fi

log "Installing desktop apps (missing ones are skipped, not fatal)"
APPS="xfce4-terminal mousepad xfce4-whiskermenu-plugin xfce4-xkb-plugin lightdm lightdm-gtk-greeter network-manager network-manager-gnome gvfs-backends xdg-user-dirs fonts-dejavu fonts-liberation epiphany-browser pavucontrol curl wget nano htop less file"
if ! ch /bin/sh -ec "apt-get -o Acquire::Retries=3 install -y $APPS"; then
  log "Group install failed -- retrying packages one by one"
  for pkg in $APPS; do
    ch /bin/sh -ec "apt-get -o Acquire::Retries=3 install -y $pkg" || echo "SKIP: $pkg is not available"
  done
fi

log "Best-effort extras: Russian language pack"
ch /bin/sh -ec 'apt-get install -y language-pack-ru' || true

log "Regenerating initramfs with casper hooks"
ch /bin/sh -ec 'command -v update-initramfs >/dev/null || { echo "update-initramfs is missing, kernel/casper install failed"; exit 1; }'
ch update-initramfs -u

# ---------------------------------------------------------------- 3. Configuration
log "Configuring the live system"

# locales: Russian default, English available
sed -i 's/^# *\(ru_RU.UTF-8 UTF-8\)/\1/; s/^# *\(en_US.UTF-8 UTF-8\)/\1/' "$CHROOT/etc/locale.gen"
ch locale-gen
printf 'LANG=ru_RU.UTF-8\n' > "$CHROOT/etc/default/locale"

# keyboard: us+ru, switch with Alt+Shift
cat > "$CHROOT/etc/default/keyboard" <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=","
XKBOPTIONS="grp:alt_shift_toggle"
BACKSPACE="guess"
EOF

printf 'dimbuntu\n' > "$CHROOT/etc/hostname"
cat > "$CHROOT/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 dimbuntu
::1 localhost ip6-localhost ip6-loopback
EOF

cat > "$CHROOT/etc/fstab" <<'EOF'
# The live system is assembled by casper, this file is a placeholder.
EOF

# live session user created by casper
cat > "$CHROOT/etc/casper.conf" <<'EOF'
export USERNAME="dimbuntu"
export USERFULLNAME="Live session user"
export HOSTNAME="dimbuntu"
export BUILD_SYSTEM="Ubuntu"
EOF

ch systemctl enable lightdm.service NetworkManager.service || true
ch systemctl set-default graphical.target || true

# no snapd in the live image (keeps boot fast, no snap seeding loop)
ch /bin/sh -ec 'apt-get purge -y snapd' 2>/dev/null || true
ch /bin/sh -ec 'apt-get autoremove --purge -y' || true

# ---------------------------------------------------------------- 4. Cleanup
log "Cleaning the chroot"
ch apt-get clean
rm -rf "$CHROOT"/var/lib/apt/lists/* "$CHROOT"/var/cache/apt/archives/*.deb 2>/dev/null || true
rm -rf "$CHROOT"/tmp/* "$CHROOT"/var/tmp/* 2>/dev/null || true
find "$CHROOT/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -f "$CHROOT/root/.bash_history" "$CHROOT/root/.lesshst" 2>/dev/null || true
truncate -s 0 "$CHROOT/etc/machine-id"
rm -f "$CHROOT/var/lib/dbus/machine-id"
rm -f "$CHROOT/usr/sbin/policy-rc.d"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$CHROOT/etc/resolv.conf"

ch dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > "$STAGING/casper/filesystem.manifest"

umount_chroot
trap - EXIT

# ---------------------------------------------------------------- 5. Kernel + initrd
log "Extracting kernel and initrd"
VMLINUZ="$(ls -1 "$CHROOT"/boot/vmlinuz-* 2>/dev/null | head -n 1 || true)"
[ -n "$VMLINUZ" ] || die "No kernel found in chroot /boot"
INITRD_SRC="$(ls -1 "$CHROOT"/boot/initrd.img-* 2>/dev/null | head -n 1 || true)"
if [ -z "$INITRD_SRC" ] && [ -e "$CHROOT/initrd.img" ]; then
  INITRD_SRC="$CHROOT/initrd.img"
fi
if [ -z "$INITRD_SRC" ]; then
  log "initrd not found, generating explicitly"
  ch update-initramfs -c -k all || true
  INITRD_SRC="$(ls -1 "$CHROOT"/boot/initrd.img-* 2>/dev/null | head -n 1 || true)"
fi
[ -n "$INITRD_SRC" ] || die "No initrd found in chroot /boot"
cp "$VMLINUZ" "$STAGING/casper/vmlinuz"
cp -L "$INITRD_SRC" "$STAGING/casper/initrd"

# ---------------------------------------------------------------- 6. GRUB menu
log "Writing GRUB menu"
cat > "$STAGING/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=15

menuentry "Dimbuntu ${VERSION} (live)" {
	linux	/casper/vmlinuz boot=casper quiet splash ---
	initrd	/casper/initrd
}

menuentry "Dimbuntu ${VERSION} (safe graphics)" {
	linux	/casper/vmlinuz boot=casper nomodeset ---
	initrd	/casper/initrd
}

menuentry "Dimbuntu ${VERSION} (whole image in RAM, 4GB+)" {
	linux	/casper/vmlinuz boot=casper toram quiet splash ---
	initrd	/casper/initrd
}

if [ "\$grub_platform" = "efi" ]; then
menuentry "UEFI Firmware Settings" {
	fwsetup
}
fi
EOF

# ---------------------------------------------------------------- 7. Squashfs
log "Packing squashfs (zstd, a few minutes)"
rm -f "$STAGING/casper/filesystem.squashfs"
mksquashfs "$CHROOT" "$STAGING/casper/filesystem.squashfs" \
  -noappend -no-recovery -comp zstd -b 1M -Xcompression-level 19 \
  -e boot dev proc sys run tmp mnt media lost+found

# ---------------------------------------------------------------- 8. ISO
log "Building hybrid BIOS+UEFI ISO with grub-mkrescue"
rm -f "$ISO_OUT"
grub-mkrescue -o "$ISO_OUT" "$STAGING" -- -volid "Dimbuntu_${VERSION}"

log "Checksums"
( cd "$BUILD_DIR" && sha256sum "$(basename "$ISO_OUT")" > SHA256SUMS )

log "Done"
ls -lh "$ISO_OUT" "$STAGING/casper/filesystem.squashfs"
echo "ISO ready: $ISO_OUT"
