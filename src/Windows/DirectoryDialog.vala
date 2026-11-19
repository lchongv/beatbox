/*
 * Finds internet radio stations and podcasts in public directories:
 *  - radio stations: radio-browser.info, SHOUTcast, laut.fm and Icecast (core: RadioDirectories.vala)
 *  - the Apple Podcasts directory (Apple's search service, no API key)
 */

using Gtk;

public class BeatBox.DirectoryDialog : ButtonDialog {
	public enum Kind { RADIO, PODCAST }

	const string PODCAST_API = "https://itunes.apple.com/search?media=podcast&limit=50";

	// a result row's cells (its check box: already added)
	enum Col { NAME, DETAIL, EXTRA, URL, GENRE, COUNTRY }

	Kind kind;
	SearchEntry entry;
	SimpleTable results;
	ColumnViewColumn detail_column;
	Spinner spinner;
	Label status;
	Label source;
	Widget add_btn;
	uint serial = 0;
	bool closed = false;

	// radio only
	Radio.Directory directory = Radio.Directory.RADIO_BROWSER;
	ChoiceBox directories;
	ChoiceBox country;
	ChoiceBox state;
	ChoiceBox language;
	ChoiceBox genre;
	ChoiceBox codec;
	ChoiceBox bitrate;
	ChoiceBox order;
	CheckButton https;
	bool filling = false;

	// the filters' values for this session, by directory/list/country; filled on the main loop only
	static Gee.HashMap<string, Gee.List<Radio.Choice>>? lists = null;

	public DirectoryDialog (Kind kind) {
		base ((kind == Kind.RADIO) ? _("Find Radio Stations") : _("Find Podcasts"), App.window);
		resizable = true;
		this.kind = kind;
		set_default_size ((kind == Kind.RADIO) ? 860 : 720, 560);
		close_request.connect (() => { closed = true; return false; });

		entry = new SearchEntry ();
		entry.placeholder_text = (kind == Kind.RADIO) ? _("Station name, city or genre (jazz, news, rock…)")
		                                              : _("Podcast name, author or topic");
		entry.activate.connect (() => search (entry.text.strip ()));
		spinner = new Spinner ();
		var top = new Box (Orientation.HORIZONTAL, 6);
		entry.hexpand = true;
		top.append(entry);
		top.append(spinner);

		results = new SimpleTable ();
		results.view.add_css_class ("tracklist");
		string[] headers = (kind == Kind.RADIO) ? new string[] { _("Station"), _("Country"), _("Genre") }
		                                        : new string[] { _("Podcast"), _("Author"), _("Genre") };
		for (int i = 0; i < 3; i++) {
			int cell = i;
			var col = results.add_custom_column (headers[i], (item) => {
				var label = new Label (null);
				label.xalign = 0;
				label.ellipsize = Pango.EllipsizeMode.END;
				item.child = label;
			}, (item, row) => {
				var label = (Label) item.child;
				label.label = row.cells[cell];
				// the ones already in the library in bold
				var attrs = new Pango.AttrList ();
				if (row.checked)
					attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
				label.attributes = attrs;
			}, i != 1);
			if (i == 1)
				col.fixed_width = 140;
		}
		detail_column = results.view.columns.get_item (1) as ColumnViewColumn;
		results.activated.connect (() => add_selected ());
		var scroll = new ScrolledWindow ();
		scroll.has_frame = true;
		scroll.set_child (results.view);

		status = new Label ("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.END;
		source = new Label (_("Podcasts from the Apple Podcasts directory."));
		source.xalign = 0;
		source.add_css_class ("dim-label");

		var box = content_area;
		box.spacing = 8;
		box.append (top);
		if (kind == Kind.RADIO)
			box.append (build_filters (top));
		scroll.vexpand = true;
		box.append (AquaScroll.wrap(scroll));
		box.append (status);
		box.append (source);

		add_button (_("Close"), ButtonDialog.CLOSE);
		add_btn = add_button ((kind == Kind.RADIO) ? _("Add Station") : _("Subscribe"), ButtonDialog.APPLY);
		add_btn.sensitive = false;
		results.selection.selection_changed.connect (() => {
			add_btn.sensitive = results.selected_row () != null;
		});
		response.connect ((id) => {
			if (id == ButtonDialog.APPLY)
				add_selected ();
			else
				destroy ();
		});

		present ();
		entry.grab_focus ();

		// Something to start with: the most voted stations of the user's country
		if (kind == Kind.RADIO)
			directory_changed ();
		else
			status.label = _("Type a name or topic and press Enter.");
	}

	/** The directory menu (before the search box) and the filters below it */
	Widget build_filters (Box top) {
		directories = new ChoiceBox ();
		directories.hexpand = false;
		directories.append_text ("radio-browser.info");
		directories.append_text ("SHOUTcast");
		directories.append_text ("laut.fm");
		directories.append_text ("Icecast");
		directories.active = 0;
		directories.changed.connect (() => {
			directory = (Radio.Directory) directories.active;
			directory_changed ();
		});
		top.prepend (directories);

		var filters = new FlowBox ();
		filters.selection_mode = SelectionMode.NONE;
		filters.column_spacing = 12;
		filters.row_spacing = 4;
		filters.max_children_per_line = 8;

		filling = true;
		country = add_filter (filters, _("Country:"), true);
		string cc = country_code ();
		if (cc != "") {
			country.append (cc, cc);
			country.active_id = cc;
		}
		state = add_filter (filters, _("Region:"), true);
		language = add_filter (filters, _("Language:"), true);
		genre = add_filter (filters, _("Genre:"), true);
		codec = add_filter (filters, _("Format:"), false);
		foreach (var name in new string[] { "MP3", "AAC", "AAC+", "OGG", "FLAC" })
			codec.append (name, name);
		bitrate = add_filter (filters, _("Quality:"), false);
		foreach (var kbps in new int[] { 64, 96, 128, 192, 256, 320 })
			bitrate.append (kbps.to_string (), _("%d kbps or more").printf (kbps));
		order = add_filter (filters, _("Sort by:"), false);
		order.remove_all ();
		order.append ("votes", _("Most voted"));
		order.append ("clickcount", _("Most played"));
		order.append ("clicktrend", _("Trending"));
		order.append ("name", _("Name"));
		order.append ("bitrate", _("Quality"));
		order.append ("random", _("Random"));
		order.active_id = "votes";
		https = new CheckButton.with_label (_("HTTPS only"));
		https.toggled.connect (() => search (entry.text.strip ()));
		var box = new Box (Orientation.HORIZONTAL, 0);
		box.append (https);
		filters.append (box);
		filling = false;
		return filters;
	}

	ChoiceBox add_filter (FlowBox filters, string title, bool typing) {
		var combo = typing ? new ChoiceBox.with_entry () : new ChoiceBox ();
		combo.append ("", _("Any"));
		if (!typing)
			combo.active_id = "";
		else {
			// a few hundred countries, languages or genres: typed, the matching ones listed below
			var typed = combo.entry;
			typed.width_chars = 14;
			typed.placeholder_text = _("Any");
			typed.activate.connect (() => filter_changed (combo));
		}
		combo.changed.connect (() => {
			if (combo.active < 0)
				return;
			// "Any" leaves the box empty, showing it as placeholder: typing doesn't append to it
			if (combo.has_entry && combo.active_id == "")
				combo.entry.text = "";
			filter_changed (combo);
		});
		var box = new Box (Orientation.HORIZONTAL, 4);
		box.append (new Label (title));
		box.append (combo);
		filters.append (box);
		return combo;
	}

	void filter_changed (ChoiceBox combo) {
		if (filling)
			return;
		if (combo == country)
			load_states ();
		search (entry.text.strip ());
	}

	/** The regions of the country chosen; radio-browser asks for them by the country's name */
	void load_states () {
		fill (state, new Gee.ArrayList<Radio.Choice> ());
		string code = value_of (country);
		foreach (var c in lists["0/countries/"] ?? new Gee.ArrayList<Radio.Choice> ())
			if (c.value == code)
				load_list (state, "states", c.name);
	}

	void directory_changed () {
		bool radio_browser = (directory == Radio.Directory.RADIO_BROWSER);
		// each filter sits in a box with its label, in the FlowBox's child
		foreach (Widget filter in new Widget[] { country, state, language, order, https })
			filter.get_parent ().get_parent ().visible = radio_browser;
		foreach (Widget filter in new Widget[] { codec, bitrate })
			filter.get_parent ().get_parent ().visible = (directory != Radio.Directory.LAUT_FM);

		load_list (genre, "genres");
		if (radio_browser) {
			load_list (country, "countries");
			load_list (language, "languages");
		}
		detail_column.title = (directory == Radio.Directory.SHOUTCAST || directory == Radio.Directory.ICECAST) ? _("Format") : _("Country");
		string[] sources = { _("Stations from radio-browser.info, a free community directory."),
		                     _("Stations from the SHOUTcast directory."),
		                     _("Stations made by laut.fm’s listeners."),
		                     _("Stations from the Icecast directory (dir.xiph.org).") };
		source.label = sources[(int) directory];
		search (entry.text.strip ());
	}

	/** A filter's values from the directory, once per session */
	void load_list (ChoiceBox combo, string list, string country_name = "") {
		if (lists == null)
			lists = new Gee.HashMap<string, Gee.List<Radio.Choice>> ();
		string key = "%d/%s/%s".printf ((int) directory, list, country_name);
		if (lists.has_key (key)) {
			fill (combo, lists[key]);
			return;
		}
		var from = directory;
		new Thread<void*> ("radio-filters", () => {
			var found = Radio.choices (from, list, country_name);
			Idle.add (() => {
				if (found.size > 0)
					lists[key] = found;
				if (!closed && directory == from)
					fill (combo, found);
				return false;
			});
			return null;
		});
	}

	/** Puts a filter's values in its menu, keeping what was chosen or typed */
	void fill (ChoiceBox combo, Gee.List<Radio.Choice> choices) {
		string chosen = value_of (combo, true);
		filling = true;
		combo.remove_all ();
		combo.append ("", _("Any"));
		foreach (var c in choices) {
			// radio-browser's languages and tags are lower case
			string name = c.name.get_char ().totitle ().to_string () + c.name.substring (c.name.index_of_nth_char (1));
			combo.append (c.value, (c.count > 0) ? "%s (%d)".printf (name, c.count) : name);
		}
		if (!combo.select_id (chosen)) {
			if (combo.has_entry)
				combo.entry.text = chosen;
			else
				combo.active_id = "";
		}
		filling = false;
		if (combo == country)
			load_states ();
	}

	/** What a filter asks for: the item chosen, the first one starting with what was typed or, free, the text itself */
	string value_of (ChoiceBox combo, bool free = false) {
		if (combo.active_id != null)
			return combo.active_id;
		if (!combo.has_entry)
			return "";
		string typed = combo.entry.text.strip ();
		if (typed == "")
			return "";
		string key = typed.casefold ();
		for (int i = 0; i < combo.n_items; i++) {
			string? id = combo.get_id (i);
			if (id != null && id != "" && combo.get_text (i).casefold ().has_prefix (key))
				return id;
		}
		return free ? typed : "";
	}

	/** Two-letter country of the user's locale (es_CL.UTF-8 → CL), or "" */
	static string country_code () {
		foreach (var name in Intl.get_language_names ()) {
			int u = name.index_of ("_");
			if (u > 0 && name.length >= u + 3)
				return name.substring (u + 1, 2).up ();
		}
		return "";
	}

	void search (string term) {
		if (filling)
			return;
		uint my_serial = ++serial;
		if (kind == Kind.PODCAST) {
			if (term == "")
				return;
			string cc = country_code ();
			string url = PODCAST_API + "&term=" + Uri.escape_string (term, null, false) + (cc != "" ? "&country=" + cc : "");
			spinner.start ();
			status.label = _("Searching…");
			new Thread<void*> ("directory-search", () => {
				string body = Http.fetch (url);
				Idle.add (() => {
					if (my_serial == serial)
						show_podcasts (body, term);
					return false;
				});
				return null;
			});
			return;
		}

		var q = new Radio.Query ();
		q.text = term;
		q.genre = value_of (genre, true);
		if (directory != Radio.Directory.LAUT_FM) {
			q.codec = value_of (codec);
			q.min_bitrate = int.parse (value_of (bitrate));
		}
		if (directory == Radio.Directory.RADIO_BROWSER) {
			q.country = value_of (country);
			q.state = value_of (state);
			q.language = value_of (language);
			q.order = value_of (order);
			q.https_only = https.active;
		}
		if (directory == Radio.Directory.LAUT_FM && term == "" && q.genre == "") {
			spinner.stop ();
			results.clear ();
			status.label = _("Choose a genre or type a station’s name.");
			return;
		}
		spinner.start ();
		status.label = (directory == Radio.Directory.ICECAST) ? _("Searching… the Icecast directory is downloaded once a day (9 MB).")
		                                                     : _("Searching…");
		var from = directory;
		new Thread<void*> ("directory-search", () => {
			var found = Radio.search (from, q);
			Idle.add (() => {
				if (my_serial == serial)
					show_stations (found, term);
				return false;
			});
			return null;
		});
	}

	void show_stations (Gee.List<Radio.Result>? found, string term) {
		spinner.stop ();
		results.clear ();
		if (found == null) {
			status.label = _("Could not reach the directory. Check your internet connection.");
			return;
		}
		var seen = new GenericSet<string> (str_hash, str_equal);
		int count = 0;
		foreach (var r in found) {
			if (r.url in seen)
				continue;
			seen.add (r.url);
			string format = "%s %s".printf (r.codec, (r.bitrate > 0) ? "%d kbps".printf (r.bitrate) : "").strip ();
			string extra = r.tags;
			if (r.bitrate > 0 && r.country != "") // without a country the format, bitrate included, takes its place
				extra = "%d kbps%s%s".printf (r.bitrate, extra != "" ? " · " : "", extra);
			results.add ({ r.name, (r.country != "") ? r.country : format, extra, r.url, r.genre, r.country })
			       .checked = already_added (r.url);
			count++;
		}
		if (count == 0)
			status.label = (term != "") ? _("Nothing found for “%s”.").printf (term) : _("No stations match these filters.");
		else
			status.label = ngettext ("%d result. Double click to add.", "%d results. Double click to add.", count).printf (count);
	}

	void show_podcasts (string body, string term) {
		spinner.stop ();
		results.clear ();
		var items = Http.json_objects (body, "results");
		if (items == null) {
			if (body != "")
				warning ("Unexpected answer from the directory: %.100s", body);
			status.label = _("Could not reach the directory. Check your internet connection.");
			return;
		}
		var seen = new GenericSet<string> (str_hash, str_equal);
		int count = 0;
		foreach (var o in items) {
			string name = str (o, "collectionName");
			string url = str (o, "feedUrl");
			string genre = str (o, "primaryGenreName");
			if (url == "" || name == "" || url in seen)
				continue;
			seen.add (url);
			results.add ({ name, str (o, "artistName"), genre, url, genre, "" }).checked = already_added (url);
			count++;
		}
		if (count == 0)
			status.label = _("Nothing found for “%s”.").printf (term);
		else
			status.label = ngettext ("%d result. Double click to add.", "%d results. Double click to add.", count).printf (count);
	}

	static string str (Json.Object o, string member) {
		return o.get_string_member_with_default (member, "");
	}

	bool already_added (string url) {
		var library = (kind == Kind.RADIO) ? App.library.station_library : App.library.podcast_library;
		foreach (var m in library.medias ())
			if (m.uri == url || m.rss_uri == url)
				return true;
		return false;
	}

	void add_selected () {
		var row = results.selected_row ();
		if (row == null)
			return;
		string name = row.cells[Col.NAME], url = row.cells[Col.URL], genre = row.cells[Col.GENRE], country = row.cells[Col.COUNTRY];
		if (row.checked) {
			status.label = _("“%s” is already in your library.").printf (name);
			return;
		}

		if (kind == Kind.PODCAST) {
			App.podcasts.parse_new_rss (url);
			status.label = _("Subscribing to “%s”… its episodes will appear in Podcasts.").printf (name);
		}
		else if (Radio.is_playlist (url)) {
			// SHOUTcast gives a playlist: its stream is looked up now
			status.label = _("Looking up the stream of “%s”…").printf (name);
			uint my_serial = serial;
			new Thread<void*> ("station-stream", () => {
				string stream = Radio.stream_of (url);
				Idle.add (() => {
					if (stream == "") {
						status.label = _("“%s” gave no stream to play.").printf (name);
						return false;
					}
					add_station (name, stream, genre, country);
					status.label = _("Added “%s” to Internet Radio.").printf (name);
					if (my_serial == serial)
						mark_added (row);
					return false;
				});
				return null;
			});
			return;
		}
		else {
			add_station (name, url, genre, country);
			status.label = _("Added “%s” to Internet Radio.").printf (name);
		}
		mark_added (row);
	}

	/** In bold from now on */
	void mark_added (TableRow row) {
		row.checked = true;
		uint position;
		if (results.rows.find (row, out position))
			results.changed (position);
	}

	public static void add_station (string name, string url, string genre = "", string host = "") {
		var station = new Station (url);
		station.name = name;
		station.genre = genre;
		if (host != "")
			station.host = host;
		var list = new Gee.LinkedList<Media> ();
		list.add (station);
		App.library.station_library.add_medias (list);
	}

	/** Small dialog to add a station from its stream address */
	public static async void add_station_by_url () {
		var dialog = new ButtonDialog (_("Add Station"), App.window);
		dialog.add_button (_("Cancel"), ButtonDialog.CANCEL);
		dialog.add_button (_("Add"), ButtonDialog.OK);
		var name = new Entry () { placeholder_text = _("My favourite station"), activates_default = true };
		var url = new Entry () { placeholder_text = "https://…", activates_default = true, width_chars = 40 };
		var grid = new Grid () { row_spacing = 8, column_spacing = 8, margin_top = 12, margin_bottom = 12, margin_start = 12, margin_end = 12 };
		grid.attach (new Label (_("Name:")) { xalign = 1 }, 0, 0);
		grid.attach (name, 1, 0);
		grid.attach (new Label (_("Stream address:")) { xalign = 1 }, 0, 1);
		grid.attach (url, 1, 1);
		var hint = new Label (_("The address of the audio stream itself (often ending in .mp3, .aac or /stream).\nTo add a .pls or .m3u file use “Import File…”."));
		hint.add_css_class ("dim-label");
		grid.attach (hint, 0, 2, 2, 1);
		dialog.content_area.append (grid);
		dialog.set_default_response (ButtonDialog.OK);
		var ok = dialog.get_widget_for_response (ButtonDialog.OK);
		ok.sensitive = false;
		url.changed.connect (() => {
			var u = url.text.strip ();
			ok.sensitive = (u.has_prefix ("http://") || u.has_prefix ("https://")) && !(" " in u);
		});
		if ((yield dialog.run ()) == ButtonDialog.OK) {
			var n = name.text.strip ();
			add_station (n != "" ? n : url.text.strip (), url.text.strip ());
		}
		dialog.destroy ();
	}
}
