/*-
 * Preferences › Shortcuts: the keyboard shortcuts, changed by clicking one
 * and pressing the new keys (Backspace removes it).
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

using Gtk;

public class BeatBox.ShortcutsPreferences : SimplePreferences {
	public override string title { get { return _("Shortcuts"); } }

	SimpleTable table; // the action's name; the row's data is its Shortcuts.Shortcut
	Label notice;

	public ShortcutsPreferences () {
		add_heading (_("Keyboard Shortcuts"));
		var hint = new Label (_("Click a shortcut and press the new keys; Backspace leaves the action without one."));
		hint.xalign = 0.0f;
		hint.wrap = true;
		hint.max_width_chars = 60;
		hint.add_css_class("dim-label");
		add_row (hint);

		table = new SimpleTable ();
		table.headers_visible = false;
		table.add_column (null, 0);
		// the keys: a click, then the new keys (Escape leaves them, Backspace removes them)
		table.add_custom_column (null, (item) => {
			UI.add_css (".bb-accel { padding: 0 6px; min-height: 0; }"); // as tall as the text, like the old cells
			var button = new Button ();
			button.has_frame = false;
			button.add_css_class ("bb-accel");
			button.halign = Align.END;
			item.child = button;
			var keys = new EventControllerKey ();
			keys.key_pressed.connect ((keyval, code, state) => {
				if (!button.has_css_class ("listening"))
					return false;
				var row = item.item as TableRow;
				if (row == null)
					return false;
				switch (keyval) {
				case Gdk.Key.Shift_L: case Gdk.Key.Shift_R: case Gdk.Key.Control_L: case Gdk.Key.Control_R:
				case Gdk.Key.Alt_L: case Gdk.Key.Alt_R: case Gdk.Key.Super_L: case Gdk.Key.Super_R:
				case Gdk.Key.Meta_L: case Gdk.Key.Meta_R: case Gdk.Key.ISO_Level3_Shift:
					return true; // a modifier alone: wait for the key
				case Gdk.Key.Escape:
					stop_listening (button, (Shortcuts.Shortcut) row.data);
					return true;
				case Gdk.Key.BackSpace:
					change ((Shortcuts.Shortcut) row.data, "");
					return true;
				}
				change ((Shortcuts.Shortcut) row.data, Gtk.accelerator_name (Gdk.keyval_to_lower (keyval), state & Gtk.accelerator_get_default_mod_mask ()));
				return true;
			});
			button.add_controller (keys);
			button.clicked.connect (() => {
				button.add_css_class ("listening");
				button.label = _("New shortcut…");
				button.grab_focus ();
			});
			var focus = new EventControllerFocus ();
			focus.leave.connect (() => {
				var row = item.item as TableRow;
				if (row != null)
					stop_listening (button, (Shortcuts.Shortcut) row.data);
			});
			button.add_controller (focus);
		}, (item, row) => {
			stop_listening ((Button) item.child, (Shortcuts.Shortcut) row.data);
		}, false);

		var frame = new Frame (null);
		frame.set_child (table.view);
		add_row (frame);

		notice = new Label ("");
		notice.xalign = 0.0f;
		notice.wrap = true;
		notice.max_width_chars = 60;
		add_row (notice);

		var restore = new Button.with_label (_("Restore the Defaults"));
		restore.clicked.connect (() => {
			Shortcuts.restore_defaults ();
			notice.label = "";
			fill ();
		});
		add_row (restore);
		restore.halign = Align.START; // after add_row, which makes rows fill
		fill ();
	}

	void fill () {
		table.clear ();
		foreach (var s in Shortcuts.all ())
			table.add ({ s.label }, s);
	}

	/** The button shows the shortcut's keys again */
	static void stop_listening (Button button, Shortcuts.Shortcut s) {
		button.remove_css_class ("listening");
		uint key = 0;
		Gdk.ModifierType mods = 0;
		if (s.accel != "")
			Gtk.accelerator_parse (s.accel, out key, out mods);
		button.label = (key != 0) ? Gtk.accelerator_get_label (key, mods) : _("Disabled");
	}

	void change (Shortcuts.Shortcut s, string accelerator) {
		var taken_from = Shortcuts.set_accel (s, accelerator);
		notice.label = (taken_from != null)
			? _("“%s” used those keys; it has no shortcut now.").printf (taken_from.label)
			: "";
		fill ();
	}
}
