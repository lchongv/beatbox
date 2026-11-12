/*
 * Context menus for GTK4. They stand in for Gtk.Menu, Gtk.MenuItem and the rest of the
 * GTK3 menu family, which GTK4 dropped (see docs/gtk4/RECETAS.md).
 */

using Gtk;

// A menu: a popover with a vertical list of items
public class BeatBox.PopMenu : Gtk.Popover {
	private Gtk.Box box;

	public PopMenu () {
		has_arrow = false;
		add_css_class ("menu");
		box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		set_child (box);
		// the menu hangs off the widget it was popped up at: let go of it once closed
		closed.connect (() => Idle.add (() => {
			if (!visible && get_parent () != null)
				unparent ();
			return false;
		}));
	}

	public void append (Gtk.Widget item) {
		box.append (item);
	}

	// x, y are in the coordinates of widget
	public void popup_at (Gtk.Widget widget, double x, double y) {
		detach ();
		set_parent (widget);
		pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
		popup ();
	}

	public void popup_under (Gtk.Widget widget) {
		detach ();
		set_parent (widget);
		position = Gtk.PositionType.BOTTOM;
		popup ();
	}

	private void detach () {
		if (visible)
			popdown ();
		if (get_parent () != null)
			unparent ();
	}
}

// An item of a PopMenu (replaces Gtk.MenuItem)
public class BeatBox.PopMenuItem : Gtk.Button {
	// true: the menu stays open when the item is activated
	public bool keep_open { get; set; }

	// Items are activated through "clicked": Vala does not allow an "activate" signal here,
	// Gtk.Button already has one (keyboard activation only).
	public PopMenuItem () {
	}

	construct {
		add_css_class ("flat");
		add_css_class ("menuitem");
		clicked.connect (() => item_clicked ());
	}

	public PopMenuItem.with_label (string label) {
		var text = new Gtk.Label (label);
		text.xalign = 0;
		text.hexpand = true;
		set_child (text);
	}

	public PopMenuItem.with_child (Gtk.Widget child) {
		set_child (child);
	}

	// a click: close the menu unless the item stays open
	protected virtual void item_clicked () {
		if (keep_open)
			return;
		var menu = get_ancestor (typeof (PopMenu)) as PopMenu;
		if (menu != null)
			menu.popdown ();
	}
}

// A checkable item of a PopMenu (replaces CheckMenuItem and RadioMenuItem)
public class BeatBox.PopMenuCheck : BeatBox.PopMenuItem {
	private Gtk.CheckButton check;
	private bool radio;

	public bool active {
		get { return check.active; }
		set { check.active = value; }
	}

	public signal void toggled ();

	public PopMenuCheck.with_label (string label, bool radio = false) {
		this.radio = radio;
		check = new Gtk.CheckButton.with_label (label);
		check.can_target = false; // the clicks go to the item, which is the button
		check.focusable = false;
		set_child (check);
	}

	// a click flips the item (a radio item stays on); the activation comes after
	protected override void item_clicked () {
		if (!(radio && active)) {
			active = !active;
			toggled ();
		}
		base.item_clicked ();
	}
}

// A separator between the items of a PopMenu (replaces SeparatorMenuItem). GTK 4 does not let
// a class derive from Gtk.Separator, so this is a column holding one.
public class BeatBox.PopMenuSeparator : Gtk.Box {
	public PopMenuSeparator () {
		Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
	}
}
