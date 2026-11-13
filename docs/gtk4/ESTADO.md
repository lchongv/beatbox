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
| T31 pruebas y primer arranque | H | [x] | dfbdd8a, f3f5e73, fef30cc | 0 | 17/17 pruebas con SMOKE_REQUIRED=1. El arranque se colgaba: ModeButton.append se llamaba a sí mismo y el manejador «forzar NORMAL» de RatingMenuItem limpiaba DIR_LTR en bucle; corregidos. La prueba smoke reintenta el Xvfb si otro le quita el número de pantalla e ignora el montaje del portal (run/doc) al limpiar: tres ejecuciones en paralelo pasan |
| T40 avisos y widgets ocultos | H | [x] | 220a213, 2737a27 | 0 | Corregidos: CRITICAL de AT-SPI (GTK_A11Y=none en pruebas y capturas), avisos del analizador CSS (T41), prefer-dark-theme → gtk-interface-color-scheme. Los 19 avisos «Trying to measure …» al arrancar venían de la pantalla de bienvenida: su texto con ajuste de línea hacía que el mínimo de la ventana dependiera del ancho (573 px estrecha, 466 a 1100) y GTK medía por debajo; la página va en un ScrolledWindow y las descripciones tienen ancho fijo. Riesgo 1: los 40 no_show_all retirados tienen visible=false o set_visible |
| T41 CSS y apariencias | H | [x] | 220a213, f84b68e | 0 | csscheck: data/theme.css y los 8 skins sin errores. Revisión visual de las 8 apariencias en Xvfb contra GTK3: barra de estado, botones de transporte (redondos), botón de menú redondo y rejilla de álbumes no recibían su estilo (selectores con la estructura de GTK3: actionbar.app-statusbar sobre la caja exterior, .transport-button > button, button.round-menu, iconview.albumgrid sobre la caja); corregidos |
| T42 pendientes | H | [x] | 2737a27…f6b55c2 | 0 | Las 14 marcas GTK4-PENDIENTE están cerradas (ninguna queda en el código); cada una, con lo hecho, en «Pendientes para el usuario» |
| T43 capturas | orquestador | [x] | f3f5e73 | 0 | docs/gtk4/capturas/gtk4-final.png; diferencias abajo |
| T50 empaquetado | D | [x] | bf1322c | 0 | sin verificar hasta el CI: Debian, Fedora, Arch y CI piden GTK 4; AppImage con DEPLOY_GTK_VERSION=4 (plugin de linuxdeploy sin verificar); Flatpak ya usa org.gnome.Platform 50 |
| T51 documentación | D | [x] | bf1322c | 0 | README, docs/plugins.md, docs/gtk4-prep.md y NEWS (2.0, unreleased). listeninglog.py no pide Gtk (solo BeatBox 1.0): sin cambios |

## Necesita un modelo más capaz

(vacío)

## Pendientes para el usuario

Cerrados el 2026-11-12 (segunda vuelta, con la GUI en Xvfb + xfwm4 y una biblioteca de prueba):

1. Vídeo: ya estaba apagado en 1.x (sin sumidero de vídeo; playbin solo audio). Se quitó el código del XID (`video_area_xid`). Si se quiere vídeo: gtk4paintablesink (instalado aquí) dibuja en un Gdk.Paintable.
2. Lista emergente: el gestor de ventanas la coloca (transitoria de la principal) cerca del centro de la ventana. Aceptado.
3. Mantener encima el mini reproductor: GTK 4 no puede. Se quitó la casilla (en X11 seguía activa sin efecto); la página explica «Siempre encima» del menú de la ventana. El texto, para conservar sus 43 traducciones, sigue diciendo «En Wayland».
4. Submenús del visualizador: elegir ahora cierra toda la cadena de menús. Se abren al pulsar (GTK3: al pasar el ratón).
5. WindowHandle: GTK solo maximiza con doble clic ventanas sin padre transitorio; las dos que lo usan lo tienen. El doble clic de la carátula ampliada (cerrar) va en fase de captura y funciona. Arrastrar la carátula del LCD ya no mueve la ventana (la pulsación se reclama con un gesto agrupado con el DragSource).
6. Iconos simbólicos en pixbuf: se tiñen con el color del contexto (UI.tint), como load_symbolic_for_context.
7. Barra de estado: sus iconos son SVG simbólicos que GTK 4 recolorea solo; comprobado al pasar a Adwaita oscuro.
8. size-allocate: el botón redondo queda bien tras cambiar de skin; el panel de información conserva su ancho al maximizar.
9. Tamaño de ventana: 1100×600 estable entre sesiones y tras el mini reproductor; se quitó la corrección de la barra de título de GTK3. La carátula ampliada encoge con el zoom.
10. Acerca de: dice «Ported to GTK 4»; las traducciones se actualizaron igual.
11. «(None)»: era el texto del FileChooserButton de GTK3; añadida la traducción al español («(Ninguna)»).
12. `--display`: anotado en NEWS (usar la variable DISPLAY).
13. Avisos de medida al arrancar: corregidos (T40).

Fallos encontrados y corregidos en esta vuelta (ninguno estaba marcado): escribir tres letras en el buscador cerraba el programa; la primera tecla iba a la búsqueda interactiva de la barra lateral en vez de al buscador (y daba un CRITICAL); el muro de álbumes tenía una columna y no mostraba carátulas hasta redibujar; los size_allocate/measure de subclases de Box no se llamaban nunca (marquesina, letras, SpaceWidget, carátula del LCD); el panel de información se abría recortado a ~70 px; carátulas y estrellas en celdas a 16 px; el menú de columnas de la cabecera abría el menú de la canción; menús sobre un TreeView daban un CRITICAL; soltar archivos sobre la ventana leía el FileList como objeto; flechas de la barra lateral sin dibujar; icono del ecualizador como tres puntos; botones de las preferencias a la izquierda.

Queda:

- Un menú largo abierto cerca del borde inferior se sale de la pantalla en X11 (el visualizador en una pantalla de 800 px); en Wayland lo ajusta el compositor. Sin desplazamiento propio dentro de PopMenu.
- Errores de formato en traducciones que ya estaban (msgfmt -c): ar, de, fr, hi, it, ko, pt_BR. Un printf con especificadores distintos puede romper ese texto.
- Last.fm: la clave de la API responde y el inicio de sesión llega a Last.fm (rechaza un usuario inventado con «Authentication Failed»); falta probar con una cuenta real.
- Revisión manual en el escritorio real: arrastre de varias canciones a listas, Cover Flow, editor de canciones, importar una carpeta soltándola.

## Diferencias vistas en las capturas

Contra `docs/gtk4/capturas/gtk3-referencia.png`, `gtk4-final.png` tiene la misma estructura: barra superior, barra lateral con sus flechas, panel central con la pantalla de bienvenida y barra inferior con el icono de ecualizador (deslizadores). La ventana mide 1100×600 (la referencia se tomó con 700 de alto guardados). Los botones de reproducción salen más claros porque están desactivados sin biblioteca: así pinta Adwaita de GTK 4 un botón desactivado. Con la misma biblioteca y la misma apariencia, el muro, la lista, el LCD con carátula, la lista emergente y las 8 apariencias se compararon contra la compilación GTK3 (`build/beatbox`) y coinciden salvo detalles de tema.

## Resumen final

Estado de la rama `gtk4` (sin fusionar, sin publicar, sin etiquetar, sin instalar):

- Arranque y uso: la ventana aparece sin avisos de BeatBox; reproducción, búsqueda con sugerencias, muro y rejilla, lista con valoraciones, panel de información, mini reproductor, preferencias, cambio de apariencia, visualizador clásico y carátula del LCD probados en Xvfb.
- Pruebas: 17/17 con SMOKE_REQUIRED=1; la prueba smoke aguanta ejecuciones en paralelo.
- Captura: gtk4-final.png sin CRITICAL ni avisos.
- Marcas GTK4-PENDIENTE: ninguna.
- Empaquetado y CI: sin verificar localmente.

## Revisión del 13-11-2026 (rejilla de carátulas y apariencia)

Comparado con la versión GTK 3 lado a lado, también en una sesión GNOME/Wayland sin pantalla
(`gnome-shell --headless`), con la apariencia «template», ventana maximizada y 45 álbumes.

- **Rejilla de carátulas en blanco al desplazar:** el muro solo pinta la parte visible y GTK 4 desplaza
  moviendo el último dibujo, sin volver a pintar. Ahora se repinta al cambiar el desplazamiento.
- **Filas 3 px más bajas** en las listas y la barra lateral: GTK 3 añadía ese alto a cada fila (`UI.GTK3_ROW_EXTRA`, `ListText`).
- **Barra superior:** GTK 4 separaba los elementos 6 px (`border-spacing` de Adwaita); el botón del menú
  salía 5 px más pequeño (se medía el LCD sin borde ni relleno).
- **Barra de estado:** los iconos de aleatorio y repetir quedaban pegados arriba.
- **Flechas de la barra lateral:** del tamaño y en el sitio de GTK 3.
- Aviso `GtkGizmo (highlight) reported min width -2` con las apariencias no nativas: corregido.
