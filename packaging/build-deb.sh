#!/bin/bash
# Builds beatbox_<version>-1~<distro><release>_<arch>.deb for the Debian or Ubuntu
# release it runs on, installing the build dependencies (needs root: CI runs it in a
# container per release). Usage, from the repository root:
#   packaging/build-deb.sh [output dir, default .]
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath -m "${1:-.}")
BB_VERSION=$(sed -n "s/^project('beatbox'.*version: '\([^']*\)'.*/\1/p" "$SRC/meson.build")
. /etc/os-release

WORK=$(mktemp -d)
mkdir "$WORK/beatbox-$BB_VERSION"
tar -C "$SRC" --exclude=./.git --exclude=./build --exclude='./build-*' --exclude=./appimage-work \
    --exclude=./.flatpak-builder --exclude=./repo -cf - . | tar -C "$WORK/beatbox-$BB_VERSION" -xf -
cd "$WORK/beatbox-$BB_VERSION"
cp -r packaging/debian debian
cat > debian/changelog <<EOF
beatbox ($BB_VERSION-1~$ID$VERSION_ID) $VERSION_CODENAME; urgency=medium

  * BeatBox $BB_VERSION, built for $PRETTY_NAME.

 -- lchongv <lchongv+beatbox@gmail.com>  $(date -R)
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get build-dep -y -qq ./
dpkg-buildpackage -b -us -uc
mkdir -p "$OUT"
cp ../beatbox_*.deb "$OUT/"
ls -l "$OUT"/beatbox_*.deb
