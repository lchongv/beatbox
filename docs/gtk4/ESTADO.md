# Estado del port a GTK4

Lo mantiene el orquestador (`docs/gtk4/ORQUESTADOR.md`).
`[ ]` sin empezar · `[~]` en curso · `[x]` pasó la puerta y tiene commit · `BLOQUEADA` con motivo.

Línea base medida antes de empezar (2026-11-12, copia de prueba): 1.549 errores en
etapa 2 con el andamio; `tools/gtk4-check.sh` tarda ~2 s.

## Tareas

| Tarea | Quién | Estado | Commit | Pendientes | Notas |
|---|---|---|---|---|---|
| T00 rama, meson y andamio | orquestador | [x] | | | total de errores: 1549 (etapa 2) |
| T01 utilidades y PopMenu | H | [x] | | 2 | icono simbólico sin colores de contexto (Icon.vala:213); WindowHandle también maximiza con doble clic (UI.vala:117) |
| T02 resto de core | H | [x] | | 0 | a verificar en T31: rayas de FastList (se pintan antes que el fondo), rueda de StyledBox.set_widget (mismo comportamiento que antes: sin handler) |
| T10 diálogos | D | [x] | | 0 | |
| T11 preferencias | D | [~] | | | |
| T12 ventanas | D | [~] | | | |
| T13 editores | D | [~] | | | |
| T14 sueltos | D | [x] | | 0 | export_playlist_to_file es async: SourceViews la llama sin yield (T16 debe usar .begin) |
| T15 widgets simples | D | [x] | | 1 | StatusBar: el icono se tiñe solo al crearse (no sigue a un cambio de skin): StatusBar.vala:66 |
| T16 vistas de origen | D | [x] | | 0 | arrastre de la lista de reproducción sin probar; MiddlePaned centra el divisor a mano |
| T20 listas (base y música) | H | [x] | | 0 | arrastre de varias filas sin probar (riesgo 3, revisión manual); «Añadir a lista» abre el submenú al pulsar, no al pasar el ratón; DropTarget de la cola sin confirmar en 4.6 |
| T21 otras listas | D | [x] | | 0 | |
| T22 rejillas y lista emergente | H | [x] | | 1 | la lista emergente ya no se centra sobre el muro (GTK4 no coloca ventanas): PopupListView.vala show_list() |
| T23 muro de álbumes | H | [x] | | 0 | pulsar en el relleno vacío de la banda ya no la cierra (antes sí): revisión manual; SourceView.vala lo cubre T16 (wall_scroll.set_child) |
| T24 widgets dibujados | H | [~] | | | |
| T25 barra lateral | H | [x] | | 0 | arrastre a listas: solo texto (ya no acepta archivos de fuera); flecha de expansión con render_arrow; color de selección con theme_selected_fg_color; posible doble resaltado al arrastrar: revisión manual |
| T26 «Reproduciendo» | H | [x] | | 0 | video_area_xid borrado: LibraryWindow.vala:50 (T27) y Streamer.vala 269/338/424/517/519 (T14) lo leían: decidir 0 o quitarlo (T42); EventBox de letras y resumen pasa al widget que envolvía, sin GestureClick |
| T27 ventana principal | H | [x] | | 5 | video_area_xid devuelve 0 (Streamer.vala lo usa: T42); keep-above perdido en mini; tamaño con barra de título (track_size); clic en carátula del LCD sin reclamar; divisor de TrackReport diferido. Revisión GUI: semáforo, atajos con foco en campo, arrastre de archivos, WindowHandle |
| T28 núcleo de la aplicación | H | [~] | | | |
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
