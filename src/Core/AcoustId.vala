/*
 * Identifies a song by its sound: fpcalc (Chromaprint's tool) makes the fingerprint
 * and AcoustID answers with the MusicBrainz recordings that match it.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

namespace BeatBox.AcoustId {
	public class Match : Object {
		public string title = "";
		public string artist = "";
		public string album = "";
		public int score; // %
	}

	/** fpcalc comes with Chromaprint (chromaprint on Arch, libchromaprint-tools on Debian) */
	public bool available () {
		return Environment.find_program_in_path ("fpcalc") != null;
	}

	/** Blocking. The matches, best first; error says why there are none when it isn't just "nothing found". */
	public Gee.List<Match> identify (string path, out string? error) {
		error = null;
		var matches = new Gee.ArrayList<Match> ();
		string output;
		int status;
		try {
			Process.spawn_sync (null, { "fpcalc", "-json", path }, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL,
			                    null, out output, null, out status);
		} catch (SpawnError err) {
			error = err.message;
			return matches;
		}
		var print = Http.json_object (output);
		if (status != 0 || print == null) {
			error = _("Could not compute the fingerprint of this file.");
			return matches;
		}

		uint http_status;
		var body = Http.send ("POST", "https://api.acoustid.org/v2/lookup", "application/x-www-form-urlencoded",
			"client=%s&duration=%d&meta=recordings+releasegroups+compress&fingerprint=%s".printf (
				Uri.escape_string (App.settings.lastfm.acoustid_key), (int) print.get_double_member_with_default ("duration", 0),
				print.get_string_member_with_default ("fingerprint", "")), null, out http_status);
		var answer = Http.json_object (body);
		if (answer == null) {
			error = _("AcoustID could not be reached.");
			return matches;
		}
		if (answer.get_string_member_with_default ("status", "") != "ok") {
			var problem = answer.has_member ("error") ? answer.get_object_member ("error").get_string_member_with_default ("message", "") : "";
			error = _("AcoustID answered: %s").printf (problem);
			return matches;
		}

		var seen = new Gee.HashSet<string> ();
		foreach (var result in answer.get_array_member ("results").get_elements ()) {
			var r = result.get_object ();
			if (!r.has_member ("recordings"))
				continue;
			foreach (var recording in r.get_array_member ("recordings").get_elements ()) {
				var rec = recording.get_object ();
				var artists = new string[0];
				if (rec.has_member ("artists"))
					foreach (var a in rec.get_array_member ("artists").get_elements ())
						artists += a.get_object ().get_string_member_with_default ("name", "");
				string[] albums = { "" };
				if (rec.has_member ("releasegroups")) {
					albums = {};
					foreach (var g in rec.get_array_member ("releasegroups").get_elements ())
						albums += g.get_object ().get_string_member_with_default ("title", "");
				}
				foreach (var album in albums) {
					var m = new Match ();
					m.title = rec.get_string_member_with_default ("title", "");
					m.artist = string.joinv (", ", artists);
					m.album = album;
					m.score = (int) (r.get_double_member_with_default ("score", 0) * 100);
					if (m.title != "" && seen.add (m.title + "\n" + m.artist + "\n" + m.album))
						matches.add (m);
				}
			}
		}
		return matches;
	}
}
