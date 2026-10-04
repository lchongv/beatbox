# Preparación para GTK4 (paso intermedio)

Objetivo: dejar el código sin APIs obsoletas de GTK3 y con contenedores al
estilo GTK4, **sin cambiar de versión de GTK**. Cada fase compila y funciona
sola; se puede hacer de a una por sesión y commitear al terminar.

Línea base (oct 2026): ~250 avisos de obsolescencia al compilar.
Para medir el avance:

    find src core -name '*.vala' -exec touch {} + && ninja -C build 2>&1 | grep -c deprecated

Regla para cada fase: compilar sin avisos nuevos, abrir el programa,
probar la pantalla tocada y probar los skins Default y Nativo.

## Fase 1 — Gtk.Stock → nombres de ícono (~2 h) 
~75 avisos. `Gtk.Stock.*`, `Image.from_stock`, `Button.from_stock`,
`drag_source_set_icon_stock`, `render_icon*`.
- `Gtk.Stock.CANCEL` → texto `_("Cancel")` en botones; íconos → `"process-stop"`, `"document-open"`, `"dialog-error"`, etc.
- `new Image.from_stock(x, size)` → `new Image.from_icon_name(name, size)`.
- Mecánico, bajo riesgo.

## Fase 2 — Márgenes y alineación (~2 h)
~35 avisos. `margin_left/right` → `margin_start/end`;
`Gtk.Alignment` → márgenes + `halign/valign` en el hijo; `Gtk.Arrow` → `Image` con `"pan-down-symbolic"`.

## Fase 3 — Cajas de botones (~1 h)
34 avisos. `Gtk.HButtonBox` → `Gtk.ButtonBox(HORIZONTAL)` o, mejor, `Gtk.Box` (GTK4 no tiene ButtonBox).

## Fase 4 — Gtk.Action → GLib.Action (~4 h)
19 avisos, en Actions.vala y quien las use. Pasar a `SimpleAction` en la
ventana/aplicación + atajos con `set_accels_for_action`. Es la base de los menús GTK4.

## Fase 5 — Menús emergentes (~3 h)
13 `Menu.popup` → `popup_at_pointer`/`popup_at_widget`. Si da el tiempo,
pasar menús simples a `Gtk.Popover` con `GMenu` (lo que pide GTK4).

## Fase 6 — Varios sueltos (~2 h)
`add_with_viewport` → `add`; `override_background_color` → CSS;
`show_uri` → `AppInfo.launch_default_for_uri`; `Gdk.Screen.get_height`/
`get_pointer` → `Gdk.Monitor`/`Gdk.Seat`; `set_rules_hint`, `set_has_resize_grip`,
`double_buffered`, `ComboBox.set_title` → borrar.

## Fase 7 — GStreamer (~1 h)
28 `DiscovererInfo.get_tags` → `get_stream_info().get_tags()` (o de cada stream de audio).
No es GTK, pero limpia la salida.

## Fase 8 — Contenedores estilo GTK4 (~6–10 h, por carpetas)
411 `pack_start`, 128 `show_all`. GTK4 solo tiene `append/prepend` y los
widgets son visibles por defecto.
- `box.pack_start(w, expand, fill, pad)` → `w.hexpand/vexpand = expand; w.margin_* = pad; box.add(w)`
  (en GTK3 `add` ya equivale a `append`).
- Hacerlo por carpeta: Widgets/ → Views/ → Dialogs/ → Core/.
- `show_all` se deja en GTK3 (sigue haciendo falta); solo anotarlos. Se borran al migrar.

## Fase 9 — Eventos con controladores (~8 h, opcional)
101 `*_event`. GTK3.24 ya trae `GestureMultiPress`, `EventControllerKey`,
`EventControllerScroll`, `EventControllerMotion`. Pasarlos ahora hace que
en GTK4 sea solo renombrar. Empezar por los más simples (clics y teclas).

## Fuera de alcance (solo en la migración real)
TreeView/CellRenderer → ColumnView, IconView → GridView, drag & drop,
Granite 6 → 7, revisión de CSS de skins.

Total fases 1–8: ~20–25 h. Fase 9: +8 h.

## Estado
- [x] Fases 1, 2, 3 y 6 (commit 00e5fd9): 214 → 121 avisos.
- [x] Fases 4 y 5: 121 → 56 avisos. Las acciones son `SimpleAction` en
      `App.actions.group` ("bb.<nombre>"); `App.actions.menu_item(a)` crea la
      entrada de menú (gris si la acción está deshabilitada; los duplicados se
      ocultan). EmbeddedAlert perdió los botones de acción (nadie los usaba).
      Menús con `popup_at_pointer`/`popup_at_widget`. Queda pasar a `GMenu` + `Popover`.
- [x] Fase 7: `GStreamerTagger.all_tags(info)` junta las etiquetas del contenedor y
      de cada stream (en MP4 están en el contenedor). Probado importando MP3, FLAC,
      OGG y M4A con la versión vieja y la nueva: mismas filas en la base, y además
      el año ahora se importa (venía en DATE_TIME y quedaba en 0).
- [~] Fase 8: 219 `pack_start(w, false, *, 0)` → `add(w)` (equivalentes exactos;
      pantallas idénticas píxel a píxel). Quedan ~200 con expand o padding: pasarlos a
      `hexpand`/márgenes cambia el diseño en GTK3 (hexpand se propaga a los padres),
      así que van en la migración real, revisando cada pantalla. Tampoco los 77 `pack_end`.
- [~] Fase 9: CoverFlow (rueda, teclas) y el visor de carátula usan
      `EventControllerScroll`/`EventControllerKey`. Quedan ~55 `*_event`: los clics de
      las listas devuelven true para conservar la selección y la ventana principal
      intercepta teclas antes que la búsqueda; con controladores cambia el orden, así
      que conviene hacerlos junto con TreeView → ColumnView.
- [x] Resto: Granite.Application → Gtk.Application (el formato del log se conserva
      con Granite.Services.Logger; depuración con G_MESSAGES_DEBUG en vez de --debug),
      Gdk.X11.Window, Gst.Format.get_by_nick, `.begin` explícitos, ImageMenuItem →
      MenuItem con caja, OptionChooser sin Gtk.Action. Al ejecutar: sin los 46 avisos
      de GENERIC_FALLBACK de los íconos.
- Avisos de obsolescencia: 214 → 0.
- Quedan además: Granite.Application (se va con Granite 7), Gdk.X11Window del
  video (en GTK4 se usa gtk4paintablesink), CDRipper `format_get_by_nick`.

# Hoja de ruta
0.9: solo limpieza (errores y avisos de obsolescencia). Lo pendiente pasa a 0.10.

## Hecho en 0.9
1. [x] Reproducción sin cortes (ya existía; verificada) + ReplayGain (Preferencias › Comportamiento). Crossfade: pendiente, requiere dos playbin.
2. [x] Letras sincronizadas (LRCLIB) en la segunda línea del LCD; caché en ~/.cache/beatbox/lyrics (Preferencias › Apariencia).
3. [x] Mini reproductor: Ctrl+M, Alt+botón verde o menú; deja solo controles y LCD.
4. [x] Cola editable: «Reproducir a continuación» y «Añadir a la cola» en las listas; en la Cola, Subir, Bajar, Vaciar y arrastrar para reordenar; se guarda al cambiar y vuelve al abrir.
5. [x] Biblioteca: vigila la carpeta de música (importa lo nuevo; sigue borrados, renombres y movimientos conservando reproducciones; desmarca los que vuelven). Duplicados y edición por lotes revisados y corregidos. «Guardar la carátula en los archivos» (menú contextual; TagLib ≥ 2.0).
6. [x] Escuchas: Last.fm corregido (valores escapados, POST como formulario, firma verificada contra el servidor, regla 30 s + mitad o 4 min, hora de inicio; sin «Prohibir», que Last.fm quitó). ListenBrainz con token validado (Preferencias › Escuchas).
7. [x] Atajos configurables (Preferencias › Atajos: 11 acciones, aviso al reasignar, restaurar). Las notificaciones llevan la portada (verificado).
8. [x] Ecualizador revisado: bandas en las frecuencias que dicen las etiquetas (32 Hz–16 kHz, una octava), modo automático sin género no toma el primer preajuste, preajustes aplicados en el hilo principal, cierre sin reentrada, nombres traducidos; quitado el código de reconexión muerto.
9. Paquete Flatpak/AppImage.
