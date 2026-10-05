/*
 * Linked toggle buttons with exactly one active: the view switcher.
 * Adapted from Granite's ModeButton (granite 6.2.0, LGPL-3.0-or-later):
 * Copyright 2011-2019 elementary, Inc.; written by Christian Dywan, Tom Beckmann
 * and Victor Martinez. Same widgets and style classes, so it looks the same.
 */

public class BeatBox.ModeButton : Gtk.Box {
	public signal void mode_changed ();

	public int selected {
		get { return _selected; }
		set { set_active (value); }
	}

	int _selected = -1;
	Gee.ArrayList<Gtk.ToggleButton> items = new Gee.ArrayList<Gtk.ToggleButton> ();
	Gtk.EventControllerScroll wheel; // GTK3 controllers need a reference

	public ModeButton () {
		homogeneous = true;
		get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
		get_style_context ().add_class ("raised");

		// the wheel moves to the next or previous sensitive button
		wheel = new Gtk.EventControllerScroll (this, Gtk.EventControllerScrollFlags.BOTH_AXES | Gtk.EventControllerScrollFlags.DISCRETE);
		wheel.scroll.connect ((dx, dy) => {
			int offset = (dy > 0 || dx > 0) ? 1 : -1;
			for (int i = _selected + offset; i >= 0 && i < items.size; i += offset) {
				if (items[i].visible && items[i].sensitive) {
					selected = i;
					break;
				}
			}
		});
	}

	public void append (Gtk.Widget child) {
		int index = items.size;
		var item = new Gtk.ToggleButton ();
		item.add_events (Gdk.EventMask.SCROLL_MASK); // the wheel reaches the buttons, then the box's controller
		item.add (child);
		item.toggled.connect (() => {
			if (item.active)
				selected = index;
			else if (_selected == index)
				item.active = true; // a click on the active button keeps it active
		});
		items.add (item);
		add (item);
		item.show_all ();
	}

	void set_active (int index) {
		if (index < 0 || index >= items.size)
			return;

		items[index].active = true;
		if (_selected == index)
			return;

		// _selected changes first, so the old button knows it's being turned off on purpose
		int old = _selected;
		_selected = index;
		if (old >= 0)
			items[old].active = false;

		mode_changed ();
	}
}
