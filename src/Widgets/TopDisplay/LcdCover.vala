/*
 * Thumbnail of the playing album's cover, at the left edge of the LCD.
 * Shown only when Preferences ask for it and the playing media is a song.
 */

using Gtk;

public class BeatBox.LcdCover : Image {
	const int SIDE = 42;

	public LcdCover () {
		no_show_all = true;
		margin_right = 8;
		valign = Align.CENTER;
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
			hide ();
			return;
		}

		// The original file in the cache looks better than the framed 180 px version
		Gdk.Pixbuf? pix = null;
		try {
			var path = App.covers.get_cached_album_art_path (App.covers.get_media_coverart_key (m));
			pix = new Gdk.Pixbuf.from_file_at_scale (path, SIDE, SIDE, true);
		} catch (Error err) {}

		if (pix == null) {
			var framed = App.covers.get_album_art_from_media (m) ?? App.covers.DEFAULT_COVER_SHADOW;
			int crop = 6; // the shadow baked into the cached covers
			if (framed.width > 2 * crop && framed.height > 2 * crop)
				framed = new Gdk.Pixbuf.subpixbuf (framed, crop, crop, framed.width - 2 * crop, framed.height - 2 * crop);
			pix = framed.scale_simple (SIDE, SIDE, Gdk.InterpType.BILINEAR);
		}
		set_from_pixbuf (pix);
		show ();
	}
}
