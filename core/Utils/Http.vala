namespace BeatBox.Http {
	Soup.Session new_session (string url) {
		var session = new Soup.Session ();
		session.timeout = 30;
		// MusicBrainz, radio-browser.info, lrclib.net and ListenBrainz ask clients to identify
		// themselves; Apple, on the other hand, answers ~5 s later to unknown user agents
		if ("musicbrainz.org" in url || "radio-browser.info" in url || "lrclib.net" in url || "listenbrainz.org" in url)
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

	/**
	 * Blocking request with a body (form or JSON) and an optional Authorization
	 * header. Returns the response body ("" on failure); status is the HTTP
	 * status, 0 when the server couldn't be reached.
	 */
	public string send (string method, string url, string? content_type, string? body, string? authorization, out uint status) {
		status = 0;
		var message = new Soup.Message (method, url);
		if (message == null)
			return "";
		if (authorization != null)
			message.request_headers.append ("Authorization", authorization);
		if (body != null)
			message.set_request_body_from_bytes (content_type, new Bytes (body.data));
		try {
			unowned uint8[] data = new_session (url).send_and_read (message).get_data ();
			status = message.status_code;
			var sb = new StringBuilder.sized (data.length + 1);
			sb.append_len ((string) data, data.length);
			return sb.str;
		} catch (Error err) {
			warning ("Could not reach %s: %s", url, err.message);
			return "";
		}
	}

	/** The top object of a JSON answer; null when the answer is something else (not JSON, an error page...) */
	public Json.Object? json_object (string body) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data (body);
		} catch (Error err) {
			return null;
		}
		unowned Json.Node? root = parser.get_root ();
		return (root != null && root.get_node_type () == Json.NodeType.OBJECT) ? root.get_object () : null;
	}

	/**
	 * The objects in a JSON array: the whole answer (member null) or a member of its top
	 * object. Null when the answer is something else: not JSON, an error message...
	 */
	public Gee.List<Json.Object>? json_objects (string body, string? member = null) {
		var parser = new Json.Parser ();
		try {
			parser.load_from_data (body);
		} catch (Error err) {
			return null;
		}
		unowned Json.Node? node = parser.get_root ();
		if (node != null && member != null)
			node = (node.get_node_type () == Json.NodeType.OBJECT) ? node.get_object ().get_member (member) : null;
		if (node == null || node.get_node_type () != Json.NodeType.ARRAY)
			return null;
		var objects = new Gee.ArrayList<Json.Object> ();
		foreach (unowned Json.Node item in node.get_array ().get_elements ())
			if (item.get_node_type () == Json.NodeType.OBJECT)
				objects.add (item.get_object ());
		return objects;
	}

	/** application/x-www-form-urlencoded, values escaped */
	public string form_encode (Gee.Map<string, string> fields) {
		var sb = new StringBuilder ();
		foreach (var entry in fields.entries) {
			if (sb.len > 0)
				sb.append_c ('&');
			sb.append (Uri.escape_string (entry.key, null, false));
			sb.append_c ('=');
			sb.append (Uri.escape_string (entry.value, null, false));
		}
		return sb.str;
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
