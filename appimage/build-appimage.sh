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
[ -d "$WORK/build" ] || meson setup "$WORK/build" "$SRC" --prefix=/usr --libdir=lib --buildtype=release
ninja -C "$WORK/build"
DESTDIR=$APPDIR meson install -C "$WORK/build" --no-rebuild

# HTTPS (album art, lyrics, radio, scrobbling) needs GIO's TLS module, which GIO only finds
# in the bundle through GIO_MODULE_DIR. The bundled GnuTLS knows only Debian's CA bundle:
# elsewhere SSL_CERT_FILE names the system's, which BeatBox then loads itself.
GIOMODULES=$(pkg-config --variable=giomoduledir gio-2.0)
mkdir -p "$APPDIR/usr/lib/gio/modules" "$APPDIR/apprun-hooks"
cp "$GIOMODULES/libgiognutls.so" "$GIOMODULES/libgioenvironmentproxy.so" "$APPDIR/usr/lib/gio/modules/"
cat > "$APPDIR/apprun-hooks/beatbox-tls.sh" <<'EOF'
export GIO_MODULE_DIR="$APPDIR/usr/lib/gio/modules"
if [ ! -e /etc/ssl/certs/ca-certificates.crt ] && [ -z "${SSL_CERT_FILE:-}" ]; then
  for ca in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    if [ -e "$ca" ]; then export SSL_CERT_FILE="$ca"; break; fi
  done
fi
EOF

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
# linuxdeploy points the GIO modules at their own directory; their libraries are two levels up
patchelf --set-rpath '$ORIGIN/../..' "$APPDIR"/usr/lib/gio/modules/*.so
# BeatBox doesn't use the tag muxers, whose plugin can bring a second TagLib (the system's
# 1.x next to the 2.x BeatBox links): two TagLib ABIs in one process would clash
rm -f "$APPDIR/usr/lib/gstreamer-1.0/libgsttaglib.so" "$APPDIR/usr/lib/libtag.so.1"
# The sound server's client library has to be the system's (its ABI is stable): Ubuntu 22.04's
# libpulse leaves a stream resumed after a seek in pause stalled on current PipeWire.
# Without one, GStreamer falls back to ALSA.
rm -f "$APPDIR"/usr/lib/libpulse.so.0 "$APPDIR"/usr/lib/libpulse-simple.so.0 "$APPDIR"/usr/lib/libpulsecommon-*.so
# appimagetool looks for the AppStream file under its older name
ln -sf net.launchpad.beatbox.metainfo.xml "$APPDIR/usr/share/metainfo/net.launchpad.beatbox.appdata.xml"

PATH=$TOOLS:$PATH "$TOOLS/linuxdeploy-plugin-appimage-x86_64.AppImage" --appdir "$APPDIR"
ls -la "$WORK"/BeatBox-*.AppImage
