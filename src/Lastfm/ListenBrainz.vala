/*-
 * Listens sent to ListenBrainz (listenbrainz.org), with the user token from
 * Preferences › Scrobbling. See https://listenbrainz.readthedocs.io/en/latest/users/api/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

namespace BeatBox.ListenBrainz {
	const string API = "https://api.listenbrainz.org/1/";

	/** BEATBOX_LISTENBRAINZ_API points it at another server (tests, self-hosted instances) */
	string api () {
		return Environment.get_variable ("BEATBOX_LISTENBRAINZ_API") ?? API;
	}

	bool connected () {
		return App.settings.lastfm.listenbrainz_token != "";
	}

	/** Only songs with an artist and a title (radio and podcasts would fill the history with noise) */
	bool can_send (Media m) {
		return connected () && m.media_type == MediaType.SONG && m.artist.strip () != "" && m.title.strip () != "";
	}

	/** The song is starting */
	public void now_playing (Media m) {
		if (can_send (m))
			submit_listen ("playing_now", m, 0);
	}

	/** The song was listened to; started_at is when it began playing (unix time) */
	public void listened (Media m, int64 started_at) {
		if (can_send (m))
			submit_listen ("single", m, started_at);
	}

	void submit_listen (string listen_type, Media m, int64 started_at) {
		// built here, on the main loop; the thread only sends it
		var b = new Json.Builder ();
		b.begin_object ();
		b.set_member_name ("listen_type").add_string_value (listen_type);
		b.set_member_name ("payload").begin_array ().begin_object ();
		if (listen_type != "playing_now")
			b.set_member_name ("listened_at").add_int_value (started_at);
		b.set_member_name ("track_metadata").begin_object ();
		b.set_member_name ("artist_name").add_string_value (m.artist);
		b.set_member_name ("track_name").add_string_value (m.title);
		if (m.album.strip () != "")
			b.set_member_name ("release_name").add_string_value (m.album);
		b.set_member_name ("additional_info").begin_object ();
		if (m.length > 0)
			b.set_member_name ("duration_ms").add_int_value ((int64) m.length * 1000);
		if (m.track > 0)
			b.set_member_name ("tracknumber").add_int_value (m.track);
		b.set_member_name ("media_player").add_string_value ("BeatBox");
		b.set_member_name ("submission_client").add_string_value ("BeatBox");
		b.set_member_name ("submission_client_version").add_string_value (Build.VERSION);
		b.end_object ();
		b.end_object ();
		b.end_object ().end_array ();
		b.end_object ();
		var generator = new Json.Generator ();
		generator.root = b.get_root ();
		string body = generator.to_data (null);
		string authorization = "Token " + App.settings.lastfm.listenbrainz_token;

		new Thread<void*> ("listenbrainz", () => {
			uint status;
			string answer = Http.send ("POST", api () + "submit-listens", "application/json", body, authorization, out status);
			if (status != 200)
				message ("ListenBrainz did not take the listen (%u): %s", status, answer);
			return null;
		});
	}

	public delegate void ValidateFunc (bool valid, string user_name);

	/** Checks a token; done runs on the main loop with the account's name when it is valid */
	public void validate (string token, owned ValidateFunc done) {
		string authorization = "Token " + token.strip ();
		new Thread<void*> ("listenbrainz-validate", () => {
			uint status;
			string answer = Http.send ("GET", api () + "validate-token", null, null, authorization, out status);
			bool valid = false;
			string user = "";
			var obj = Http.json_object (answer);
			if (obj != null) {
				valid = obj.get_boolean_member_with_default ("valid", false);
				if (valid)
					user = obj.get_string_member_with_default ("user_name", "");
			}
			Idle.add (() => { done (valid, user); return false; });
			return null;
		});
	}
}
