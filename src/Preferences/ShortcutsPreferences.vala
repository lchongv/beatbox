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

	enum Column { LABEL, KEY, MODS, SHORTCUT }

	Gtk.ListStore store;
	Label notice;

	public ShortcutsPreferences () {
		add_heading (_("Keyboard Shortcuts"));
		var hint = new Label (_("Click a shortcut and press the new keys; Backspace leaves the action without one."));
		hint.xalign = 0.0f;
		hint.wrap = true;
		hint.max_width_chars = 60;
		hint.get_style_context ().add_class ("dim-label");
		add_row (hint);

		store = new Gtk.ListStore (4, typeof (string), typeof (uint), typeof (Gdk.ModifierType), typeof (Shortcuts.Shortcut));
		var view = new TreeView.with_model (store);
		view.headers_visible = false;
		view.insert_column_with_attributes (-1, null, new CellRendererText (), "text", Column.LABEL);
		var accel = new CellRendererAccel ();
		accel.editable = true;
		accel.accel_mode = CellRendererAccelMode.OTHER; // Space alone is a shortcut too
		view.insert_column_with_attributes (-1, null, accel, "accel-key", Column.KEY, "accel-mods", Column.MODS);
		accel.accel_edited.connect ((path, key, mods, code) => {
			change (path, Gtk.accelerator_name (key, mods));
		});
		accel.accel_cleared.connect ((path) => { change (path, ""); });

		var frame = new Frame (null);
		frame.add (view);
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
		store.clear ();
		foreach (var s in Shortcuts.all ()) {
			uint key = 0;
			Gdk.ModifierType mods = 0;
			if (s.accel != "")
				Gtk.accelerator_parse (s.accel, out key, out mods);
			TreeIter iter;
			store.append (out iter);
			store.set (iter, Column.LABEL, s.label, Column.KEY, key, Column.MODS, mods, Column.SHORTCUT, s);
		}
	}

	void change (string path, string accelerator) {
		TreeIter iter;
		if (!store.get_iter_from_string (out iter, path))
			return;
		Shortcuts.Shortcut s;
		store.get (iter, Column.SHORTCUT, out s);
		var taken_from = Shortcuts.set_accel (s, accelerator);
		notice.label = (taken_from != null)
			? _("“%s” used those keys; it has no shortcut now.").printf (taken_from.label)
			: "";
		fill ();
	}
}
