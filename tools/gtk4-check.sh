#!/bin/bash
# Port a GTK4: errores de valac de TODO el código (core + src) en una sola pasada,
# filtrados por los archivos o carpetas que se pasen como argumento.
#
#   tools/gtk4-check.sh                      # resumen: errores por archivo
#   tools/gtk4-check.sh src/Dialogs          # errores de esa carpeta (con contexto)
#   tools/gtk4-check.sh src/Widgets/StatusBar.vala core/Utils/UI.vala
#
# Sale con 0 si no hay errores en lo pedido (sin argumentos: en nada).
# No toca el directorio de compilación: varios agentes pueden correrlo a la vez.
# Solo genera C (no lo compila ni enlaza): el cierre de cada fase usa ninja.
# Ver docs/gtk4/RECETAS.md ("Las dos etapas del compilador").
set -u
cd "$(dirname "$0")/.."
B=${BUILD:-build-gtk4}
[ -f "$B/build.ninja" ] || { echo "Falta $B. Créalo: meson setup $B -Dprefix=\$HOME/.local" >&2; exit 2; }

# build.ninja al día (archivos nuevos en meson.build); con candado porque ninja no admite dos a la vez
flock "$B/.gtk4-check.lock" ninja -C "$B" build.ninja >/dev/null 2>&1

cmds=$(ninja -C "$B" -t commands 2>/dev/null | grep -E '^valac .*--library beatbox(-core)? ')
[ -n "$cmds" ] || { echo "No encuentro los comandos de valac en $B" >&2; exit 2; }
srcs=$(grep -oE '\.\./[^ ]+\.vala' <<<"$cmds" | sed 's|^\.\./||' | sort -u)
flags=$(grep -oE -- '(-D [A-Z_]+|--pkg [^ ]+)' <<<"$cmds" | sort -u | tr '\n' ' ')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2086
valac -C -d "$tmp" --vapidir=vapi --target-glib=2.56 $flags "$B/config.vala" $srcs >"$tmp/log" 2>&1
log=$(sed 's/\x1b\[[0-9;]*m//g' "$tmp/log")

total=$(grep -c ' error: ' <<<"$log")
stage="2 (semántica)"
grep -q "error: The type name .* could not be found\|error: The symbol .* could not be found\|error: syntax error" <<<"$log" \
  && stage="1 (tipos o sintaxis: mientras existan, el compilador NO muestra los demás errores)"

if [ $# -eq 0 ]; then
  grep -E '^[^ ]+\.vala:[0-9.-]+: error: ' <<<"$log" | sed -E 's/:[0-9].*//' | sort | uniq -c | sort -rn
  echo "TOTAL: $total errores. Etapa $stage"
  [ "$total" -eq 0 ]; exit
fi

pat=$(printf '%s\n' "$@" | sed -E 's|/+$||; s/[.[\*^$]/\\&/g' | paste -sd'|')
mine=$(grep -E -A2 "^($pat)[^ ]*:[0-9.-]+: error: " <<<"$log")
n=$(grep -c ' error: ' <<<"$mine")
[ -n "$mine" ] && echo "$mine"
echo "EN LO PEDIDO: $n errores (total del proyecto: $total). Etapa $stage"
[ "$n" -eq 0 ]
