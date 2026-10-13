/*
 * Finds internet radio stations and podcasts in public directories:
 *  - radio stations: radio-browser.info, SHOUTcast, laut.fm and Icecast (core: RadioDirectories.vala)
 *  - the Apple Podcasts directory (Apple's search service, no API key)
 */

using Gtk;

public class BeatBox.DirectoryDialog : Dialog {
	public enum Kind { RADIO, PODCAST }

	const string PODCAST_API = "https://itunes.apple.com/search?media=podcast&limit=50";

	enum Col { NAME, DETAIL, EXTRA, URL, GENRE, ADDED, COUNTRY }

	Kind kind;
	SearchEntry entry;
	Gtk.ListStore store;
	TreeView view;
	TreeViewColumn detail_column;
	Spinner spinner;
	Label status;
	Label source;
	Widget add_btn;
	uint serial = 0;
	bool closed = false;

	// radio only
	Radio.Directory directory = Radio.Directory.RADIO_BROWSER;
	ComboBoxText directories;
	ComboBoxText country;
	ComboBoxText state;
	ComboBoxText language;
	ComboBoxText genre;
	ComboBoxText codec;
	ComboBoxText bitrate;
	ComboBoxText order;
	CheckButton https;
	bool filling = false;

	// the filters' values for this session, by directory/list/country; filled on the main loop only
	static Gee.HashMap<string, Gee.List<Radio.Choice>>? lists = null;

	public DirectoryDialog (Kind kind) {
		Object (title: (kind == Kind.RADIO) ? _("Find Radio Stations") : _("Find Podcasts"),
		        transient_for: App.window, modal: true, destroy_with_parent: true);
		this.kind = kind;
		set_default_size ((kind == Kind.RADIO) ? 860 : 720, 560);
		destroy.connect (() => { closed = true; });

		entry = new SearchEntry ();
		entry.placeholder_text = (kind == Kind.RADIO) ? _("Station name, city or genre (jazz, news, rock…)")
		                                              : _("Podcast name, author or topic");
		entry.activate.connect (() => search (entry.text.strip ()));
		spinner = new Spinner ();
		var top = new Box (Orientation.HORIZONTAL, 6);
		entry.hexpand = true;
		top.add(entry);
		top.add(spinner);

		store = new Gtk.ListStore (7, typeof (string), typeof (string), typeof (string), typeof (string), typeof (string), typeof (bool), typeof (string));
		view = new TreeView.with_model (store);
		view.get_style_context ().add_class ("tracklist");
		string[] headers = (kind == Kind.RADIO) ? new string[] { _("Station"), _("Country"), _("Genre") }
		                                        : new string[] { _("Podcast"), _("Author"), _("Genre") };
		for (int i = 0; i < 3; i++) {
			var cell = new CellRendererText ();
			cell.ellipsize = Pango.EllipsizeMode.END;
			var col = new TreeViewColumn.with_attributes (headers[i], cell, "text", i);
			col.resizable = true;
			col.expand = (i != 1);
			if (i == 1)
				col.fixed_width = 140;
			col.sizing = TreeViewColumnSizing.FIXED;
			col.set_cell_data_func (cell, (c, r, model, iter) => {
				bool added;
				model.get (iter, Col.ADDED, out added);
				((CellRendererText)r).weight = added ? Pango.Weight.BOLD : Pango.Weight.NORMAL;
			});
			view.append_column (col);
		}
		detail_column = view.get_column (1);
		view.row_activated.connect (() => add_selected ());
		var scroll = new ScrolledWindow (null, null);
		scroll.shadow_type = ShadowType.IN;
		scroll.add (view);

		status = new Label ("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.END;
		source = new Label (_("Podcasts from the Apple Podcasts directory."));
		source.xalign = 0;
		source.get_style_context ().add_class ("dim-label");

		var box = get_content_area ();
		box.spacing = 8;
		box.margin = 12;
		box.add(top);
		if (kind == Kind.RADIO)
			box.add (build_filters (top));
		scroll.vexpand = true;
		box.add(scroll);
		box.add(status);
		box.add(source);

		add_button (_("Close"), ResponseType.CLOSE);
		add_btn = add_button ((kind == Kind.RADIO) ? _("Add Station") : _("Subscribe"), ResponseType.APPLY);
		add_btn.sensitive = false;
		view.get_selection ().changed.connect (() => {
			add_btn.sensitive = view.get_selection ().count_selected_rows () > 0;
		});
		response.connect ((id) => {
			if (id == ResponseType.APPLY)
				add_selected ();
			else
				destroy ();
		});

		show_all ();
		entry.grab_focus ();

		// Something to start with: the most voted stations of the user's country
		if (kind == Kind.RADIO)
			directory_changed ();
		else
			status.label = _("Type a name or topic and press Enter.");
	}

	/** The directory menu (before the search box) and the filters below it */
	Widget build_filters (Box top) {
		directories = new ComboBoxText ();
		directories.append_text ("radio-browser.info");
		directories.append_text ("SHOUTcast");
		directories.append_text ("laut.fm");
		directories.append_text ("Icecast");
		directories.active = 0;
		directories.changed.connect (() => {
			directory = (Radio.Directory) directories.active;
			directory_changed ();
		});
		top.pack_start (directories, false, false);
		top.reorder_child (directories, 0);

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
		box.add (https);
		filters.add (box);
		filling = false;
		return filters;
	}

	ComboBoxText add_filter (FlowBox filters, string title, bool typing) {
		var combo = typing ? new ComboBoxText.with_entry () : new ComboBoxText ();
		combo.append ("", _("Any"));
		if (!typing)
			combo.active_id = "";
		else {
			// a few hundred countries, languages or genres: typed, with completion
			var typed = (Entry) combo.get_child ();
			typed.width_chars = 14;
			typed.placeholder_text = _("Any");
			var completion = new EntryCompletion ();
			completion.model = combo.model;
			completion.text_column = 0;
			completion.match_selected.connect ((model, iter) => {
				string id;
				model.get (iter, 1, out id);
				combo.active_id = id;
				return true;
			});
			typed.completion = completion;
			typed.activate.connect (() => filter_changed (combo));
		}
		combo.changed.connect (() => {
			if (combo.active < 0)
				return;
			// "Any" leaves the box empty, showing it as placeholder: typing doesn't append to it
			if (combo.has_entry && combo.active_id == "")
				((Entry) combo.get_child ()).text = "";
			filter_changed (combo);
		});
		var box = new Box (Orientation.HORIZONTAL, 4);
		box.add (new Label (title));
		box.add (combo);
		filters.add (box);
		return combo;
	}

	void filter_changed (ComboBoxText combo) {
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
	void load_list (ComboBoxText combo, string list, string country_name = "") {
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
	void fill (ComboBoxText combo, Gee.List<Radio.Choice> choices) {
		string chosen = value_of (combo, true);
		filling = true;
		combo.remove_all ();
		combo.append ("", _("Any"));
		foreach (var c in choices) {
			// radio-browser's languages and tags are lower case
			string name = c.name.get_char ().totitle ().to_string () + c.name.substring (c.name.index_of_nth_char (1));
			combo.append (c.value, (c.count > 0) ? "%s (%d)".printf (name, c.count) : name);
		}
		if (!combo.set_active_id (chosen)) {
			if (combo.has_entry)
				((Entry) combo.get_child ()).text = chosen;
			else
				combo.active_id = "";
		}
		filling = false;
		if (combo == country)
			load_states ();
	}

	/** What a filter asks for: the item chosen, the first one starting with what was typed or, free, the text itself */
	string value_of (ComboBoxText combo, bool free = false) {
		if (combo.active_id != null)
			return combo.active_id;
		if (!combo.has_entry)
			return "";
		string typed = ((Entry) combo.get_child ()).text.strip ();
		if (typed == "")
			return "";
		string key = typed.casefold ();
		string? found = null;
		combo.model.foreach ((model, path, iter) => {
			string text, id;
			model.get (iter, 0, out text, 1, out id);
			if (id != "" && text.casefold ().has_prefix (key))
				found = id;
			return found != null;
		});
		return found ?? (free ? typed : "");
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
			store.clear ();
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
		store.clear ();
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
			TreeIter iter;
			store.append (out iter);
			store.set (iter, Col.NAME, r.name, Col.DETAIL, (r.country != "") ? r.country : format, Col.EXTRA, extra,
			           Col.URL, r.url, Col.GENRE, r.genre, Col.ADDED, already_added (r.url), Col.COUNTRY, r.country);
			count++;
		}
		if (count == 0)
			status.label = (term != "") ? _("Nothing found for “%s”.").printf (term) : _("No stations match these filters.");
		else
			status.label = ngettext ("%d result. Double click to add.", "%d results. Double click to add.", count).printf (count);
	}

	void show_podcasts (string body, string term) {
		spinner.stop ();
		store.clear ();
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
			TreeIter iter;
			store.append (out iter);
			store.set (iter, Col.NAME, name, Col.DETAIL, str (o, "artistName"), Col.EXTRA, genre,
			           Col.URL, url, Col.GENRE, genre, Col.ADDED, already_added (url), Col.COUNTRY, "");
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
		TreeModel model;
		TreeIter iter;
		if (!view.get_selection ().get_selected (out model, out iter))
			return;
		string name, url, genre, country;
		bool added;
		model.get (iter, Col.NAME, out name, Col.URL, out url, Col.GENRE, out genre, Col.ADDED, out added, Col.COUNTRY, out country);
		if (added) {
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
						store.set (iter, Col.ADDED, true);
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
		store.set (iter, Col.ADDED, true);
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
	public static void add_station_by_url () {
		var dialog = new Dialog.with_buttons (_("Add Station"), App.window, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
		                                      _("Cancel"), ResponseType.CANCEL, _("Add"), ResponseType.OK);
		var name = new Entry () { placeholder_text = _("My favourite station"), activates_default = true };
		var url = new Entry () { placeholder_text = "https://…", activates_default = true, width_chars = 40 };
		var grid = new Grid () { row_spacing = 8, column_spacing = 8, margin = 12 };
		grid.attach (new Label (_("Name:")) { xalign = 1 }, 0, 0);
		grid.attach (name, 1, 0);
		grid.attach (new Label (_("Stream address:")) { xalign = 1 }, 0, 1);
		grid.attach (url, 1, 1);
		var hint = new Label (_("The address of the audio stream itself (often ending in .mp3, .aac or /stream).\nTo add a .pls or .m3u file use “Import File…”."));
		hint.get_style_context ().add_class ("dim-label");
		grid.attach (hint, 0, 2, 2, 1);
		dialog.get_content_area ().add (grid);
		dialog.set_default_response (ResponseType.OK);
		var ok = dialog.get_widget_for_response (ResponseType.OK);
		ok.sensitive = false;
		url.changed.connect (() => {
			var u = url.text.strip ();
			ok.sensitive = (u.has_prefix ("http://") || u.has_prefix ("https://")) && !(" " in u);
		});
		dialog.show_all ();
		if (dialog.run () == ResponseType.OK) {
			var n = name.text.strip ();
			add_station (n != "" ? n : url.text.strip (), url.text.strip ());
		}
		dialog.destroy ();
	}
}
