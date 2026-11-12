#!/bin/bash
# Port a GTK4: arranca un BeatBox recién compilado en una pantalla virtual, con una
# carpeta personal vacía y su propio D-Bus (no toca la sesión ni la colección del
# usuario), guarda una captura y muestra los avisos que el programa escribió.
#   tools/gtk4-shot.sh build-gtk4/beatbox docs/gtk4/capturas/gtk4.png
#   WAIT=60 tools/gtk4-shot.sh build/beatbox /tmp/gtk3.png      # espera distinta (por defecto 45 s)
# Sale con 1 si el programa murió antes de la captura. El registro queda junto al PNG (.log).
set -u
exe=$(realpath "${1:?uso: gtk4-shot.sh <ejecutable> <salida.png>}")
out=$(realpath -m "${2:?falta la ruta del PNG}")
mkdir -p "$(dirname "$out")"
tmp=$(mktemp -d)
mkdir -p "$tmp/home"
Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp 3>"$tmp/display" 2>/dev/null &
xpid=$!
trap 'kill $xpid 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do [ -s "$tmp/display" ] && break; sleep 0.1; done
d=$(cat "$tmp/display"); [ -n "$d" ] || { echo "Xvfb no arrancó" >&2; exit 2; }

# sin WAYLAND_DISPLAY y con su propio bus: si no, se abriría en el escritorio real o
# le hablaría al BeatBox que el usuario tiene abierto
env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
    XDG_DATA_HOME="$tmp/home/.local/share" XDG_CACHE_HOME="$tmp/home/.cache" \
    DISPLAY=":$d" GDK_BACKEND=x11 GSETTINGS_BACKEND=keyfile NO_AT_BRIDGE=1 \
  dbus-run-session -- bash -c '
    "$0" >"$1" 2>&1 & pid=$!
    sleep "${WAIT:-45}"
    alive=0; kill -0 $pid 2>/dev/null && alive=1
    import -window root "$2"
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    [ $alive = 1 ]' "$exe" "${out%.png}.log" "$out" 2>/dev/null
rc=$?
echo "--- avisos (${out%.png}.log) ---"
grep -aE 'CRITICAL|WARNING|Theme pars|Segmentation|assertion' "${out%.png}.log" | sort | uniq -c | sort -rn | head -40
[ $rc = 0 ] && echo "OK: captura en $out" || echo "FALLO: el programa no seguía vivo al capturar"
exit $rc
