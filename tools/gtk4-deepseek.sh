#!/bin/bash
# Port a GTK4: lanza un trabajador Deepseek gratuito (OpenCode) para UNA tarea del plan.
#   tools/gtk4-deepseek.sh T10            # bloquea hasta que termina (máx. 45 min)
# Deja el registro en build-gtk4/logs/T10.log. El modelo se puede cambiar con MODEL=...
# El trabajador no hace commits: los hace el orquestador (docs/gtk4/ORQUESTADOR.md).
set -u
cd "$(dirname "$0")/.."
T=${1:?uso: tools/gtk4-deepseek.sh T10}
PLAN=docs/superpowers/plans/2026-11-12-gtk4-port.md
grep -q "^### $T:" "$PLAN" || { echo "No existe la tarea $T en $PLAN" >&2; exit 2; }
mkdir -p build-gtk4/logs
timeout 2700 opencode run --auto --title "gtk4 $T" \
  -m "${MODEL:-opencode/deepseek-v4.1-flash-free}" \
  "Eres un trabajador del port de BeatBox (Vala) de GTK3 a GTK4. \
1) Lee COMPLETO docs/gtk4/RECETAS.md. \
2) Lee en $PLAN las secciones 'Restricciones globales' y 'Pasos comunes' de la fase 2, y solo la tarea que empieza con '### $T:' (hasta el siguiente '###'). \
3) Haz esa tarea y nada más: edita solo los archivos que la tarea te asigna. \
4) Verifica con el comando 'Comprobar' de la tarea hasta que diga 0 errores o hasta que solo queden errores que no sabes resolver. \
5) No hagas git commit, git checkout, git stash ni git reset. No borres ni comentes funcionalidad para que compile. \
6) Termina escribiendo un informe breve: archivos tocados, salida final del comando Comprobar, y cada '// GTK4-PENDIENTE' que dejaste con su motivo." \
  2>&1 | tee "build-gtk4/logs/$T.log"
