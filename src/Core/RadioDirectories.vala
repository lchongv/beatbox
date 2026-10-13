/*
 * The directories DirectoryDialog finds radio stations in, without any GTK
 * (tests/radio-directories.vala runs it on its own):
 *  - radio-browser.info: community database of ~50k stations, filtered by the server
 *  - SHOUTcast: the JSON directory.shoutcast.com's own pages use (its API needs a key)
 *  - laut.fm: its public API; ~17k stations made by its users
 *  - Icecast: dir.xiph.org's whole listing (9 MB), kept a day in ~/.cache/beatbox
 * Only radio-browser filters on the server; the others are filtered here.
 */
namespace BeatBox.Radio {
	public enum Directory { RADIO_BROWSER, SHOUTCAST, LAUT_FM, ICECAST }

	/** What a search asks for; "" or 0 means any */
	public class Query {
		public string text = "";
		public string country = ""; // two-letter code
		public string state = "";
		public string language = "";
		public string genre = "";
		public string codec = "";   // as radio-browser names them: MP3, AAC, AAC+, OGG, FLAC
		public int min_bitrate = 0;
		public string order = "votes"; // radio-browser's: votes, clickcount, clicktrend, name, bitrate, random
		public bool https_only = false;
	}

	public class Result {
		public string name = "";
		public string url = "";     // for SHOUTcast a playlist: see stream_of ()
		public string country = "";
		public string genre = "";   // the first of tags
		public string tags = "";
		public string codec = "";
		public int bitrate = 0;
	}

	/** One value of a filter: a country, a language, a genre... */
	public class Choice {
		public string name = "";
		public string value = "";   // what the directory is asked with (a country's code, a tag...)
		public int count = 0;       // its stations; 0 when the directory doesn't say
	}

	const int MAX_RESULTS = 200;
	const int64 DAY = 24 * 3600;
	const string SHOUTCAST = "https://directory.shoutcast.com";
	// SHOUTcast's own genres (its pages list them in their scripts, there is nothing to ask)
	const string[] SHOUTCAST_GENRES = { "Alternative", "Blues", "Classical", "Country", "Decades", "Easy Listening",
		"Electronic", "Folk", "Inspirational", "International", "Jazz", "Latin", "Metal", "Misc", "New Age", "Pop",
		"Public Radio", "R&B and Urban", "Rap", "Reggae", "Rock", "Seasonal and Holiday", "Soundtracks", "Talk", "Themes" };
	// Icecast genres are whatever each station typed: some common words to start from
	const string[] ICECAST_GENRES = { "80s", "90s", "Alternative", "Ambient", "Blues", "Chillout", "Classical", "Country",
		"Dance", "Electronic", "Folk", "Hip Hop", "House", "Jazz", "Latin", "Lounge", "Metal", "News", "Oldies", "Pop",
		"Punk", "Reggae", "Rock", "Soul", "Talk", "Techno", "Trance", "World" };

	string? radio_host = null;
	Mutex cache_lock;
	Gee.List<Result>? icecast = null;

	/* radio-browser.info asks clients to pick one of its mirrors: the
	 * all.api name resolves to every one of them. Going through that name
	 * directly is ~10 s slower when IPv6 isn't routed. Blocking. */
	public string radio_browser_server () {
		if (radio_host == null) {
			radio_host = "de1.api.radio-browser.info";
			try {
				var resolver = Resolver.get_default ();
				var hosts = new GenericArray<string> ();
				foreach (var address in resolver.lookup_by_name ("all.api.radio-browser.info"))
					if (address.family == SocketFamily.IPV4)
						hosts.add (resolver.lookup_by_address (address));
				if (hosts.length > 0)
					radio_host = hosts[Random.int_range (0, hosts.length)];
			} catch (Error err) {
				warning ("Could not list the radio-browser.info servers: %s", err.message);
			}
		}
		return "https://" + radio_host;
	}

	/** Blocking: the stations found; null when the directory can't be reached */
	public Gee.List<Result>? search (Directory directory, Query q) {
		// q is built for this one search: what the server already filtered is cleared before filtering here
		switch (directory) {
		case Directory.SHOUTCAST:
			string form;
			string url = shoutcast_request (q, out form);
			uint status;
			var found = parse_shoutcast (Http.send ("POST", url, "application/x-www-form-urlencoded", form, null, out status));
			if (found == null)
				return null;
			if (q.text == "")
				q.genre = "";
			return filter (found, q, MAX_RESULTS);
		case Directory.LAUT_FM:
			string body;
			if (q.text != "") {
				// laut.fm's own search finds nothing: its station names are matched here instead
				var names = lautfm_matches (cached ("lautfm-names.json", "https://api.laut.fm/station_names", "["), q.text, 100);
				if (names.length == 0)
					return new Gee.ArrayList<Result> ();
				for (int i = 0; i < names.length; i++)
					names[i] = Uri.escape_string (names[i], null, false);
				body = Http.fetch ("https://api.laut.fm/stations/" + string.joinv (",", names));
				q.text = "";
			}
			else if (q.genre != "") {
				body = Http.fetch ("https://api.laut.fm/stations/genre/" + Uri.escape_string (q.genre, null, false) + "?limit=100");
				q.genre = "";
			}
			else
				return new Gee.ArrayList<Result> ();
			var found = parse_lautfm (body);
			return (found != null) ? filter (found, q, MAX_RESULTS) : null;
		case Directory.ICECAST:
			cache_lock.lock ();
			if (icecast == null) {
				string xml = cached ("icecast-yp.xml", "https://dir.xiph.org/yp.xml", "<directory");
				if (xml != "")
					icecast = parse_icecast (xml.make_valid ());
			}
			var all = icecast;
			cache_lock.unlock ();
			return (all != null) ? filter (all, q, MAX_RESULTS) : null;
		default:
			Gee.List<Result>? found = null;
			foreach (var path in radio_browser_searches (q)) {
				var some = parse_radio_browser (Http.fetch (radio_browser_server () + path));
				if (some == null)
					continue;
				if (found == null)
					found = some;
				else
					found.add_all (some);
			}
			return found;
		}
	}

	/** Blocking: a filter's values, list being "countries", "languages", "genres" or "states" (of country, by name) */
	public Gee.List<Choice> choices (Directory directory, string list, string country = "") {
		string body = "";
		string value = "name";
		string? count = "stationcount";
		if (directory == Directory.RADIO_BROWSER) {
			string server = radio_browser_server () + "/json/";
			if (list == "countries") {
				body = Http.fetch (server + "countries?hidebroken=true&order=name");
				value = "iso_3166_1";
			}
			else if (list == "states")
				body = Http.fetch (server + "states/" + Uri.escape_string (country, null, false) + "/?hidebroken=true&order=name");
			else if (list == "languages")
				body = Http.fetch (server + "languages?hidebroken=true&order=stationcount&reverse=true&limit=200");
			else if (list == "genres")
				body = Http.fetch (server + "tags?hidebroken=true&order=stationcount&reverse=true&limit=300");
		}
		else if (directory == Directory.LAUT_FM && list == "genres") {
			body = Http.fetch ("https://api.laut.fm/genres");
			count = null; // it gives a score, not a number of stations
		}
		else if (list == "genres") {
			var fixed = new Gee.ArrayList<Choice> ();
			foreach (var genre in (directory == Directory.SHOUTCAST) ? SHOUTCAST_GENRES : ICECAST_GENRES)
				fixed.add (new Choice () { name = genre, value = genre });
			return fixed;
		}
		return parse_choices (body, value, count) ?? new Gee.ArrayList<Choice> ();
	}

	/** Blocking: the address to play; a playlist (SHOUTcast's) gives its first stream, "" when it can't be read */
	public string stream_of (string url) {
		return is_playlist (url) ? first_stream (Http.fetch (url)) : url;
	}

	/** radio-browser searches (paths on its server) for a query */
	public string[] radio_browser_searches (Query q) {
		var sb = new StringBuilder ("/json/stations/search?hidebroken=true&limit=100&order=" + q.order);
		if (q.order != "name" && q.order != "random")
			sb.append ("&reverse=true");
		add_parameter (sb, "countrycode", q.country);
		add_parameter (sb, "state", q.state, true);
		add_parameter (sb, "language", q.language, true);
		add_parameter (sb, "codec", q.codec);
		if (q.min_bitrate > 0)
			sb.append_printf ("&bitrateMin=%d", q.min_bitrate);
		if (q.https_only)
			sb.append ("&is_https=true");
		if (q.genre != "") {
			add_parameter (sb, "tag", q.genre, true);
			add_parameter (sb, "name", q.text);
			return { sb.str };
		}
		if (q.text == "")
			return { sb.str };
		// a word like "jazz" is more often a tag than part of a name
		string text = Uri.escape_string (q.text, null, false);
		return { sb.str + "&name=" + text, sb.str + "&tag=" + text };
	}

	static void add_parameter (StringBuilder sb, string name, string value, bool exact = false) {
		if (value == "")
			return;
		sb.append_printf ("&%s=%s", name, Uri.escape_string (value, null, false));
		if (exact)
			sb.append_printf ("&%sExact=true", name);
	}

	/** The stations in a radio-browser answer; null when it is something else */
	public Gee.List<Result>? parse_radio_browser (string body) {
		var items = Http.json_objects (body);
		if (items == null)
			return null;
		var found = new Gee.ArrayList<Result> ();
		foreach (var o in items) {
			var r = new Result ();
			r.name = str (o, "name").strip ();
			r.url = (str (o, "url_resolved") != "") ? str (o, "url_resolved") : str (o, "url");
			r.country = str (o, "country");
			r.tags = str (o, "tags").replace (",", ", ");
			r.genre = first_word (str (o, "tags"), ",");
			r.codec = str (o, "codec");
			r.bitrate = (int) num (o, "bitrate");
			add_result (found, r);
		}
		return found;
	}

	/** The values in a list answer (countries, tags, genres...); null when it is something else */
	public Gee.List<Choice>? parse_choices (string body, string value_member, string? count_member) {
		var items = Http.json_objects (body);
		if (items == null)
			return null;
		var found = new Gee.ArrayList<Choice> ();
		foreach (var o in items) {
			var c = new Choice ();
			c.name = str (o, "name").strip ();
			c.value = str (o, value_member);
			if (count_member != null)
				c.count = (int) num (o, count_member);
			if (c.name != "" && c.value != "")
				found.add (c);
		}
		return found;
	}

	/** The SHOUTcast page asked (a POST of form): a search, a genre, or its most listened stations */
	public string shoutcast_request (Query q, out string form) {
		if (q.text != "") {
			form = "query=" + Uri.escape_string (q.text, null, false);
			return SHOUTCAST + "/Search/UpdateSearch";
		}
		if (q.genre != "") {
			form = "genrename=" + Uri.escape_string (q.genre, null, false);
			return SHOUTCAST + "/Home/BrowseByGenre";
		}
		form = "";
		return SHOUTCAST + "/Home/Top";
	}

	public Gee.List<Result>? parse_shoutcast (string body) {
		var items = Http.json_objects (body);
		if (items == null)
			return null;
		var found = new Gee.ArrayList<Result> ();
		foreach (var o in items) {
			var r = new Result ();
			r.name = str (o, "Name").strip ();
			if (num (o, "ID") > 0)
				r.url = "https://yp.shoutcast.com/sbin/tunein-station.m3u?id=%lld".printf (num (o, "ID"));
			r.codec = codec_of (str (o, "Format"));
			r.bitrate = (int) num (o, "Bitrate");
			r.genre = r.tags = str (o, "Genre");
			add_result (found, r);
		}
		return found;
	}

	/** laut.fm station names (its station_names list) like text, the closest first: same, starting with it, holding it */
	public string[] lautfm_matches (string names_json, string text, int max) {
		string key = squash (text);
		var parser = new Json.Parser ();
		try {
			parser.load_from_data (names_json);
		} catch (Error err) {
			return {};
		}
		unowned Json.Node? root = parser.get_root ();
		if (key == "" || root == null || root.get_node_type () != Json.NodeType.ARRAY)
			return {};
		string[] same = {}, starting = {}, holding = {};
		foreach (unowned Json.Node node in root.get_array ().get_elements ()) {
			if (node.get_value_type () != typeof (string))
				continue;
			string name = node.get_string ();
			string squashed = squash (name);
			if (squashed == key)
				same += name;
			else if (squashed.has_prefix (key))
				starting += name;
			else if (key in squashed)
				holding += name;
		}
		string[] names = {};
		foreach (var name in same)
			names += name;
		foreach (var name in starting)
			names += name;
		foreach (var name in holding)
			names += name;
		return (names.length > max) ? names[0:max] : names;
	}

	/** Lower case letters and digits only: "Just Jazz" and "just-jazz" are both "justjazz" */
	static string squash (string text) {
		var sb = new StringBuilder ();
		unichar c;
		for (int i = 0; text.get_next_char (ref i, out c);)
			if (c.isalnum ())
				sb.append_unichar (c.tolower ());
		return sb.str;
	}

	public Gee.List<Result>? parse_lautfm (string body) {
		var items = Http.json_objects (body);
		if (items == null)
			return null;
		var found = new Gee.ArrayList<Result> ();
		foreach (var o in items) {
			var r = new Result ();
			r.name = (str (o, "display_name") != "") ? str (o, "display_name").strip () : str (o, "name");
			r.url = str (o, "stream_url");
			r.country = str (o, "location");
			string[] genres = {};
			if (o.has_member ("genres") && o.get_member ("genres").get_node_type () == Json.NodeType.ARRAY)
				foreach (unowned Json.Node genre in o.get_array_member ("genres").get_elements ())
					if (genre.get_value_type () == typeof (string))
						genres += genre.get_string ();
			r.tags = string.joinv (", ", genres);
			r.genre = (genres.length > 0) ? genres[0] : "";
			add_result (found, r);
		}
		return found;
	}

	/** The stations in Icecast's yp.xml that give their address (~12k of ~32k) */
	public Gee.List<Result> parse_icecast (string xml) {
		return new IcecastReader ().read (xml);
	}

	class IcecastReader {
		const MarkupParser PARSER = { start, end, text, null, null };
		Gee.ArrayList<Result> found = new Gee.ArrayList<Result> ();
		Result? entry = null;
		StringBuilder content = new StringBuilder ();

		public Gee.List<Result> read (string xml) {
			var context = new MarkupParseContext (PARSER, 0, this, null);
			try {
				context.parse (xml, -1);
				context.end_parse ();
			} catch (MarkupError err) {
				warning ("The Icecast directory was read up to an error: %s", err.message);
			}
			return found;
		}

		void start (MarkupParseContext context, string name, string[] attribute_names, string[] attribute_values) throws MarkupError {
			if (name == "entry")
				entry = new Result ();
			content.truncate ();
		}

		void text (MarkupParseContext context, string text, size_t length) throws MarkupError {
			content.append_len (text, (ssize_t) length);
		}

		void end (MarkupParseContext context, string name) throws MarkupError {
			if (entry == null)
				return;
			string value = content.str.strip ();
			switch (name) {
			case "server_name":
				entry.name = value;
				break;
			case "listen_url":
				entry.url = value;
				break;
			case "server_type":
				entry.codec = codec_of (value);
				break;
			case "bitrate":
				entry.bitrate = int.parse (value);
				break;
			case "genre":
				entry.tags = value;
				entry.genre = first_word (value, " ,");
				break;
			case "entry":
				add_result (found, entry);
				entry = null;
				break;
			}
		}
	}

	/** The stations matching a query, at most max: a word in their name or tags, a genre in their tags... */
	public Gee.List<Result> filter (Gee.List<Result> all, Query q, int max) {
		string text = q.text.casefold ();
		string genre = q.genre.casefold ();
		var found = new Gee.ArrayList<Result> ();
		foreach (var r in all) {
			if (found.size >= max)
				break;
			if (text != "" && !(text in r.name.casefold ()) && !(text in r.tags.casefold ()))
				continue;
			if ((genre != "" && !(genre in r.tags.casefold ())) || (q.codec != "" && r.codec != q.codec) || r.bitrate < q.min_bitrate)
				continue;
			found.add (r);
		}
		return found;
	}

	/** A stream's type as radio-browser names its codec */
	static string codec_of (string mime) {
		switch (mime.down ()) {
		case "audio/mpeg":
		case "audio/mp3":
			return "MP3";
		case "audio/aacp":
			return "AAC+";
		case "audio/aac":
			return "AAC";
		case "application/ogg":
		case "audio/ogg":
		case "audio/opus":
			return "OGG";
		case "audio/flac":
			return "FLAC";
		default:
			return "";
		}
	}

	/** .m3u and .pls are lists of streams; .m3u8 is HLS, played as it is */
	public bool is_playlist (string url) {
		string path = url.split ("?")[0].down ();
		return path.has_suffix (".m3u") || path.has_suffix (".pls");
	}

	/** The first address in an .m3u or .pls; "" when there is none */
	public string first_stream (string playlist) {
		foreach (unowned string line in playlist.split ("\n")) {
			string address = line.strip ();
			if (address.down ().has_prefix ("file") && "=" in address)
				address = address.substring (address.index_of ("=") + 1).strip ();
			if (address.has_prefix ("http://") || address.has_prefix ("https://"))
				return address;
		}
		return "";
	}

	/* url's answer, kept a day in ~/.cache/beatbox/<file>. The old copy when the server can't be
	 * reached or answers something without marker at its start (an error page) */
	static string cached (string file, string url, string marker) {
		string path = Path.build_filename (Environment.get_user_cache_dir (), "beatbox", file);
		string old = "";
		try {
			var info = File.new_for_path (path).query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
			FileUtils.get_contents (path, out old);
			if (new DateTime.now_utc ().to_unix () - info.get_modification_date_time ().to_unix () < DAY)
				return old;
		} catch (Error err) {
			// not downloaded yet
		}
		string body = Http.fetch (url);
		int at = body.index_of (marker);
		if (at < 0 || at > 100)
			return old;
		try {
			DirUtils.create_with_parents (Path.get_dirname (path), 0755);
			FileUtils.set_contents (path, body);
		} catch (Error err) {
			warning ("Could not keep %s: %s", path, err.message);
		}
		return body;
	}

	static void add_result (Gee.List<Result> found, Result r) {
		if (r.name != "" && r.url != "")
			found.add (r);
	}

	static string first_word (string text, string separators) {
		foreach (unowned string word in text.split_set (separators))
			if (word.strip () != "")
				return word.strip ();
		return "";
	}

	static string str (Json.Object o, string member) {
		unowned Json.Node? node = o.get_member (member);
		return (node != null && node.get_value_type () == typeof (string)) ? node.get_string () : "";
	}

	static int64 num (Json.Object o, string member) {
		unowned Json.Node? node = o.get_member (member);
		return (node != null && node.get_node_type () == Json.NodeType.VALUE) ? node.get_int () : 0;
	}
}
