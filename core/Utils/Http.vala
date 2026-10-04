namespace BeatBox.Http {
	Soup.Session new_session (string url) {
		var session = new Soup.Session ();
		session.timeout = 30;
		// MusicBrainz, radio-browser.info and lrclib.net ask clients to identify themselves;
		// Apple, on the other hand, answers ~5 s later to unknown user agents
		if ("musicbrainz.org" in url || "radio-browser.info" in url || "lrclib.net" in url)
			session.user_agent = "BeatBox/" + Build.VERSION + " ( https://launchpad.net/beat-box )";
		return session;
	}

	/** Blocking HTTP request; returns the response body, or "" on failure. */
	public string fetch (string url, string method = "GET") {
		var message = new Soup.Message (method, url);
		if (message == null)
			return "";

		try {
			unowned uint8[] data = new_session (url).send_and_read (message).get_data ();
			var sb = new StringBuilder.sized (data.length + 1);
			sb.append_len ((string) data, data.length);
			return sb.str;
		} catch (Error err) {
			warning ("Could not fetch %s: %s", url, err.message);
			return "";
		}
	}

	/** Blocking GET of binary data (follows redirects); null unless the answer is 200 OK. */
	public Bytes? fetch_bytes (string url) {
		var message = new Soup.Message ("GET", url);
		if (message == null)
			return null;

		try {
			var bytes = new_session (url).send_and_read (message);
			return (message.status_code == 200) ? bytes : null;
		} catch (Error err) {
			warning ("Could not fetch %s: %s", url, err.message);
			return null;
		}
	}
}
