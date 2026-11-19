using Gtk;

/** Find and Replace in Tags: one tag of the chosen songs, with the changes shown as they are typed */
public class BeatBox.FindReplaceDialog : ButtonDialog {
	// the tags offered: GObject property names of Media
	const string[] PROPERTIES = { "title", "artist", "album-artist", "album", "genre", "composer", "grouping", "comment" };

	Gee.List<Media> medias;
	Gee.HashMap<Media, string> changes = new Gee.HashMap<Media, string> (); // song → its tag once replaced
	DropDown field;
	Entry find;
	Entry replace;
	CheckButton case_sensitive;
	CheckButton regex;
	CheckButton whole_word;
	Label summary;
	SimpleTable preview;
	Widget apply_button;

	public static async void run_for (Gee.Collection<Media> medias) {
		var dialog = new FindReplaceDialog (medias);
		while ((yield dialog.run ()) == ButtonDialog.APPLY)
			dialog.apply (); // stays open for the next replacement
		dialog.destroy ();
	}

	FindReplaceDialog (Gee.Collection<Media> chosen) {
		base (_("Find and Replace in Tags"), App.window);
		resizable = true;
		set_default_size (680, 480);
		medias = new Gee.ArrayList<Media> ();
		foreach (var m in chosen)
			if (m.can_save_metadata)
				medias.add (m);

		string[] names = { _("Title"), _("Artist"), _("Album Artist"), _("Album"), _("Genre"), _("Composer"), _("Grouping"), _("Comment") };
		field = new DropDown.from_strings (names);
		field.selected = 1;
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
			label.xalign = 1.0f;
			grid.attach (label, 0, i);
			grid.attach (widgets[i], 1, i);
		}
		var checks = new Box (Orientation.HORIZONTAL, 12);
		checks.append (case_sensitive);
		checks.append (regex);
		checks.append (whole_word);
		grid.attach (checks, 1, 3);

		preview = new SimpleTable ();
		preview.add_column (_("Now"), 0);
		preview.add_column (_("After"), 1);
		var scroll = new ScrolledWindow ();
		scroll.vexpand = true;
		scroll.has_frame = true;
		scroll.set_child (preview.view);

		summary = new Label ("");
		summary.xalign = 0.0f;
		summary.wrap = true;

		var box = content_area;
		box.spacing = 8;
		box.append (grid);
		box.append (summary);
		box.append (AquaScroll.wrap (scroll));

		add_button (_("Close"), ButtonDialog.CLOSE);
		apply_button = add_button (_("Replace All"), ButtonDialog.APPLY);
		apply_button.add_css_class("suggested-action");
		set_default_response (ButtonDialog.APPLY);

		field.notify["selected"].connect (refresh);
		find.changed.connect (refresh);
		replace.changed.connect (refresh);
		case_sensitive.toggled.connect (refresh);
		regex.toggled.connect (refresh);
		whole_word.toggled.connect (refresh);
		refresh ();
	}

	string property () {
		return PROPERTIES[field.selected];
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
				preview.add ({ now, after });
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
