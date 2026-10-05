/*
 * Finds internet radio stations and podcasts in public directories:
 *  - radio-browser.info (community database of ~50k stations, no API key)
 *  - the Apple Podcasts directory (Apple's search service, no API key)
 */

using Gtk;

public class BeatBox.DirectoryDialog : Dialog {
	public enum Kind { RADIO, PODCAST }

	const string RADIO_QUERY = "/json/stations/search?hidebroken=true&order=votes&reverse=true&limit=100";
	const string PODCAST_API = "https://itunes.apple.com/search?media=podcast&limit=50";

	enum Col { NAME, DETAIL, EXTRA, URL, GENRE, ADDED }

	Kind kind;
	SearchEntry entry;
	Gtk.ListStore store;
	TreeView view;
	Spinner spinner;
	Label status;
	Widget add_btn;
	uint serial = 0;

	static string? radio_host = null;

	/* radio-browser.info asks clients to pick one of its mirrors: the
	 * all.api name resolves to every one of them. Going through that name
	 * directly is ~10 s slower when IPv6 isn't routed. Blocking. */
	static string radio_api () {
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
		return "https://" + radio_host + RADIO_QUERY;
	}

	public DirectoryDialog (Kind kind) {
		Object (title: (kind == Kind.RADIO) ? _("Find Radio Stations") : _("Find Podcasts"),
		        transient_for: App.window, modal: true, destroy_with_parent: true);
		this.kind = kind;
		set_default_size (720, 520);

		entry = new SearchEntry ();
		entry.placeholder_text = (kind == Kind.RADIO) ? _("Station name, city or genre (jazz, news, rock…)")
		                                              : _("Podcast name, author or topic");
		entry.activate.connect (() => search (entry.text.strip ()));
		spinner = new Spinner ();
		var top = new Box (Orientation.HORIZONTAL, 6);
		top.pack_start (entry, true, true, 0);
		top.add(spinner);

		store = new Gtk.ListStore (6, typeof (string), typeof (string), typeof (string), typeof (string), typeof (string), typeof (bool));
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
		view.row_activated.connect (() => add_selected ());
		var scroll = new ScrolledWindow (null, null);
		scroll.shadow_type = ShadowType.IN;
		scroll.add (view);

		status = new Label ("");
		status.xalign = 0;
		status.ellipsize = Pango.EllipsizeMode.END;
		var source = new Label ((kind == Kind.RADIO) ? _("Stations from radio-browser.info, a free community directory.")
		                                             : _("Podcasts from the Apple Podcasts directory."));
		source.xalign = 0;
		source.get_style_context ().add_class ("dim-label");

		var box = get_content_area ();
		box.spacing = 8;
		box.margin = 12;
		box.add(top);
		box.pack_start (scroll, true, true, 0);
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
			search ("");
		else
			status.label = _("Type a name or topic and press Enter.");
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
		uint my_serial = ++serial;
		string cc = country_code ();
		string q = Uri.escape_string (term, null, false);
		string[] urls;
		if (kind == Kind.PODCAST) {
			if (term == "")
				return;
			urls = { PODCAST_API + "&term=" + q + (cc != "" ? "&country=" + cc : "") };
		}
		else if (term == "") {
			urls = { "&countrycode=" + cc };
		}
		else {
			// a word like "jazz" is more often a tag than part of a name
			urls = { "&name=" + q, "&tag=" + q };
		}

		spinner.start ();
		status.label = _("Searching…");
		new Thread<void*> ("directory-search", () => {
			string[] bodies = {};
			foreach (var url in urls)
				bodies += Http.fetch ((kind == Kind.RADIO) ? radio_api () + url : url);
			Idle.add (() => {
				if (my_serial == serial)
					show_results (bodies, term);
				return false;
			});
			return null;
		});
	}

	void show_results (string[] bodies, string term) {
		spinner.stop ();
		store.clear ();
		var seen = new GenericSet<string> (str_hash, str_equal);
		int count = 0;
		bool failed = true;

		foreach (var body in bodies) {
			if (body == "")
				continue;
			var items = Http.json_objects (body, (kind == Kind.RADIO) ? null : "results");
			if (items == null) {
				warning ("Unexpected answer from the directory: %.100s", body);
				continue;
			}
			failed = false;
			foreach (var o in items) {
				string name, detail, extra, url, genre;
				if (kind == Kind.RADIO) {
					name = str (o, "name").strip ();
					url = str (o, "url_resolved") != "" ? str (o, "url_resolved") : str (o, "url");
					detail = str (o, "country");
					genre = str (o, "tags").split (",")[0];
					extra = str (o, "tags").replace (",", ", ");
					if (o.get_int_member_with_default ("bitrate", 0) > 0)
						extra = "%d kbps%s%s".printf ((int)o.get_int_member ("bitrate"), extra != "" ? " · " : "", extra);
				}
				else {
					name = str (o, "collectionName");
					url = str (o, "feedUrl");
					detail = str (o, "artistName");
					genre = extra = str (o, "primaryGenreName");
				}
				if (url == "" || name == "" || url in seen)
					continue;
				seen.add (url);
				TreeIter iter;
				store.append (out iter);
				store.set (iter, Col.NAME, name, Col.DETAIL, detail, Col.EXTRA, extra,
				           Col.URL, url, Col.GENRE, genre, Col.ADDED, already_added (url));
				count++;
			}
		}

		if (failed)
			status.label = _("Could not reach the directory. Check your internet connection.");
		else if (count == 0)
			status.label = _("Nothing found for “%s”.").printf (term);
		else if (term == "")
			status.label = _("Most popular stations in your country. Double click one to add it.");
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
		string name, url, genre;
		bool added;
		model.get (iter, Col.NAME, out name, Col.URL, out url, Col.GENRE, out genre, Col.ADDED, out added);
		if (added) {
			status.label = _("“%s” is already in your library.").printf (name);
			return;
		}

		if (kind == Kind.RADIO) {
			string country;
			model.get (iter, Col.DETAIL, out country);
			add_station (name, url, genre, country);
			status.label = _("Added “%s” to Internet Radio.").printf (name);
		}
		else {
			App.podcasts.parse_new_rss (url);
			status.label = _("Subscribing to “%s”… its episodes will appear in Podcasts.").printf (name);
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
