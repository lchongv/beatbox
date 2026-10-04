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
