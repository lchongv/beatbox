# Recetas del port a GTK4

Lectura obligatoria para todo agente que toque código en la rama `gtk4`.
El plan y las tareas están en `docs/superpowers/plans/2026-11-12-gtk4-port.md`.

## Reglas del trabajador

1. Edita **solo** los archivos que tu tarea te asigna. Si el arreglo correcto está en
   un archivo ajeno, no lo toques: anótalo en tu informe.
2. No uses `git commit`, `checkout`, `stash`, `reset` ni `restore`. Hay otros agentes
   trabajando en el mismo árbol; los commits los hace el orquestador.
3. **Prohibido** hacer compilar borrando o comentando funcionalidad. Si algo no sabes
   portarlo, déjalo lo más cerca posible de correcto y marca la línea con
   `// GTK4-PENDIENTE: <qué falta y por qué>`. Un pendiente honesto vale más que un
   arreglo falso.
4. Solo API disponible en **GTK 4.6**. No uses `Gtk.FileDialog`, `Gtk.AlertDialog`,
   `Gtk.ColumnView` nuevo, `Gdk.FileList.from_array`, `Picture.content_fit`,
   `load_from_string` ni libadwaita. `TreeView`, `IconView`, `CellRenderer*`, `ListStore`,
   `ComboBoxText`, `Dialog`, `MessageDialog`, `FileChooserDialog`, `InfoBar` y
   `StyleContext` **se quedan** (GTK4 los tiene; los avisos de obsolescencia se ignoran).
5. `Gdk.Pixbuf` se queda como tipo de imagen en todo el programa. No lo cambies por
   `Gdk.Texture` salvo donde una API exija un `Gdk.Paintable` (`Gdk.Texture.for_pixbuf (pb)`).
6. No cambies textos visibles, nombres de clases CSS ni nombres de opciones. No añadas
   dependencias. Comentarios y mensajes de commit en inglés, como el resto del código.
7. Estilo: el del archivo (tabs o espacios como estén). Cambios mínimos: no reordenes,
   no renombres, no «mejores» nada que no pida el port.
8. `src/Store/` es código muerto (no se compila): no lo toques.

## Cómo comprobar

    tools/gtk4-check.sh                 # resumen de errores por archivo
    tools/gtk4-check.sh src/Dialogs     # errores de tus archivos, con contexto

Tarda ~2 s y se puede correr mientras otros trabajan. Tu tarea termina cuando dice
`EN LO PEDIDO: 0 errores`.

### Las dos etapas del compilador

valac primero resuelve tipos (etapa 1) y solo si no falla ninguno revisa el resto
(etapa 2). Por eso existe `core/Gtk3Shim.vala`, el **andamio**: declara vacíos los tipos
que GTK4 quitó (`Gtk.Menu`, `Gtk.EventBox`, `Gdk.EventButton`…) para que todos vean sus
errores de etapa 2 a la vez.
- Nunca dejes un error de etapa 1 (tipo desconocido o error de sintaxis): tapa los
  errores de todos los demás. Si el script dice «Etapa 1», arréglalo antes que nada.
- No añadas nada al andamio. Cuando tus archivos dejen de usar un tipo del andamio,
  no lo borres tú: lo hace la tarea de cierre.
- Arreglar un error suele destapar otros (el cuerpo de una lambda no se revisa hasta
  que su señal existe). Repite hasta 0.

## Utilidades propias (las crea la tarea T01; úsalas)

En `core/Utils/UI.vala`, espacio `BeatBox.UI`:

```vala
public async int run_dialog (Gtk.Dialog dialog);          // sustituye a dialog.run ()
public GLib.List<unowned Gtk.Widget> children (Gtk.Widget parent); // sustituye a get_children ()
public void clear (Gtk.Widget parent);                    // quita todos los hijos
public void show_pixbuf (Gtk.Image image, Gdk.Pixbuf? pixbuf);     // set_from_pixbuf + tamaño real
public Gtk.Window? window_of (Gtk.Widget widget);         // sustituye a get_toplevel ()
```

En `core/Widgets/PopMenu.vala` (menús contextuales; sustituyen a `Gtk.Menu` y familia):

```vala
public class BeatBox.PopMenu : Gtk.Popover {
    public PopMenu ();
    public void append (Gtk.Widget item);
    public void popup_at (Gtk.Widget widget, double x, double y); // x, y en coordenadas de widget
    public void popup_under (Gtk.Widget widget);                  // sustituye a popup_at_widget
}
public class BeatBox.PopMenuItem : Gtk.Button {       // sustituye a Gtk.MenuItem
    public PopMenuItem.with_label (string label);
    public PopMenuItem.with_child (Gtk.Widget child); // sustituye a MenuItem () + add (w)
    public bool keep_open { get; set; }               // true: el menú no se cierra al clicar
}
// Un ítem se conecta por «clicked», nunca por «activate»: Vala no deja declarar
// «activate» aquí (ya lo tiene Gtk.Button, que solo lo emite con el teclado).
public class BeatBox.PopMenuCheck : BeatBox.PopMenuItem {  // CheckMenuItem y RadioMenuItem
    public PopMenuCheck.with_label (string label, bool radio = false);
    public bool active { get; set; }
    public signal void toggled ();
}
public class BeatBox.PopMenuSeparator : Gtk.Separator { }  // SeparatorMenuItem
```

Portar un menú es casi solo renombrar: `new Gtk.Menu ()` → `new PopMenu ()`,
`new Gtk.MenuItem.with_label (x)` → `new PopMenuItem.with_label (x)`,
`menu.popup_at_pointer (event)` → `menu.popup_at (this, x, y)` con las coordenadas del
gesto. Los grupos de radio (`get_group`, `join_group`) desaparecen: quien crea los ítems
desmarca los demás en `toggled`. `menu.show_all ()` se borra. `attach_to_widget` se borra.

## Tabla de cambios

### Contenedores

| GTK3 | GTK4 |
|---|---|
| `box.add (w)`, `box.pack_start (w…)` | `box.append (w)` |
| `window/scrolled/button/frame/viewport/popover/revealer/overlay.add (w)` | `.set_child (w)` |
| `listbox.add`, `flowbox.add` | `.append (w)` |
| `stack.add (w)` | `stack.add_child (w)` (`add_named`, `add_titled` siguen) |
| `infobar.get_content_area ().add (w)` | `infobar.add_child (w)` |
| `dialog.get_content_area ().add (w)` | `dialog.get_content_area ().append (w)` |
| `paned.pack1 (w, resize, shrink)` | `paned.start_child = w; paned.resize_start_child = resize; paned.shrink_start_child = shrink;` (`pack2` → `end_child`…) |
| `x.remove (w)` en un contenedor de un hijo | `x.set_child (null)` (`Box.remove` sigue) |
| `x.get_children ()` | `UI.children (x)` |
| `foreach (var c in x.get_children ()) x.remove (c)` | `UI.clear (x)` |
| `box.reorder_child (w, 0)` | `box.reorder_child_after (w, null)` (después de `sibling`) |
| `box.set_center_widget (w)` | usar `Gtk.CenterBox` |
| `border_width = n`, `margin = n` | `margin_top = margin_bottom = margin_start = margin_end = n` en el hijo |
| `new ScrolledWindow (null, null)` | `new ScrolledWindow ()` |
| `scrolled.set_shadow_type (…)`, `viewport.set_shadow_type` | `scrolled.has_frame = true/false`; en Viewport, borrar |
| `Gtk.ButtonBox`, `set_layout` | `new Gtk.Box (HORIZONTAL, 6)` con `halign = Gtk.Align.END` |
| `Gtk.Toolbar` | `Gtk.Box` horizontal con `add_css_class ("toolbar")` |
| `Gtk.ToolItem` envolviendo `w` | `w` directamente |
| `Gtk.ToolButton`, `ToggleToolButton` | `Gtk.Button.from_icon_name (…)`, `Gtk.ToggleButton` |
| `Gtk.EventBox` envolviendo `w` | `w` directamente; los controladores van en `w` |
| clase que hereda de `EventBox` | hereda de `Gtk.Box` y `append (hijo)` |
| `Gtk.Bin`, `Gtk.Container` como tipo | `Gtk.Widget` |

### Visibilidad y vida de los widgets (trampas que el compilador NO ve)

- En GTK4 todo widget es **visible al crearse**. `show_all ()` se borra (en una ventana:
  `present ()`). `set_no_show_all (true)` / `no_show_all = true` se borra **y** si el
  widget debía empezar oculto, pon `visible = false` al crearlo.
- `widget.destroy ()`: solo existe en ventanas y diálogos. En otro widget: quítalo de su
  padre (`box.remove (w)` o `set_child (null)`).
- `can_focus = false` ahora también deja sin foco a los hijos; el equivalente antiguo
  es `focusable = false`.
- `can_default`/`grab_default ()` → `ventana.set_default_widget (boton)`.

### Imágenes e íconos

| GTK3 | GTK4 |
|---|---|
| `new Image.from_icon_name (n, IconSize.X)` | `new Image.from_icon_name (n)`; tamaño aparte (abajo) |
| `image.set_from_icon_name (n, size)` | `image.set_from_icon_name (n)` |
| `IconSize.MENU`, `BUTTON`, `SMALL_TOOLBAR` (16 px) | nada (es el tamaño por defecto) |
| `IconSize.LARGE_TOOLBAR` (24), `DND` (32), `DIALOG` (48) | `image.pixel_size = 24` / `32` / `48` |
| `new Button.from_icon_name (n, size)` | `new Button.from_icon_name (n)` |
| `new Image.from_pixbuf (pb)`, `image.set_from_pixbuf (pb)` | `var image = new Gtk.Image (); UI.show_pixbuf (image, pb);` |
| `image.pixbuf` (leer) | no existe: guarda el pixbuf en un campo |
| `button.set_image (img)`, `button.image = img` | `button.child = img` (con texto: un `Box` con imagen y `Label`) |
| `button.always_show_image`, `button.relief = NONE` | borrar; `button.has_frame = false` |
| `IconTheme.get_default ()` | `Gtk.IconTheme.get_for_display (Gdk.Display.get_default ())` |
| `cell_pixbuf.stock_size = …` | `cell_pixbuf.icon_size = Gtk.IconSize.NORMAL` (o `LARGE`) |

**Trampa:** `Gtk.Image` en GTK4 dibuja cualquier imagen al tamaño de ícono (16 px) salvo
que se fije `pixel_size`. Por eso las carátulas y demás pixbufs van siempre con
`UI.show_pixbuf`, nunca con `set_from_pixbuf` a secas.

### Texto, botones, entradas

| GTK3 | GTK4 |
|---|---|
| `label.set_line_wrap (true)`, `line_wrap = true` | `label.wrap = true` |
| `label.xalign = 0.0` (error «float/double») | `label.xalign = 0.0f` |
| `label.set_alignment (x, y)` | `label.xalign = xf; label.yalign = yf;` |
| `Gtk.STYLE_CLASS_BUTTON` y demás constantes | la cadena: `"button"`, `"flat"`, `"linked"`, `"sidebar"`, `"view"`, `"dim-label"`, `"menuitem"`, `"suggested-action"`, `"destructive-action"` |
| `w.get_style_context ().add_class ("x")` | `w.add_css_class ("x")` (`remove_css_class`, `has_css_class`) |
| `context.get_color (state)` | `w.get_style_context ().get_color ()` (sin argumento; devuelve `Gdk.RGBA`) |
| `context.get_background_color (…)` | `w.get_style_context ().render_background (cr, x, y, ancho, alto)` |
| `context.lookup_color (nombre, out c)` | igual |
| `obj.set_data ("k", v)` (error «cannot infer generic type») | `obj.set_data<Tipo> ("k", v)` |
| `new VScale (adj)` | `new Scale (Orientation.VERTICAL, adj)` |
| `FileChooserButton` | un `Button` con el nombre de la carpeta que abre un `FileChooserDialog` (SELECT_FOLDER) |

### CSS

| GTK3 | GTK4 |
|---|---|
| `StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), p, prio)` | `Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), p, prio)` |
| `provider.load_from_data (css)` o `(css, -1)` | `provider.load_from_data (css.data)` |
| `load_from_resource`, `load_from_file`, `load_from_path` | igual, pero ya no lanzan error: quita el `try` si queda vacío |

### Ventanas y diálogos

| GTK3 | GTK4 |
|---|---|
| `new Gtk.Window (WindowType.TOPLEVEL)` | `new Gtk.Window ()` |
| `window_position`, `type_hint`, `set_keep_above`, `skip_taskbar_hint`, `move (x, y)`, `get_position`, `set_icon*`, `has_resize_grip` | borrar (GTK4 no deja colocar ventanas) |
| `resize (w, h)` | `set_default_size (w, h)` |
| `get_size (out w, out h)` | `w = default_width; h = default_height;` (siguen el tamaño real) |
| `delete_event.connect ((e) => { …; return true; })` | `close_request.connect (() => { …; return true; })` |
| `window_state_event` | `notify["maximized"].connect (…)`, `notify["fullscreened"]`, y `is_maximized ()` |
| `iconify ()` | `minimize ()` |
| `hide_on_delete ()` | `hide_on_close = true` |
| `w.get_toplevel () as Gtk.Window` | `UI.window_of (w)` |
| `begin_move_drag (…)` (arrastrar la ventana desde una zona) | envolver esa zona en `Gtk.WindowHandle` (`handle.set_child (zona)`) |
| `Gtk.show_uri_on_window (win, uri, t)` | `Gtk.show_uri (win, uri, Gdk.CURRENT_TIME)` |
| `Gdk.Screen.get_default ().get_height ()` | geometría del monitor: `display.get_monitor_at_surface (win.get_surface ()).get_geometry ()` |
| `dialog.run ()` | `yield UI.run_dialog (dialog)` (ver abajo) |
| `chooser.get_filename ()` | `chooser.get_file ().get_path ()` |
| `chooser.get_uri ()` | `chooser.get_file ().get_uri ()` |
| `chooser.set_current_folder (ruta)` | `try { chooser.set_current_folder (File.new_for_path (ruta)); } catch (Error e) { }` |
| `chooser.get_current_folder ()` | `chooser.get_current_folder ().get_path ()` |
| `chooser.set_local_only (…)` | borrar |

**`dialog.run ()`** no existe. Receta:

```vala
// antes
void elegir () {
    var d = new Gtk.FileChooserDialog (…);
    if (d.run () == Gtk.ResponseType.ACCEPT) usar (d.get_filename ());
    d.destroy ();
}
// después
async void elegir () {
    var d = new Gtk.FileChooserDialog (…);
    if ((yield UI.run_dialog (d)) == Gtk.ResponseType.ACCEPT) usar (d.get_file ().get_path ());
    d.destroy ();
}
```

El método pasa a ser `async`; quien lo llama pasa de `elegir ()` a `elegir.begin ()`.
Si lo conectaba una señal: `boton.clicked.connect (() => elegir.begin ());`. Si el método
devolvía un valor que el llamador usa, el llamador también se vuelve `async` y hace
`yield`. Un `while (d.run () == …)` se convierte en `while ((yield UI.run_dialog (d)) == …)`.

### Eventos

Las señales `*_event` no existen. Los controladores se crean **sin** widget y se añaden
con `add_controller` (el widget se queda con ellos: el campo que guardaba la referencia
ya no hace falta, pero puede quedarse).

| GTK3 | GTK4 |
|---|---|
| `new Gtk.GestureMultiPress (w)` | `var g = new Gtk.GestureClick (); w.add_controller (g);` |
| `new Gtk.GestureDrag (w)`, `EventControllerKey (w)`, `EventControllerMotion (w)` | igual: sin argumento + `w.add_controller (c)` |
| `new EventControllerScroll (w, flags)` | `new Gtk.EventControllerScroll (flags)` + `add_controller` |
| `button_press_event.connect ((e) => …)` | `GestureClick`: `g.pressed.connect ((n_press, x, y) => …)` |
| `button_release_event` | `g.released.connect ((n_press, x, y) => …)` |
| `e.button == 3` | `g.button = 0;` al crear (0 = cualquier botón) y `g.get_current_button () == Gdk.BUTTON_SECONDARY` |
| `e.type == Gdk.EventType.2BUTTON_PRESS` | `n_press == 2` |
| `e.state & Gdk.ModifierType.CONTROL_MASK` | `g.get_current_event_state () & Gdk.ModifierType.CONTROL_MASK` |
| `Gdk.ModifierType.MOD1_MASK` | `Gdk.ModifierType.ALT_MASK` |
| `return true` (tragarse el clic) | `g.set_state (Gtk.EventSequenceState.CLAIMED)` |
| el clic debe llegar **antes** que al propio widget (listas) | `g.propagation_phase = Gtk.PropagationPhase.CAPTURE` |
| `key_press_event` | `EventControllerKey`: `key_pressed.connect ((keyval, keycode, state) => bool)` |
| `scroll_event` | `EventControllerScroll`: `scroll.connect ((dx, dy) => bool)` |
| `motion_notify_event`, `enter/leave_notify_event` | `EventControllerMotion`: `motion (x, y)`, `enter (x, y)`, `leave ()` |
| `focus_in_event`, `focus_out_event` | `Gtk.EventControllerFocus`: `enter ()`, `leave ()` |
| `add_events (…)`, `set_events` | borrar |
| `Gtk.get_current_event ()`, `get_current_event_time ()` | `controlador.get_current_event ()`; el tiempo: `Gdk.CURRENT_TIME` |
| `get_window ().set_cursor (new Gdk.Cursor…HAND2)` / `(null)` | `set_cursor_from_name ("pointer")` / `set_cursor_from_name (null)` |
| `treeview.get_path_at_pos ((int) e.x, (int) e.y, …)` con x, y de un gesto | antes: `int bx, by; convert_widget_to_bin_window_coords ((int) x, (int) y, out bx, out by);` y usar `bx, by` |

### Dibujo a mano

| GTK3 | GTK4 |
|---|---|
| `area.draw.connect ((cr) => { …; return false; })` en un `DrawingArea` | `area.set_draw_func ((a, cr, ancho, alto) => { … });` |
| `override bool draw (Cairo.Context cr)` en una clase que hereda de `DrawingArea` | método normal `void on_draw (Gtk.DrawingArea a, Cairo.Context cr, int w, int h)` y `set_draw_func (on_draw)` en el constructor |
| `override bool draw` en otro widget (con hijos) | `override void snapshot (Gtk.Snapshot s)` (abajo) |
| `get_allocated_width ()` / `height` | `get_width ()` / `get_height ()` |
| `size_allocate.connect (…)` en `DrawingArea` | `resize.connect ((ancho, alto) => …)` |
| `override void size_allocate (Allocation a)` | `override void size_allocate (int width, int height, int baseline)` + `base.size_allocate (…)` |
| `override void get_preferred_width (out min, out nat)` (y `height`) | `override void measure (Gtk.Orientation o, int for_size, out int min, out int nat, out int min_base, out int nat_base)` con `min_base = nat_base = -1`; si era un mínimo fijo basta `set_size_request` |
| `app_paintable`, `set_visual`, `double_buffered`, `get_bin_window`, `Gtk.cairo_should_draw_window`, `Gtk.cairo_transform_to_window` | borrar |
| `Gdk.cairo_set_source_pixbuf`, `Gdk.cairo_set_source_rgba`, Pango | igual |

```vala
public override void snapshot (Gtk.Snapshot s) {
    var r = Graphene.Rect ();
    r.init (0, 0, get_width (), get_height ());
    var cr = s.append_cairo (r);
    // … el dibujo de antes …
    base.snapshot (s);   // dibuja los hijos
}
```

`CellRenderer` propio: `override void render (Cairo.Context cr, Widget w, Rectangle bg,
Rectangle cell, CellRendererState f)` → `override void snapshot (Gtk.Snapshot s, Gtk.Widget w,
Gdk.Rectangle bg, Gdk.Rectangle cell, Gtk.CellRendererState f)` y dentro
`var r = Graphene.Rect (); r.init (cell.x, cell.y, cell.width, cell.height); var cr = s.append_cairo (r);`.
`get_size` → `get_preferred_width (Widget w, out int min, out int nat)` y `get_preferred_height`.

### Arrastrar y soltar

El contenido arrastrado dentro del programa es **un string con las URI separadas por
`\n`** (sustituye a `SelectionData.set_uris/get_uris`). Los archivos soltados desde fuera
llegan como `Gdk.FileList`.

```vala
// origen (sustituye a drag_source_set + drag_begin/drag_data_get/drag_end)
var source = new Gtk.DragSource ();
source.actions = Gdk.DragAction.COPY;
source.prepare.connect ((x, y) => {
    string uris = …;                       // "uri1\nuri2"
    return new Gdk.ContentProvider.for_value (uris);
});
source.drag_begin.connect ((drag) => { … });        // lo de on_drag_begin
source.drag_end.connect ((drag, borrar) => { … });  // lo de on_drag_end
widget.add_controller (source);
// ícono: source.set_icon (Gtk.IconTheme.get_for_display (get_display ())
//     .lookup_icon ("audio-x-generic", null, 32, 1, Gtk.TextDirection.NONE, 0), 0, 0);

// destino (sustituye a drag_dest_set + drag_data_received/drag_motion/drag_drop)
var dest = new Gtk.DropTarget (GLib.Type.INVALID, Gdk.DragAction.COPY);
dest.set_gtypes ({ typeof (string), typeof (Gdk.FileList) });
dest.on_drop.connect ((value, x, y) => {
    string[] uris = {};
    if (value.holds (typeof (Gdk.FileList)))
        foreach (unowned File f in ((Gdk.FileList) value.get_boxed ()).get_files ()) uris += f.get_uri ();
    else
        uris = value.get_string ().split ("\n");
    …
    return true;
});
dest.motion.connect ((x, y) => { …; return Gdk.DragAction.COPY; });  // lo de drag_motion
widget.add_controller (dest);
```

`Gdk.DragContext`, `Gtk.SelectionData`, `Gtk.TargetEntry`, `Gtk.drag_*`, `Gdk.drag_abort`
desaparecen. En `core`, `View.drag_received (Gtk.SelectionData data)` pasa a ser
`drag_received (string[] uris)` (lo cambia T02).

### Varios

| GTK3 | GTK4 |
|---|---|
| `Gtk.Popover.from_model (widget, modelo)` (o `new Popover.from_model`) | `var p = new Gtk.PopoverMenu.from_model (modelo); p.set_parent (widget);` |
| `Gtk.main_iteration ()`, `events_pending ()` | `MainContext.default ().iteration (false)`, `MainContext.default ().pending ()` |
| `Gtk.init (ref args)` | `Gtk.init ()` |
| `widget.get_window ()` | casi siempre sobra; si hace falta: `widget.get_native ().get_surface ()` |
| `Gtk.Widget.get_pointer`, `Gdk.Seat` para la posición del puntero | usa las coordenadas del último `EventControllerMotion` |

Si algo no está en esta tabla: busca el miembro en `/usr/share/vala-0.56/vapi/gtk4.vapi`
(`grep -n "nombre" …`) antes de inventar; si no hay equivalente, `// GTK4-PENDIENTE`.
