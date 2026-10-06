#!/bin/bash
# Builds beatbox-<version>-1-x86_64.pkg.tar.zst for Arch Linux. makepkg refuses to run as
# root, so as root (CI's archlinux container) this installs the dependencies itself and
# builds as a throwaway user; otherwise makepkg -s installs them through sudo.
# Usage, from the repository root:
#   packaging/build-arch.sh [output dir, default .]
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath -m "${1:-.}")
BB_VERSION=$(sed -n "s/^project('beatbox'.*version: '\([^']*\)'.*/\1/p" "$SRC/meson.build")

WORK=$(mktemp -d)
tar -C "$SRC" --exclude=./.git --exclude=./build --exclude='./build-*' --exclude=./appimage-work \
    --exclude=./.flatpak-builder --exclude=./repo --transform "s,^\.,beatbox-$BB_VERSION," \
    -czf "$WORK/beatbox-$BB_VERSION.tar.gz" .
sed "s/^pkgver=.*/pkgver=$BB_VERSION/" "$SRC/packaging/arch/PKGBUILD" > "$WORK/PKGBUILD"

if [ "$(id -u)" = 0 ]; then
  # the container's only mirror drops connections now and then: others to fall back on
  printf 'Server = %s/$repo/os/$arch\n' https://geo.mirror.pkgbuild.com https://mirror.rackspace.com/archlinux \
         https://mirrors.kernel.org/archlinux >> /etc/pacman.d/mirrorlist
  pacman -Syu --noconfirm --needed base-devel $(source "$WORK/PKGBUILD"; echo "${depends[@]} ${makedepends[@]}")
  id builder >/dev/null 2>&1 || useradd -m builder
  chown -R builder "$WORK"
  runuser -u builder -- bash -c "cd '$WORK' && makepkg --noconfirm"
else
  (cd "$WORK" && makepkg -s --noconfirm)
fi
mkdir -p "$OUT"
cp "$WORK"/beatbox-"$BB_VERSION"-*.pkg.tar.zst "$OUT/"  # not the -debug one
ls -l "$OUT"/beatbox-"$BB_VERSION"-*.pkg.tar.zst
