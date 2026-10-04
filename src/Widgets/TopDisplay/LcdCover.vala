/*
 * The playing album's cover at the left edge of the LCD, as tall as the LCD
 * itself: it touches the top, bottom and left borders (its outer corners
 * follow the LCD's rounded ones). Shown only when Preferences ask for it and
 * the playing media is a song.
 */

using Gtk;

public class BeatBox.LcdCover : Image {
	const int CORNER = 7;  // inner radius of the LCD's rounded border

	Gdk.Pixbuf? source = null;  // the cover, unscaled
	int side = 0;               // current size of the rendered square

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
		if (!App.settings.main.lcd_show_cover || m == null || m.media_type != MediaType.SONG) {
			source = null;
			hide ();
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

	/** The cover at full size in a borderless window: drag it anywhere, double-click or Esc closes it */
	public void show_full_size (Gtk.Window parent) {
		if (source == null)
			return;
		var area = parent.get_display ().get_monitor_at_window (parent.get_window ()).get_workarea ();
		int max = (int)(int.min (area.width, area.height) * 0.8);
		var pix = source;
		if (pix.width > max || pix.height > max) {
			double k = double.min ((double)max / pix.width, (double)max / pix.height);
			pix = pix.scale_simple ((int)(pix.width * k), (int)(pix.height * k), Gdk.InterpType.BILINEAR);
		}
		var win = new Gtk.Window ();
		win.decorated = false;
		win.transient_for = parent;
		win.window_position = WindowPosition.CENTER_ON_PARENT;
		win.title = App.playback.current_media.album;
		win.add (new Image.from_pixbuf (pix));
		win.button_press_event.connect ((e) => {
			if (e.type != Gdk.EventType.2BUTTON_PRESS)
				return false; // single press: the draggable handler below moves it
			win.destroy ();
			return true;
		});
		UI.make_window_draggable (win);
		win.key_press_event.connect ((e) => {
			if (e.keyval == Gdk.Key.Escape)
				win.destroy ();
			return false;
		});
		win.show_all ();
	}

	int side_for_now () {
		int h = get_allocated_height ();
		return (h > 16) ? h : 54;  // until the first allocation
	}

	/** Scale the cover to a square of the given side, rounding its left corners */
	void render (int new_side) {
		if (source == null || new_side == side)
			return;
		side = new_side;
		var scaled = source.scale_simple (side, side, Gdk.InterpType.BILINEAR);

		var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, side, side);
		var cr = new Cairo.Context (surface);
		cr.new_sub_path ();
		cr.arc (CORNER, CORNER, CORNER, Math.PI, 1.5 * Math.PI);
		cr.line_to (side, 0);
		cr.line_to (side, side);
		cr.arc (CORNER, side - CORNER, CORNER, 0.5 * Math.PI, Math.PI);
		cr.close_path ();
		cr.clip ();
		Gdk.cairo_set_source_pixbuf (cr, scaled, 0, 0);
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
