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
| T11 preferencias | H (orquestador) | [x] | | 0 | carpetas: botón + diálogo (como T28); acerca de dice «Ported to GTK 4» (texto visible cambiado); editor de skins usa close_request; Lastfm: el spinner queda oculto (como en GTK3) |
| T12 ventanas | H (orquestador) | [x] | b7d057c | 0 | DirectoryDialog.add_station_by_url es async (3 llamadores con .begin); SkinEditor: al cerrar pregunta con diálogo asíncrono; feedback del quitar duplicados a la izquierda con relleno (no set_child_secondary) |
| T13 editores | H (orquestador) | [x] | | 0 | SongEditor: carátulas por UI.show_pixbuf, identificar y selector de carátula async o por señal; SmartPlaylistEditor: EventBox sustituido por caja con controlador de rueda en captura; MediaEditor: pestañas medidas con measure |
| T14 sueltos | D | [x] | | 0 | export_playlist_to_file es async: SourceViews la llama sin yield (T16 debe usar .begin) |
| T15 widgets simples | D | [x] | | 1 | StatusBar: el icono se tiñe solo al crearse (no sigue a un cambio de skin): StatusBar.vala:66 |
| T16 vistas de origen | D | [x] | | 0 | arrastre de la lista de reproducción sin probar; MiddlePaned centra el divisor a mano |
| T20 listas (base y música) | H | [x] | | 0 | arrastre de varias filas sin probar (riesgo 3, revisión manual); «Añadir a lista» abre el submenú al pulsar, no al pasar el ratón; DropTarget de la cola sin confirmar en 4.6 |
| T21 otras listas | D | [x] | | 0 | |
| T22 rejillas y lista emergente | H | [x] | | 1 | la lista emergente ya no se centra sobre el muro (GTK4 no coloca ventanas): PopupListView.vala show_list() |
| T23 muro de álbumes | H | [x] | | 0 | pulsar en el relleno vacío de la banda ya no la cierra (antes sí): revisión manual; SourceView.vala lo cubre T16 (wall_scroll.set_child) |
| T24 widgets dibujados | H | [x] | | 3 | submenús de Visualizer se abren al clicar y solo cierran el submenú (Visualizer.vala:303, :497); LcdCover set_default_size(1,1) sin probar (LcdCover.vala:144); RatingWidget.css_changed sustituye a context.changed |
| T25 barra lateral | H | [x] | | 0 | arrastre a listas: solo texto (ya no acepta archivos de fuera); flecha de expansión con render_arrow; color de selección con theme_selected_fg_color; posible doble resaltado al arrastrar: revisión manual |
| T26 «Reproduciendo» | H | [x] | | 0 | video_area_xid borrado: LibraryWindow.vala:50 (T27) y Streamer.vala 269/338/424/517/519 (T14) lo leían: decidir 0 o quitarlo (T42); EventBox de letras y resumen pasa al widget que envolvía, sin GestureClick |
| T27 ventana principal | H | [x] | | 5 | video_area_xid devuelve 0 (Streamer.vala lo usa: T42); keep-above perdido en mini; tamaño con barra de título (track_size); clic en carátula del LCD sin reclamar; divisor de TrackReport diferido. Revisión GUI: semáforo, atajos con foco en campo, arrastre de archivos, WindowHandle |
| T28 núcleo de la aplicación | H | [x] | | 0 | opciones de GTK (--display) ya no se parsean; «(None)» del selector de bibliotecas es texto nuevo sin traducir; LibrarySwitcher.new_library es async |
| T29 código C | H | [x] | | 0 | comentarios nuevos en español, como el resto de ese archivo |
| T30 cierre de compilación | H (orquestador) | [x] | | 0 | valac 0 errores; ninja termina (beatbox, plugins y pruebas). Antes del cierre: 4 clases que heredaban de tipos opacos de GTK 4 (ScrolledWindow, IconView, Separator, Notebook, Image, Viewport, ActionBar, SearchEntry, CellRendererPixbuf, Stack) pasan a composición |
| T31 pruebas y primer arranque | H | [x] | dfbdd8a, f3f5e73 | 1 | 17/17 pruebas con SMOKE_REQUIRED=1. El arranque se colgaba: ModeButton.append se llamaba a sí mismo (ModeButton.vala) y el manejador «forzar NORMAL» de RatingMenuItem limpiaba DIR_LTR en bucle; corregidos. Una vez falló la prueba smoke con «Failed to open display» (el Xvfb de la prueba aún no estaba listo); dos reintentos pasan: vigilar |
| T40 avisos y widgets ocultos | H | [~] | 220a213 | 1 | Corregidos: CRITICAL de AT-SPI (GTK_A11Y=none en pruebas y capturas), avisos de analizador CSS (T41), prefer-dark-theme → gtk-interface-color-scheme. Riesgo 1: los 40 no_show_all retirados tienen ahora visible=false o set_visible en el código actual; show()/hide() siguen funcionando en 4.24 (son gtk_widget_show/hide, deprecados). PENDIENTE: 19 avisos «Trying to measure BeatBoxLibraryWindow … height of 466, but it needs at least 573» al arrancar: la ventana recibe 466 px en su primera asignación y su mínimo es 573; con 590 px no hay aviso. La cadena de mínimos cuelga de la pantalla de bienvenida (BeatBoxWelcome, rejilla de 184 px dada 118). Causa no confirmada |
| T41 CSS y apariencias | H | [x] | 220a213 | 2 | csscheck: data/theme.css y los 8 skins sin errores; los 8 bloques CSS embebidos en el código también. Cambios: -gtk-gradient → linear-gradient; -unico-* quitados (no aparecen en el registro de GTK 3); toolbar/toolbutton/toolitem → clases; :nth-child(first/last) → :first-child/:last-child; -GtkToolbar-button-relief quitado. PENDIENTE: revisión visual de cada apariencia; la cabecera solo cambia con un skin no nativo (el nativo no carga theme.css) |
| T42 pendientes | H | [x] | | 14 | 14 marcas GTK4-PENDIENTE: ninguna tiene solución sin decisión del usuario o una prueba visual. Cada una está en «Pendientes para el usuario» |
| T43 capturas | orquestador | [x] | f3f5e73 | 0 | docs/gtk4/capturas/gtk4-final.png; diferencias abajo |
| T50 empaquetado | D | [x] | bf1322c | 0 | sin verificar hasta el CI: Debian, Fedora, Arch y CI piden GTK 4; AppImage con DEPLOY_GTK_VERSION=4 (plugin de linuxdeploy sin verificar); Flatpak ya usa org.gnome.Platform 50 |
| T51 documentación | D | [x] | bf1322c | 0 | README, docs/plugins.md, docs/gtk4-prep.md y NEWS (2.0, unreleased). listeninglog.py no pide Gtk (solo BeatBox 1.0): sin cambios |

## Necesita un modelo más capaz

(vacío)

## Pendientes para el usuario

1. Vídeo en la ventana «Reproduciendo»: `video_area_xid` devuelve 0 (`src/Core/LibraryWindow.vala:49`, `Streamer.vala`). GTK 4 no da un XID por widget. Solución: gtk4paintablesink (decisión).
2. Lista emergente centrada sobre el muro: GTK 4 no coloca ventanas (`src/Views/PopupListView.vala:244`).
3. Mantener la ventana encima en el modo mini: GTK 4 no lo permite (`LibraryWindow.vala`, `apply_keep_above`).
4. Submenús del visualizador: se abren al pulsar y al elegir solo cierran el submenú (`src/Widgets/Visualizer.vala:303`, `:497`).
5. Barra de título: `Gtk.WindowHandle` también maximiza con doble clic (`core/Utils/UI.vala:117`); arrastre y doble clic por revisar en la GUI (`LibraryWindow.vala:382`).
6. Icono simbólico sin los colores del contexto (`core/Utils/Icon.vala:213`).
7. Icono de la barra de estado: se tiñe solo al crearse, no al cambiar de skin (`src/Widgets/StatusBar.vala:68`).
8. Tamaños que dependían de `size-allocate` (GTK 4 no lo tiene en Box ni en Paned): botón redondo del LCD (`LibraryWindow.vala:472`) y divisor principal (`LibraryWindow.vala:541`). Revisar en la GUI.
9. Tamaño de la ventana con la barra de título (`LibraryWindow.vala:202`) y `set_default_size (1, 1)` del LCD (`src/Widgets/TopDisplay/LcdCover.vala:150`). Revisar en la GUI.
10. Decisión: el texto de Acerca de dice «Ported to GTK 4» (antes GTK 3); es un cambio visible.
11. Decisión: «(None)» del selector de bibliotecas es texto nuevo sin traducir.
12. Decisión: la opción `--display` de GTK ya no se analiza.
13. Avisos de medida de la ventana al arrancar (T40): sin resolver.

## Diferencias vistas en las capturas

Contra `docs/gtk4/capturas/gtk3-referencia.png`, el resultado final (`gtk4-final.png`) tiene la misma estructura: barra superior, barra lateral, panel central con la pantalla de bienvenida y barra inferior.
Diferencias: no aparecen las flechas de expansión de la barra lateral; el icono de ajustes de la barra inferior derecha es otro (puntos en vez de deslizadores); los iconos de reproducción salen grises y el deslizador de volumen tiene la pista gris en vez de azul; la cabecera es más plana (tema nativo de Adwaita en vez del de GTK 3).
La ventana mide 1100×590 frente a unos 1110×700 de la referencia; no se ha comprobado si se debe a la configuración de la captura. El título «BeatBox 1.2.x» se solapa con los botones de modo también en la referencia (no es nuevo).

## Resumen final

Estado de la rama `gtk4` (sin fusionar, sin publicar, sin etiquetar, sin instalar):

- Arranque: la ventana aparece y el proceso queda en reposo. El bucle al arrancar estaba en ModeButton.append (recursión) y en RatingMenuItem (manejador de estado); corregidos en dfbdd8a.
- Pruebas: 17/17 con SMOKE_REQUIRED=1 (una vez falló por la carrera del Xvfb de la prueba; dos reintentos pasan).
- Captura: gtk4-final.png sin avisos de CRITICAL ni del analizador CSS. Queda 1 aviso de BeatBox: la medida de la ventana al arrancar (T40, pendiente).
- Riesgo 2 (pixbuf en Gtk.Image): sin hallazgos. Las tres coincidencias de set_*_from_pixbuf son de otras API (iPod y libnotify).
- Pendientes de código: 14 marcas GTK4-PENDIENTE (lista arriba). Ninguna se puede comprobar sin la GUI.
- Revisión manual que sigue siendo del usuario: arrastre de varias canciones a listas, menús contextuales, rejillas/muro/Cover Flow/visualizador, cada apariencia clara y oscura, editor de canciones, mini reproductor, importar una carpeta soltándola sobre la ventana.
- Empaquetado y CI: sin verificar localmente.
