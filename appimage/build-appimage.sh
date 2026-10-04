#!/bin/bash
# Builds BeatBox-<version>-x86_64.AppImage with linuxdeploy (GTK and GStreamer
# plugins), bundling the libraries of the system it runs on: the result runs on
# distributions with that glibc or a newer one. Usage, from the repository root:
#   appimage/build-appimage.sh [work dir, default ./appimage-work]
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(realpath -m "${1:-$SRC/appimage-work}")
TOOLS=$WORK/tools
mkdir -p "$TOOLS"

fetch() { [ -x "$TOOLS/$1" ] || { curl -fsSL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }; }
fetch linuxdeploy-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-appimage-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
fetch linuxdeploy-plugin-gtk.sh https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh
fetch linuxdeploy-plugin-gstreamer.sh https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gstreamer/master/linuxdeploy-plugin-gstreamer.sh

# no FUSE needed for the tools
export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3
export LINUXDEPLOY_OUTPUT_VERSION=$(meson introspect --projectinfo "$SRC/meson.build" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

APPDIR=$WORK/AppDir
rm -rf "$APPDIR"
[ -d "$WORK/build" ] || meson setup "$WORK/build" "$SRC" --prefix=/usr --buildtype=release
ninja -C "$WORK/build"
DESTDIR=$APPDIR meson install -C "$WORK/build" --no-rebuild

cd "$WORK"
LD_LIBRARY_PATH=$APPDIR/usr/lib PATH=$TOOLS:$PATH "$TOOLS/linuxdeploy-x86_64.AppImage" --appdir "$APPDIR" \
  -d "$APPDIR/usr/share/applications/net.launchpad.beatbox.desktop" \
  -i "$APPDIR/usr/share/icons/hicolor/128x128/apps/beatbox.svg" \
  --plugin gtk --plugin gstreamer

# The GStreamer plugin's AppRun hook expects Debian's helper path; other distributions
# keep the helpers in lib/gstreamer-1.0
HOOKDIR=$APPDIR/usr/lib/gstreamer1.0/gstreamer-1.0
mkdir -p "$HOOKDIR"
for helper in gst-plugin-scanner gst-ptp-helper; do
  [ -e "$HOOKDIR/$helper" ] || [ ! -e "$APPDIR/usr/lib/gstreamer-1.0/$helper" ] || ln -s "../../gstreamer-1.0/$helper" "$HOOKDIR/$helper"
done
# appimagetool looks for the AppStream file under its older name
ln -sf net.launchpad.beatbox.metainfo.xml "$APPDIR/usr/share/metainfo/net.launchpad.beatbox.appdata.xml"

PATH=$TOOLS:$PATH "$TOOLS/linuxdeploy-plugin-appimage-x86_64.AppImage" --appdir "$APPDIR"
ls -la "$WORK"/BeatBox-*.AppImage
