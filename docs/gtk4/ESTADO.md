# Estado del port a GTK4

Lo mantiene el orquestador (`docs/gtk4/ORQUESTADOR.md`).
`[ ]` sin empezar · `[~]` en curso · `[x]` pasó la puerta y tiene commit · `BLOQUEADA` con motivo.

Línea base medida antes de empezar (2026-11-12, copia de prueba): 1.549 errores en
etapa 2 con el andamio; `tools/gtk4-check.sh` tarda ~2 s.

## Tareas

| Tarea | Quién | Estado | Commit | Pendientes | Notas |
|---|---|---|---|---|---|
| T00 rama, meson y andamio | orquestador | [x] | | | total de errores: 1549 (etapa 2) |
| T01 utilidades y PopMenu | H | [ ] | | | |
| T02 resto de core | H | [ ] | | | |
| T10 diálogos | D | [ ] | | | |
| T11 preferencias | D | [ ] | | | |
| T12 ventanas | D | [ ] | | | |
| T13 editores | D | [ ] | | | |
| T14 sueltos | D | [ ] | | | |
| T15 widgets simples | D | [ ] | | | |
| T16 vistas de origen | D | [ ] | | | |
| T20 listas (base y música) | H | [ ] | | | |
| T21 otras listas | D | [ ] | | | |
| T22 rejillas y lista emergente | H | [ ] | | | |
| T23 muro de álbumes | H | [ ] | | | |
| T24 widgets dibujados | H | [ ] | | | |
| T25 barra lateral | H | [ ] | | | |
| T26 «Reproduciendo» | H | [ ] | | | |
| T27 ventana principal | H | [ ] | | | |
| T28 núcleo de la aplicación | H | [ ] | | | |
| T29 código C | H | [x] | | 0 | comentarios nuevos en español, como el resto de ese archivo |
| T30 cierre de compilación | H | [ ] | | | |
| T31 pruebas y primer arranque | H | [ ] | | | |
| T40 avisos y widgets ocultos | H | [ ] | | | |
| T41 CSS y apariencias | H | [ ] | | | |
| T42 pendientes | H | [ ] | | | |
| T43 capturas | orquestador | [ ] | | | |
| T50 empaquetado | D | [ ] | | | sin verificar hasta el CI |
| T51 documentación | D | [ ] | | | |

## Necesita un modelo más capaz

(vacío)

## Pendientes para el usuario

(vacío)

## Diferencias vistas en las capturas

(vacío)

## Resumen final

(vacío)
