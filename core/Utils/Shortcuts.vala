/*-
 * Keyboard shortcuts the user can change (Preferences › Shortcuts). The
 * window registers what each one does; the chosen keys are kept as
 * "id=accelerator" strings (accelerator "" = none).
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

[GIR (visible = false)] // internal: plugins don't see it
namespace BeatBox.Shortcuts {
	public delegate void ActionFunc ();

	public class Shortcut : GLib.Object {
		public string id { get; construct; }
		public string label { get; construct; }
		public string default_accel { get; construct; }
		public string accel { get; set; }
		internal ActionFunc action;

		public Shortcut (string id, string label, string default_accel) {
			Object (id: id, label: label, default_accel: default_accel, accel: default_accel);
		}

		/** Does the key event (keyval, modifiers) press this shortcut? */
		public bool matches (uint keyval, Gdk.ModifierType state) {
			if (accel == "")
				return false;
			uint key;
			Gdk.ModifierType mods;
			Gtk.accelerator_parse (accel, out key, out mods);
			var mask = Gtk.accelerator_get_default_mod_mask ();
			return key != 0 && Gdk.keyval_to_lower (keyval) == Gdk.keyval_to_lower (key) && (state & mask) == (mods & mask);
		}
	}

	Gee.ArrayList<Shortcut> shortcuts;

	public Gee.List<Shortcut> all () {
		if (shortcuts == null)
			shortcuts = new Gee.ArrayList<Shortcut> ();
		return shortcuts;
	}

	/** saved: the "id=accel" strings from the settings; changed: called with them on every change */
	public delegate void SaveFunc (string[] saved);
	SaveFunc? save_func;
	string[] saved_accels;

	public void init (string[] saved, owned SaveFunc save) {
		saved_accels = saved;
		save_func = (owned) save;
		foreach (var s in all ())
			apply_saved (s);
	}

	void apply_saved (Shortcut s) {
		if (saved_accels == null)
			return;
		foreach (var entry in saved_accels) {
			int eq = entry.index_of_char ('=');
			if (eq > 0 && entry.substring (0, eq) == s.id)
				s.accel = entry.substring (eq + 1);
		}
	}

	public Shortcut register (string id, string label, string default_accel, owned ActionFunc action) {
		var s = new Shortcut (id, label, default_accel);
		s.action = (owned) action;
		apply_saved (s);
		all ().add (s);
		return s;
	}

	/** Gives s a new key (or none, ""), taking it away from any other shortcut; returns that one, if any */
	public Shortcut? set_accel (Shortcut s, string accel) {
		Shortcut? taken_from = null;
		if (accel != "") {
			uint key;
			Gdk.ModifierType mods;
			Gtk.accelerator_parse (accel, out key, out mods);
			foreach (var other in all ()) {
				if (other != s && other.matches (key, mods)) {
					other.accel = "";
					taken_from = other;
				}
			}
		}
		s.accel = accel;
		save ();
		return taken_from;
	}

	public void restore_defaults () {
		foreach (var s in all ())
			s.accel = s.default_accel;
		save ();
	}

	void save () {
		string[] list = {};
		foreach (var s in all ())
			list += s.id + "=" + s.accel;
		saved_accels = list;
		if (save_func != null)
			save_func (list);
	}

	/** Runs the shortcut the key event presses, if any */
	public bool activate (uint keyval, Gdk.ModifierType state) {
		foreach (var s in all ()) {
			if (s.matches (keyval, state)) {
				s.action ();
				return true;
			}
		}
		return false;
	}
}
