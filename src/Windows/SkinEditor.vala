using Gtk;

/** Edits the CSS of a skin, shown live as it is typed (Preferences › Appearance › Edit CSS).
 * A bundled skin can't be changed: saving one makes an edited copy in the skins folder. */
public class BeatBox.SkinEditor : Gtk.Window {
	/** A skin was saved, maybe as a new one (its id) */
	public signal void saved (string id);

	Skins.Skin skin;
	TextView view;
	Label status;
	Button save_button;
	string saved_text;
	uint pending = 0;
	bool closing = false;

	public SkinEditor (Window parent, Skins.Skin skin) {
		this.skin = skin;
		transient_for = parent;
		modal = true; // Preferences is modal: input goes to the newest modal window only
		destroy_with_parent = true;
		set_default_size (640, 560);
		title = _("Edit Skin: %s").printf (skin.name);

		try {
			uint8[] data;
			skin.css.load_contents (null, out data, null);
			saved_text = (string)data;
		} catch (Error err) {
			saved_text = "";
			warning ("Could not read %s: %s", skin.css.get_uri (), err.message);
		}

		view = new TextView ();
		view.monospace = true;
		view.left_margin = view.right_margin = view.top_margin = view.bottom_margin = 6;
		view.buffer.text = saved_text;
		var scroll = new ScrolledWindow ();
		scroll.hexpand = scroll.vexpand = true;
		scroll.set_child (view);

		status = new Label ("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.END;
		status.selectable = true;

		var revert = new Button.with_label (_("Revert"));
		revert.tooltip_text = _("Back to the last saved version");
		revert.clicked.connect (() => { view.buffer.text = saved_text; });
		save_button = new Button.with_label (Skins.is_user (skin) ? _("Save") : _("Save as Copy"));
		save_button.tooltip_text = Skins.is_user (skin) ? null : _("A bundled skin can't be changed: the copy goes to the skins folder");
		save_button.add_css_class ("suggested-action");
		save_button.clicked.connect (() => { save (); });

		var bottom = new Box (Orientation.HORIZONTAL, 6);
		bottom.margin_top = bottom.margin_bottom = bottom.margin_start = bottom.margin_end = 6;
		status.hexpand = true;
		bottom.append (status);
		bottom.append (revert);   // in GTK3 these were packed from the end: the save button stays rightmost
		bottom.append (save_button);
		var box = new Box (Orientation.VERTICAL, 0);
		var aqua = AquaScroll.wrap (scroll);
		aqua.vexpand = true;
		box.append (aqua);
		box.append (new Separator (Orientation.HORIZONTAL));
		box.append (bottom);
		set_child (box);

		// shown a moment after typing stops, not at every key
		view.buffer.changed.connect (() => {
			if (pending != 0)
				Source.remove (pending);
			pending = Timeout.add (300, () => { pending = 0; show_css (); return false; });
		});
		close_request.connect (() => {
			if (closing)
				return false;
			confirm_close.begin ();
			return true; // the window closes once the question below is answered
		});
		show_css ();
	}

	string text () {
		return view.buffer.text;
	}

	void show_css () {
		var error = Skins.preview_css (skin, text ());
		status.label = error ?? (text () == saved_text ? "" : _("Not saved"));
		save_button.sensitive = text () != saved_text || !Skins.is_user (skin);
	}

	bool save () {
		try {
			var id = Skins.save_css (skin, text ());
			saved_text = text ();
			if (id != skin.id) { // a copy: from now on that one is edited
				foreach (var s in Skins.available ())
					if (s.id == id)
						skin = s;
				title = _("Edit Skin: %s").printf (skin.name);
				save_button.label = _("Save");
				save_button.tooltip_text = null;
				App.settings.main.skin = id;
			}
			saved (id);
			show_css ();
			return true;
		} catch (Error err) {
			status.label = _("Could not save: %s").printf (err.message);
			return false;
		}
	}

	/** Unsaved changes: save them, drop them or stay. Closes the window when that is done. */
	async void confirm_close () {
		if (text () != saved_text) {
			// 0 close without saving, 1 cancel, 2 save
			var answer = yield UI.choose (this, _("Save the changes to the skin?"), null,
				{ _("Close Without Saving"), _("Cancel"), _("Save") }, 1, 2);
			if (!(answer == 0 || (answer == 2 && save ())))
				return;
		}
		if (pending != 0)
			Source.remove (pending);
		Skins.apply (App.settings.main.skin); // what's saved, not what was typed
		closing = true;
		close ();
	}
}
