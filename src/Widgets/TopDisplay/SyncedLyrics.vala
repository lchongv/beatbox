/*-
 * Synced lyrics from lrclib.net, cached in ~/.cache/beatbox/lyrics.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/** Timed lines of an .lrc file: times[i] (ms) is when texts[i] starts */
public class BeatBox.SyncedLyrics : GLib.Object {
	public int64[] times = {};
	public string[] texts = {};

	/** Parses "[mm:ss.xx] text" lines; untimed lines and tags like [ar:...] are skipped */
	public SyncedLyrics.from_lrc (string lrc) {
		var re = /^\[(\d+):(\d+(?:\.\d+)?)\]/;
		foreach (var line in lrc.split ("\n")) {
			MatchInfo mi;
			// a line may carry several stamps: [00:12.00][01:30.00] chorus
			var rest = line.strip ();
			int64[] stamps = {};
			while (re.match (rest, 0, out mi)) {
				stamps += int64.parse (mi.fetch (1)) * 60000 + (int64)(double.parse (mi.fetch (2)) * 1000);
				rest = rest.substring (mi.fetch (0).length);
			}
			foreach (var t in stamps)
				insert (t, rest.strip ());
		}
	}

	void insert (int64 t, string text) {
		int i = times.length;
		while (i > 0 && times[i - 1] > t)
			i--;
		int64[] nt = {}; string[] nx = {};
		for (int j = 0; j < times.length; j++) {
			if (j == i) { nt += t; nx += text; }
			nt += times[j]; nx += texts[j];
		}
		if (i == times.length) { nt += t; nx += text; }
		times = nt; texts = nx;
	}

	/** Index of the line playing at ms, or -1 before the first one */
	public int line_at (int64 ms) {
		int i = -1;
		while (i + 1 < times.length && times[i + 1] <= ms)
			i++;
		return i;
	}

	static string cache_path (Media m) {
		var key = Checksum.compute_for_string (ChecksumType.MD5, m.artist + "\n" + m.title + "\n" + m.album);
		return Path.build_filename (App.settings.get_cache_dir (), "lyrics", key + ".lrc");
	}

	/** Blocking: cache first, then lrclib.net. Returns null when there are no synced lyrics.
	 *  A miss is cached as an empty file so the server is asked only once per song. */
	public static SyncedLyrics? fetch (Media m) {
		var path = cache_path (m);
		string lrc;
		try {
			if (FileUtils.get_contents (path, out lrc))
				return lrc == "" ? null : new SyncedLyrics.from_lrc (lrc);
		} catch (Error e) {}

		lrc = "";
		var url = "https://lrclib.net/api/get?artist_name=%s&track_name=%s&album_name=%s&duration=%u".printf (
			Uri.escape_string (m.artist), Uri.escape_string (m.title), Uri.escape_string (m.album), m.length);
		var body = Http.fetch (url);
		if (body != "") {
			try {
				var parser = new Json.Parser ();
				parser.load_from_data (body);
				var obj = parser.get_root ().get_object ();
				if (obj.has_member ("syncedLyrics") && !obj.get_null_member ("syncedLyrics"))
					lrc = obj.get_string_member ("syncedLyrics");
			} catch (Error e) {}
		} else {
			return null; // network trouble: don't cache, try again next time
		}

		DirUtils.create_with_parents (Path.get_dirname (path), 0755);
		try { FileUtils.set_contents (path, lrc); } catch (Error e) {}
		return lrc == "" ? null : new SyncedLyrics.from_lrc (lrc);
	}
}
