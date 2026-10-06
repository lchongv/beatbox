/*
 * The playing album's cover at the left edge of the LCD, as tall as the LCD
 * itself: it touches the top, bottom and left borders (its outer corners
 * follow the LCD's rounded ones). Shown only when Preferences ask for it and
 * the playing media is a song, or a station: its logo from radio-browser.info,
 * or a generic radio.
 */

using Gtk;

public class BeatBox.LcdCover : Image {
	delegate bool ZoomFunc (double zoom);

	const int CORNER = 7;  // inner radius of the LCD's rounded border

	Gdk.Pixbuf? source = null;  // the cover, unscaled
	int side = 0;               // current size of the rendered square
	static Gee.HashSet<string> logos_asked = new Gee.HashSet<string> (); // one lookup per station and run

	public LcdCover () {
		no_show_all = true;
		valign = Align.FILL;  // the stylesheet pulls it over the LCD's padding (see .lcd-cover)
		get_style_context ().add_class ("lcd-cover");

		App.playback.media_played.connect ((m, old) => refresh ());
		App.playback.playback_stopped.connect ((m) => refresh ());
		App.covers.cover_changed.connect ((artist, album) => refresh ());
		App.settings.main.notify["lcd-show-cover"].connect (refresh);
		refresh ();
	}

	void refresh () {
		var m = App.playback.media_active ? App.playback.current_media : null;
		if (!App.settings.main.lcd_show_cover || m == null || (m.media_type != MediaType.SONG && m.media_type != MediaType.STATION)) {
			source = null;
			hide ();
			return;
		}

		if (m.media_type == MediaType.STATION) {
			source = station_logo (m);
			side = 0;
			render (side_for_now ());
			show ();
			return;
		}

		// The original file in the cache looks better than the framed 180 px version
		source = null;
		try {
			source = new Gdk.Pixbuf.from_file (App.covers.get_cached_album_art_path (App.covers.get_media_coverart_key (m)));
		} catch (Error err) {}

		if (source == null) {
			var framed = App.covers.get_album_art_from_media (m) ?? App.covers.DEFAULT_COVER_SHADOW;
			int crop = 6; // the shadow baked into the cached covers
			if (framed.width > 2 * crop && framed.height > 2 * crop)
				framed = new Gdk.Pixbuf.subpixbuf (framed, crop, crop, framed.width - 2 * crop, framed.height - 2 * crop);
			source = framed;
		}
		side = 0;
		render (side_for_now ());
		show ();
	}

	/** The cover as a file to hand to other applications by drag and drop:
	 *  a copy named "Artist - Album.jpg" in ~/.cache/beatbox/drag, so a file
	 *  manager keeps a meaningful name. null when there is no cover. */
	public string? file_for_drag () {
		var m = App.playback.media_active ? App.playback.current_media : null;
		if (source == null || m == null)
			return null;
		string name = (m.artist != "" ? m.artist + " - " : "") + (m.album != "" ? m.album : m.title);
		name = name.replace ("/", "-").strip ();
		var dir = Path.build_filename (App.settings.get_cache_dir (), "drag");
		var path = Path.build_filename (dir, (name != "" ? name : "cover") + ".jpg");
		try {
			DirUtils.create_with_parents (dir, 0755);
			source.save (path, "jpeg", "quality", "95");
			return path;
		} catch (Error err) {
			warning ("Could not prepare the cover for dragging: %s", err.message);
			return null;
		}
	}

	/** A small copy of the cover for the drag icon */
	public Gdk.Pixbuf? drag_icon () {
		return source != null ? source.scale_simple (64, 64, Gdk.InterpType.BILINEAR) : null;
	}

	/** The cover at full size in a borderless window: drag it anywhere, wheel or +/- zooms,
	 *  0 goes back to the first size, double-click or Esc closes it */
	public void show_full_size (Gtk.Window parent) {
		if (source == null)
			return;
		var area = parent.get_display ().get_monitor_at_window (parent.get_window ()).get_workarea ();
		int max = (int)(int.min (area.width, area.height) * 0.8);
		double fit = double.min (1.0, double.min ((double)max / source.width, (double)max / source.height));
		double zoom = fit;
		var image = new Image ();
		var src = source;
		var win = new Gtk.Window ();
		win.decorated = false;
		win.transient_for = parent;
		win.window_position = WindowPosition.CENTER_ON_PARENT;
		win.title = App.playback.current_media.album;
		win.add (image);
		// ponytail: rescales the whole pixbuf on each step; fine up to the 2.5x cap
		ZoomFunc set_zoom = (z) => {
			zoom = z.clamp (0.1, 2.5);
			image.pixbuf = src.scale_simple (int.max (1, (int)(src.width * zoom)), int.max (1, (int)(src.height * zoom)), Gdk.InterpType.BILINEAR);
			win.resize (1, 1); // shrink with the image
			return true;
		};
		set_zoom (fit);
		var scroll = new Gtk.EventControllerScroll (win, Gtk.EventControllerScrollFlags.VERTICAL);
		// proportional to dy: a wheel notch (1.0) is one 15% step, a touchpad's small deltas are small steps
		scroll.scroll.connect ((dx, dy) => { set_zoom (zoom * Math.pow (1.15, -dy)); });
		win.set_data ("scroll-controller", scroll); // GTK3 controllers need a reference
		var double_click = new Gtk.GestureMultiPress (win);
		double_click.button = 0;
		double_click.pressed.connect ((n_press) => {
			if (n_press == 2)
				win.destroy ();
		});
		win.set_data ("click-gesture", double_click);
		UI.make_window_draggable (win); // drags move it
		var keys = new Gtk.EventControllerKey (win);
		win.set_data ("key-controller", keys);
		keys.key_pressed.connect ((keyval, keycode, state) => {
			if (keyval == Gdk.Key.Escape)
				win.destroy ();
			else if (keyval == Gdk.Key.plus || keyval == Gdk.Key.KP_Add || keyval == Gdk.Key.equal)
				set_zoom (zoom * 1.25);
			else if (keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract)
				set_zoom (zoom / 1.25);
			else if (keyval == Gdk.Key.@0 || keyval == Gdk.Key.KP_0)
				set_zoom (fit);
			return false;
		});
		win.show_all ();
	}

	static string logo_path (Media station) {
		return Path.build_filename (App.settings.get_cache_dir (), "station-logos", Checksum.compute_for_string (ChecksumType.MD5, station.uri));
	}

	/** The station's logo if it is in the cache, otherwise a generic radio while the logo is looked up */
	Gdk.Pixbuf? station_logo (Media station) {
		var path = logo_path (station);
		try {
			return new Gdk.Pixbuf.from_file (path);
		} catch (Error err) {}

		if (!(station.uri in logos_asked)) {
			logos_asked.add (station.uri);
			string uri = station.uri, name = station.title;
			try {
				new Thread<void*>.try (null, () => {
					if (fetch_logo (uri, name, path))
						Idle.add (() => {
							var m = App.playback.media_active ? App.playback.current_media : null;
							if (m != null && m.uri == uri)
								refresh ();
							return Source.REMOVE;
						});
					return null;
				});
			} catch (Error err) {
				warning ("Could not start the station logo lookup: %s", err.message);
			}
		}
		try {
			return new Gdk.Pixbuf.from_resource_at_scale ("/net/launchpad/beatbox/radio.svg", 256, 256, true);
		} catch (Error err) {
			return null;
		}
	}

	/** Looks the station up on radio-browser.info by its stream, then by its exact name, and saves
	 *  the first logo that loads into path. Blocking. */
	static bool fetch_logo (string uri, string name, string path) {
		string server = DirectoryDialog.radio_server ();
		string[] queries = { "/json/stations/byurl?url=" + Uri.escape_string (uri, null, false),
		                     "/json/stations/bynameexact/" + Uri.escape_string (name, null, false) + "?order=votes&reverse=true" };
		foreach (var query in queries) {
			var stations = Http.json_objects (Http.fetch (server + query));
			if (stations == null)
				continue;
			foreach (var o in stations) {
				string favicon = o.get_string_member_with_default ("favicon", "");
				if (favicon == "")
					continue;
				var bytes = Http.fetch_bytes (favicon);
				if (bytes == null)
					continue;
				try {
					var loader = new Gdk.PixbufLoader ();
					loader.write (bytes.get_data ());
					loader.close ();
					if (loader.get_pixbuf () == null)
						continue;
					DirUtils.create_with_parents (Path.get_dirname (path), 0755);
					FileUtils.set_data (path, bytes.get_data ());
					return true;
				} catch (Error err) {} // not an image this build can read
			}
		}
		return false;
	}

	int side_for_now () {
		int h = get_allocated_height ();
		return (h > 16) ? h : 54;  // until the first allocation
	}

	/** Scale the cover to fit a square of the given side (a logo may not be square), rounding its left corners */
	void render (int new_side) {
		if (source == null || new_side == side)
			return;
		side = new_side;
		double k = double.min ((double)side / source.width, (double)side / source.height);
		int w = int.max (1, (int)(source.width * k)), h = int.max (1, (int)(source.height * k));
		var scaled = source.scale_simple (w, h, Gdk.InterpType.BILINEAR);

		var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, side, side);
		var cr = new Cairo.Context (surface);
		cr.new_sub_path ();
		cr.arc (CORNER, CORNER, CORNER, Math.PI, 1.5 * Math.PI);
		cr.line_to (side, 0);
		cr.line_to (side, side);
		cr.arc (CORNER, side - CORNER, CORNER, 0.5 * Math.PI, Math.PI);
		cr.close_path ();
		cr.clip ();
		Gdk.cairo_set_source_pixbuf (cr, scaled, (side - w) / 2, (side - h) / 2);
		cr.paint ();
		set_from_pixbuf (Gdk.pixbuf_get_from_surface (surface, 0, 0, side, side));
	}

	public override void size_allocate (Allocation a) {
		base.size_allocate (a);
		if (source != null && a.height > 16 && a.height != side) {
			int h = a.height;
			Idle.add (() => { render (h); return Source.REMOVE; }); // resizing inside an allocation would loop
		}
	}
}
