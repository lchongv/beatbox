// ANDAMIO DEL PORT A GTK4. Tipos de GTK3 que GTK4 ya no tiene, declarados vacíos
// para que valac pase la etapa 1 (tipos) y muestre los errores de la etapa 2 en
// todos los archivos a la vez. Nada de esto funciona: cada uso da error de
// compilación hasta que se porta. Cada tarea borra de aquí los tipos que deja
// de usar; la tarea final borra el archivo. No añadir miembros.
namespace Gtk {
	public class EventBox : Gtk.Widget { }
	public class Container : Gtk.Widget { }
	public class Bin : Gtk.Widget { }
	public class Layout : Gtk.Widget { }
	public class Menu : Gtk.Widget { }
	public class MenuItem : Gtk.Widget { }
	public class CheckMenuItem : Gtk.MenuItem { }
	public class RadioMenuItem : Gtk.MenuItem { }
	public class SeparatorMenuItem : Gtk.MenuItem { }
	public class ButtonBox : Gtk.Widget { }
	public class Toolbar : Gtk.Widget { }
	public class ToolItem : Gtk.Widget { }
	public class ToolButton : Gtk.ToolItem { }
	public class ToggleToolButton : Gtk.ToolItem { }
	public class SeparatorToolItem : Gtk.ToolItem { }
	public class FileChooserButton : Gtk.Widget { }
	public class SelectionData : GLib.Object { }
	public class IconInfo : GLib.Object { }
	public class TargetEntry : GLib.Object { }
}
namespace Gdk {
	public class DragContext : GLib.Object { }
	public class Screen : GLib.Object { }
	public class Window : GLib.Object { }
	public class EventButton : GLib.Object { }
	public class EventScroll : GLib.Object { }
	public class EventKey : GLib.Object { }
	public class EventMotion : GLib.Object { }
	public class EventCrossing : GLib.Object { }
	public class EventWindowState : GLib.Object { }
}
