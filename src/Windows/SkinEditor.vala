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
		var scroll = new ScrolledWindow (null, null);
		scroll.expand = true;
		scroll.add (view);

		status = new Label ("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.END;
		status.selectable = true;

		var revert = new Button.with_label (_("Revert"));
		revert.tooltip_text = _("Back to the last saved version");
		revert.clicked.connect (() => { view.buffer.text = saved_text; });
		save_button = new Button.with_label (Skins.is_user (skin) ? _("Save") : _("Save as Copy"));
		save_button.tooltip_text = Skins.is_user (skin) ? null : _("A bundled skin can't be changed: the copy goes to the skins folder");
		save_button.get_style_context ().add_class ("suggested-action");
		save_button.clicked.connect (() => { save (); });

		var bottom = new Box (Orientation.HORIZONTAL, 6);
		bottom.margin = 6;
		bottom.pack_start (status, true, true);
		bottom.pack_end (save_button, false, false);
		bottom.pack_end (revert, false, false);
		var box = new Box (Orientation.VERTICAL, 0);
		box.pack_start (scroll, true, true);
		box.pack_start (new Separator (Orientation.HORIZONTAL), false, false);
		box.pack_start (bottom, false, false);
		add (box);

		// shown a moment after typing stops, not at every key
		view.buffer.changed.connect (() => {
			if (pending != 0)
				Source.remove (pending);
			pending = Timeout.add (300, () => { pending = 0; show_css (); return false; });
		});
		delete_event.connect (() => !may_close ());
		destroy.connect (() => {
			if (pending != 0)
				Source.remove (pending);
			Skins.apply (App.settings.main.skin); // what's saved, not what was typed
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

	/** Unsaved changes: save them, drop them or stay */
	bool may_close () {
		if (text () == saved_text)
			return true;
		var ask = new MessageDialog (this, DialogFlags.MODAL, MessageType.QUESTION, ButtonsType.NONE,
			"%s", _("Save the changes to the skin?"));
		ask.add_button (_("Close Without Saving"), ResponseType.REJECT);
		ask.add_button (_("Cancel"), ResponseType.CANCEL);
		ask.add_button (_("Save"), ResponseType.ACCEPT);
		ask.set_default_response (ResponseType.ACCEPT);
		var answer = ask.run ();
		ask.destroy ();
		return answer == ResponseType.REJECT || (answer == ResponseType.ACCEPT && save ());
	}
}
