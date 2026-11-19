using Gtk;

/** Fill In Tags from File Names: shows what the songs' paths say before the empty tags take it */
public class BeatBox.FillTagsDialog : ButtonDialog {
	Gee.HashMap<Media, Media> filled = new Gee.HashMap<Media, Media> (); // song → copy with the tags filled in

	public static async void run_for (Gee.Collection<Media> medias) {
		var dialog = new FillTagsDialog (medias);
		if (dialog.filled.size == 0) {
			dialog.destroy ();
			App.window.doAlert (_("Nothing to fill in"), _("The file names don't add anything to these songs' tags."));
			return;
		}
		if ((yield dialog.run ()) == ButtonDialog.APPLY)
			dialog.apply ();
		dialog.destroy ();
	}

	FillTagsDialog (Gee.Collection<Media> medias) {
		base (_("Fill In Tags from File Names"), App.window);
		resizable = true;
		set_default_size (760, 420);

		// columns: file, then track, title, artist, album, year as markup (filled in ones in bold)
		var table = new SimpleTable ();
		var folder = App.library.song_library.folder;
		foreach (var m in medias) {
			if (!m.uri.has_prefix ("file:"))
				continue;
			var copy = m.copy ();
			var changed = TagGuess.fill (copy, folder);
			if (changed.length == 0)
				continue;
			filled[m] = copy;
			table.add ({ Markup.escape_text (File.new_for_uri (m.uri).get_basename ()),
				cell ((copy.track > 0) ? copy.track.to_string () : "", "track" in changed),
				cell (copy.title, "title" in changed),
				cell (copy.artist, "artist" in changed),
				cell (copy.album, "album" in changed),
				cell ((copy.year > 0) ? copy.year.to_string () : "", "year" in changed) });
		}

		string[] titles = { _("File"), _("Track"), _("Title"), _("Artist"), _("Album"), _("Year") };
		for (int i = 0; i < titles.length; i++) {
			bool short_one = i == 1 || i == 5; // track and year are short: never cut
			table.add_column (titles[i], i, true, !short_one, short_one ? Pango.EllipsizeMode.NONE : Pango.EllipsizeMode.END);
		}
		var scroll = new ScrolledWindow ();
		scroll.vexpand = true;
		scroll.has_frame = true;
		scroll.set_child (table.view);

		var label = new Label (ngettext ("%d song gets the tags in bold. Tags already set are kept.",
		                                 "%d songs get the tags in bold. Tags already set are kept.", filled.size).printf (filled.size));
		label.xalign = 0.0f;
		label.wrap = true;
		var box = content_area;
		box.spacing = 8;
		box.append (label);
		box.append (AquaScroll.wrap (scroll));

		add_button (_("Cancel"), ButtonDialog.CANCEL);
		add_button (_("Fill In"), ButtonDialog.APPLY).add_css_class("suggested-action");
		set_default_response (ButtonDialog.APPLY);
	}

	static string cell (string text, bool bold) {
		var escaped = Markup.escape_text (text);
		return bold ? "<b>" + escaped + "</b>" : escaped;
	}

	void apply () {
		foreach (var entry in filled.entries) {
			var m = entry.key;
			var copy = entry.value;
			m.title = copy.title;
			m.artist = copy.artist;
			m.album_artist = copy.album_artist;
			m.album = copy.album;
			m.track = copy.track;
			m.year = copy.year;
		}
		App.library.update_medias (filled.keys, true, true, true);
	}
}
