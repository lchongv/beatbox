using Gtk;

/** Fill In Tags from File Names: shows what the songs' paths say before the empty tags take it */
public class BeatBox.FillTagsDialog : Dialog {
	Gee.HashMap<Media, Media> filled = new Gee.HashMap<Media, Media> (); // song → copy with the tags filled in

	public static void run_for (Gee.Collection<Media> medias) {
		var dialog = new FillTagsDialog (medias);
		if (dialog.filled.size == 0) {
			dialog.destroy ();
			App.window.doAlert (_("Nothing to fill in"), _("The file names don't add anything to these songs' tags."));
			return;
		}
		if (dialog.run () == ResponseType.APPLY)
			dialog.apply ();
		dialog.destroy ();
	}

	FillTagsDialog (Gee.Collection<Media> medias) {
		title = _("Fill In Tags from File Names");
		transient_for = App.window;
		modal = true;
		set_default_size (760, 420);

		// columns: file, then track, title, artist, album, year as markup (filled in ones in bold)
		var store = new Gtk.ListStore (6, typeof (string), typeof (string), typeof (string), typeof (string), typeof (string), typeof (string));
		var folder = App.library.song_library.folder;
		foreach (var m in medias) {
			if (!m.uri.has_prefix ("file:"))
				continue;
			var copy = m.copy ();
			var changed = TagGuess.fill (copy, folder);
			if (changed.length == 0)
				continue;
			filled[m] = copy;
			TreeIter iter;
			store.append (out iter);
			store.set (iter, 0, File.new_for_uri (m.uri).get_basename (),
				1, cell ((copy.track > 0) ? copy.track.to_string () : "", "track" in changed),
				2, cell (copy.title, "title" in changed),
				3, cell (copy.artist, "artist" in changed),
				4, cell (copy.album, "album" in changed),
				5, cell ((copy.year > 0) ? copy.year.to_string () : "", "year" in changed));
		}

		var view = new TreeView.with_model (store);
		string[] titles = { _("File"), _("Track"), _("Title"), _("Artist"), _("Album"), _("Year") };
		for (int i = 0; i < titles.length; i++) {
			var text = new CellRendererText ();
			if (i != 1 && i != 5) // track and year are short: never cut
				text.ellipsize = Pango.EllipsizeMode.END;
			var column = new TreeViewColumn.with_attributes (titles[i], text, (i == 0) ? "text" : "markup", i);
			column.resizable = true;
			column.expand = i != 1 && i != 5;
			view.append_column (column);
		}
		var scroll = new ScrolledWindow (null, null);
		scroll.expand = true;
		scroll.shadow_type = ShadowType.IN;
		scroll.add (view);

		var label = new Label (ngettext ("%d song gets the tags in bold. Tags already set are kept.",
		                                 "%d songs get the tags in bold. Tags already set are kept.", filled.size).printf (filled.size));
		label.xalign = 0;
		label.wrap = true;
		var box = get_content_area ();
		box.spacing = 8;
		box.border_width = 8;
		box.add (label);
		box.add (scroll);
		box.show_all ();

		add_button (_("Cancel"), ResponseType.CANCEL);
		add_button (_("Fill In"), ResponseType.APPLY).get_style_context ().add_class ("suggested-action");
		set_default_response (ResponseType.APPLY);
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
