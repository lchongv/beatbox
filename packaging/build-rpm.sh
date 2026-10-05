#!/bin/bash
# Builds beatbox-<version>-1.<dist>.<arch>.rpm for the Fedora release it runs on,
# installing the build dependencies (needs root: CI runs it in a container).
# Usage, from the repository root:
#   packaging/build-rpm.sh [output dir, default .]
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(realpath -m "${1:-.}")
VERSION=$(sed -n "s/^project('beatbox'.*version: '\([^']*\)'.*/\1/p" "$SRC/meson.build")

TOP=$(mktemp -d)
mkdir -p "$TOP/SOURCES"
tar -C "$SRC" --exclude=./.git --exclude=./build --exclude='./build-*' --exclude=./appimage-work \
    --exclude=./.flatpak-builder --exclude=./repo --transform "s,^\.,beatbox-$VERSION," \
    -czf "$TOP/SOURCES/beatbox-$VERSION.tar.gz" .

dnf -y -q install rpm-build 'dnf-command(builddep)'
dnf -y -q builddep --define "bb_version $VERSION" "$SRC/packaging/beatbox.spec"
rpmbuild -bb --define "_topdir $TOP" --define "bb_version $VERSION" "$SRC/packaging/beatbox.spec"
mkdir -p "$OUT"
cp "$TOP"/RPMS/*/beatbox-"$VERSION"-*.rpm "$OUT/"  # not the -debuginfo/-debugsource ones
ls -l "$OUT"/beatbox-"$VERSION"-*.rpm
