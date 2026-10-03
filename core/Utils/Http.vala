namespace BeatBox.Http {
	/** Blocking HTTP request; returns the response body, or "" on failure. */
	public string fetch (string url, string method = "GET") {
		var message = new Soup.Message (method, url);
		if (message == null)
			return "";

		var session = new Soup.Session ();
		session.timeout = 30;
		try {
			unowned uint8[] data = session.send_and_read (message).get_data ();
			var sb = new StringBuilder.sized (data.length + 1);
			sb.append_len ((string) data, data.length);
			return sb.str;
		} catch (Error err) {
			warning ("Could not fetch %s: %s", url, err.message);
			return "";
		}
	}
}
