/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/**
 * Tags read from where a song is: "Artist/Album/03 - Title.mp3",
 * "Artist - Album (1999)/03 Title.flac", "Artist - Title.mp3"...
 * Only what the tags leave empty is filled in.
 */
namespace BeatBox.TagGuess {
	public class Guess : Object {
		public string artist = "";
		public string album = "";
		public string title = "";
		public uint track = 0;
		public uint year = 0;
	}

	/**
	 * path is relative to the music folder ("Artist/Album/03 - Title.mp3"), or just
	 * the file name for a song outside it: its folders say nothing then.
	 */
	public Guess from_path (string path) {
		var g = new Guess ();
		var parts = path.split ("/");
		string name = parts[parts.length - 1];
		int dot = name.last_index_of_char ('.');
		if (dot > 0)
			name = name.substring (0, dot);
		name = tidy (name);
		MatchInfo m;

		// "03 - Title", "03. Title", "03 Title", "1-03 Title" (disc and track)
		if (/^(?:\d{1,2}-)?(\d{1,3})(?:\s*[-.]\s*|\s+)(.+)$/.match (name, 0, out m)) {
			g.track = int.parse (m.fetch (1));
			name = tidy (m.fetch (2)); // "07 My_Song": the spaces were the number's
		}

		// the folder is the album when it says so ("Artist - Album") or the tracks are numbered;
		// a loose "Artist - Title.mp3" in a folder of singles says nothing about an album
		if (parts.length >= 2) {
			string folder = tidy (parts[parts.length - 2]);
			if (/^((?:19|20)\d\d)\s+-\s+(.+)$/.match (folder, 0, out m)) {
				g.year = int.parse (m.fetch (1));
				folder = m.fetch (2);
			} else if (/^(.+?)\s*[(\[]((?:19|20)\d\d)[)\]]$/.match (folder, 0, out m)) {
				g.year = int.parse (m.fetch (2)); // before folder changes: m points into it
				folder = m.fetch (1);
			}
			int sep = folder.index_of (" - ");
			if (sep > 0) {
				g.artist = folder.substring (0, sep).strip ();
				g.album = folder.substring (sep + 3).strip ();
			} else if (g.track > 0 || g.year > 0) {
				g.album = folder;
				if (parts.length >= 3)
					g.artist = tidy (parts[parts.length - 3]);
			} else {
				g.year = 0;
			}
		}

		// "Artist - Title": the artist again, or the only place it is
		int sep = name.index_of (" - ");
		if (sep > 0) {
			string first = name.substring (0, sep).strip ();
			if (g.artist == "" || first.down () == g.artist.down ()) {
				g.artist = first;
				name = name.substring (sep + 3).strip ();
			}
		}
		g.title = name;
		return g;
	}

	/** "my_song__name " → "my song name"; names with spaces keep their underscores */
	string tidy (string s) {
		string t = s.contains (" ") ? s : s.replace ("_", " ");
		try {
			t = /\s+/.replace (t, -1, 0, " ");
		} catch (RegexError err) {}
		return t.strip ();
	}

	/**
	 * Fills in what m's tags leave empty (or as the importer's placeholders) from its
	 * path, relative to root when it is inside it. Returns the fields it changed.
	 */
	public string[] fill (Media m, File? root) {
		var file = File.new_for_uri (m.uri);
		string? path = (root != null) ? root.get_relative_path (file) : null;
		var g = from_path (path ?? file.get_basename ());
		string[] changed = {};

		// the importer puts the file name (still escaped) in an empty title
		string last = m.uri.substring (m.uri.last_index_of_char ('/') + 1);
		if (g.title != "" && (m.title == "" || m.title == "Unknown Title" || m.title == last || m.title == file.get_basename ())) {
			m.title = g.title;
			changed += "title";
		}
		bool no_artist = m.artist == "" || m.artist == "Unknown Artist";
		if (g.artist != "" && no_artist) {
			if (m.album_artist == "" || m.album_artist == m.artist)
				m.album_artist = g.artist;
			m.artist = g.artist;
			changed += "artist";
		}
		if (g.album != "" && (m.album == "" || m.album == "Unknown Album")) {
			m.album = g.album;
			changed += "album";
		}
		if (g.track > 0 && m.track == 0) {
			m.track = g.track;
			changed += "track";
		}
		if (g.year > 0 && m.year == 0) {
			m.year = g.year;
			changed += "year";
		}
		return changed;
	}
}
