using Gtk;

/** Find and Replace in Tags: one tag of the chosen songs, with the changes shown as they are typed */
public class BeatBox.FindReplaceDialog : Dialog {
	// the tags offered: GObject property names of Media
	const string[] PROPERTIES = { "title", "artist", "album-artist", "album", "genre", "composer", "grouping", "comment" };

	Gee.List<Media> medias;
	Gee.HashMap<Media, string> changes = new Gee.HashMap<Media, string> (); // song → its tag once replaced
	ComboBoxText field;
	Entry find;
	Entry replace;
	CheckButton case_sensitive;
	CheckButton regex;
	CheckButton whole_word;
	Label summary;
	Gtk.ListStore preview;
	Widget apply_button;

	public static void run_for (Gee.Collection<Media> medias) {
		var dialog = new FindReplaceDialog (medias);
		while (dialog.run () == ResponseType.APPLY)
			dialog.apply (); // stays open for the next replacement
		dialog.destroy ();
	}

	FindReplaceDialog (Gee.Collection<Media> chosen) {
		title = _("Find and Replace in Tags");
		transient_for = App.window;
		modal = true;
		set_default_size (680, 480);
		medias = new Gee.ArrayList<Media> ();
		foreach (var m in chosen)
			if (m.can_save_metadata)
				medias.add (m);

		field = new ComboBoxText ();
		string[] names = { _("Title"), _("Artist"), _("Album Artist"), _("Album"), _("Genre"), _("Composer"), _("Grouping"), _("Comment") };
		foreach (var name in names)
			field.append_text (name);
		field.active = 1;
		find = new Entry ();
		find.hexpand = true;
		find.activates_default = true;
		replace = new Entry ();
		replace.activates_default = true;
		case_sensitive = new CheckButton.with_label (_("Match case"));
		regex = new CheckButton.with_label (_("Regular expression"));
		regex.tooltip_text = _("The replacement may use \\1, \\2… for the parts in parentheses");
		whole_word = new CheckButton.with_label (_("Whole words"));

		var grid = new Grid ();
		grid.row_spacing = 6;
		grid.column_spacing = 8;
		string[] labels = { _("Tag:"), _("Find:"), _("Replace with:") };
		Widget[] widgets = { field, find, replace };
		for (int i = 0; i < 3; i++) {
			var label = new Label (labels[i]);
			label.xalign = 1;
			grid.attach (label, 0, i);
			grid.attach (widgets[i], 1, i);
		}
		var checks = new Box (Orientation.HORIZONTAL, 12);
		checks.add (case_sensitive);
		checks.add (regex);
		checks.add (whole_word);
		grid.attach (checks, 1, 3);

		preview = new Gtk.ListStore (2, typeof (string), typeof (string));
		var view = new TreeView.with_model (preview);
		string[] columns = { _("Now"), _("After") };
		for (int i = 0; i < 2; i++) {
			var text = new CellRendererText ();
			text.ellipsize = Pango.EllipsizeMode.END;
			var column = new TreeViewColumn.with_attributes (columns[i], text, "text", i);
			column.expand = true;
			view.append_column (column);
		}
		var scroll = new ScrolledWindow (null, null);
		scroll.expand = true;
		scroll.shadow_type = ShadowType.IN;
		scroll.add (view);

		summary = new Label ("");
		summary.xalign = 0;
		summary.wrap = true;

		var box = get_content_area ();
		box.spacing = 8;
		box.border_width = 8;
		box.add (grid);
		box.add (summary);
		box.add (scroll);
		box.show_all ();

		add_button (_("Close"), ResponseType.CLOSE);
		apply_button = add_button (_("Replace All"), ResponseType.APPLY);
		apply_button.get_style_context ().add_class ("suggested-action");
		set_default_response (ResponseType.APPLY);

		field.changed.connect (refresh);
		find.changed.connect (refresh);
		replace.changed.connect (refresh);
		case_sensitive.toggled.connect (refresh);
		regex.toggled.connect (refresh);
		whole_word.toggled.connect (refresh);
		refresh ();
	}

	string property () {
		return PROPERTIES[field.active];
	}

	static string get_tag (Media m, string property) {
		string value;
		m.get (property, out value);
		return value ?? "";
	}

	/** What Replace All would do, worked out again at every change */
	void refresh () {
		changes.clear ();
		preview.clear ();
		if (find.text == "") {
			summary.label = ngettext ("%d song chosen. Type what to find.", "%d songs chosen. Type what to find.", medias.size).printf (medias.size);
			apply_button.sensitive = false;
			return;
		}
		try {
			var re = TagReplace.pattern (find.text, case_sensitive.active, regex.active, whole_word.active);
			foreach (var m in medias) {
				string now = get_tag (m, property ());
				string after = TagReplace.apply (re, now, replace.text, regex.active);
				if (after == now)
					continue;
				changes[m] = after;
				TreeIter iter;
				preview.append (out iter);
				preview.set (iter, 0, now, 1, after);
			}
			summary.label = ngettext ("%d of %d songs changes.", "%d of %d songs change.", changes.size).printf (changes.size, medias.size);
		} catch (RegexError err) {
			summary.label = _("The regular expression is not valid: %s").printf (err.message);
		}
		apply_button.sensitive = changes.size > 0;
	}

	void apply () {
		var changed = new Gee.ArrayList<Media> (); // kept by the database update, while changes is refreshed
		foreach (var entry in changes.entries) {
			entry.key.set (property (), entry.value);
			changed.add (entry.key);
		}
		App.library.update_medias (changed, true, true, true);
		App.window.show_notification (_("Tags replaced"), ngettext ("%d song changed", "%d songs changed", changes.size).printf (changes.size), null);
		refresh (); // nothing left to replace, unless the replacement matches again
	}
}
