/*
 * Cover grid where clicking a cover unfolds the album INLINE, as a full-width
 * band under its row that pushes the rows below down (iTunes 11). GTK3 port of
 * the itunes7 clone's It7Albumwall.
 *
 * The covers are painted by hand on a Gtk.Layout (hundreds of albums, no
 * widget per cell); the only child widget is the detail band, moved into the
 * gap left under the open row. A triangle on top of the band points at the
 * open cover.
 */

using Gtk;

public class BeatBox.AlbumWall : Layout {
	const int COVER = Icons.ALBUM_VIEW_IMAGE_SIZE; // cached covers include their shadow
	const int CELL_W = COVER + 16;
	const int CELL_H = COVER + 44;                  // cover + two lines of text
	const int GAP = 18;
	const int ARROW_W = 28;
	const int ARROW_H = 14;
	const int DETAIL_COVER = 220;

	GenericGrid grid;
	SourceView wrapper;
	Album[] albums = {};

	int cols = 1;
	int step = GAP;          // horizontal gap, grown to spread the cells evenly
	int open_index = -1;
	Album? open_album = null;
	Widget? detail = null;   // holder placed in the layout
	Widget? content = null;  // its child, measured to size the holder
	int detail_h = 0;        // height of the band (arrow included)
	bool scroll_to_detail = false;

	/** Double click on a cover, or the band's play button */
	public signal void album_activated (Album album);

	public AlbumWall (GenericGrid grid, SourceView wrapper) {
		this.grid = grid;
		this.wrapper = wrapper;
		get_style_context ().add_class ("albumwall");
		add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK);

		grid.visible_changed.connect (refresh);
		App.covers.cover_changed.connect (() => queue_draw ());
		refresh ();
	}

	/** Reload the albums from the grid (same order and search filter) */
	public void refresh () {
		var table = grid.get_visible_table ();
		albums = {};
		for (int i = 0; i < table.size (); i++)
			albums += (Album)table.get (i);

		open_index = -1;
		for (int i = 0; open_album != null && i < albums.length; i++)
			if (same_album (albums[i], open_album))
				open_index = i;
		if (open_album != null && open_index < 0)
			close_detail ();
		queue_resize ();
	}

	static bool same_album (Album a, Album b) {
		return a == b || (a.get_album () == b.get_album () && a.get_album_artist () == b.get_album_artist ());
	}

	/* ---------- layout ---------- */

	int open_row { get { return (open_index >= 0) ? open_index / cols : -1; } }

	int row_y (int row) {
		int y = GAP + row * (CELL_H + GAP);
		if (open_index >= 0 && row > open_row)
			y += detail_h + GAP;
		return y;
	}

	void cell_rect (int i, out int x, out int y) {
		x = step + (i % cols) * (CELL_W + step);
		y = row_y (i / cols);
	}

	int band_y () {
		return row_y (open_row) + CELL_H + GAP / 2;
	}

	public override void size_allocate (Allocation alloc) {
		int width = alloc.width;
		cols = int.max (1, (width - GAP) / (CELL_W + GAP));
		step = int.max (GAP, (width - cols * CELL_W) / (cols + 1));

		if (detail != null) {
			// The band takes the whole width; its height is whatever its content needs
			int min_h, nat_h;
			content.get_preferred_height_for_width (width, out min_h, out nat_h);
			detail.set_size_request (width, nat_h); // no-op (no relayout) when unchanged
			detail_h = nat_h + ARROW_H;
			int y = band_y () + ARROW_H;
			int old_x, old_y;
			child_get (detail, "x", out old_x, "y", out old_y);
			if (old_x != 0 || old_y != y)
				move (detail, 0, y);
		}

		int rows = (albums.length + cols - 1) / cols;
		int height = GAP + rows * (CELL_H + GAP) + ((detail != null) ? detail_h + GAP : 0);
		height = int.max (height, alloc.height); // paint the background down to the bottom
		uint old_w, old_h;
		get_size (out old_w, out old_h);
		if (old_w != width || old_h != height)
			set_size (width, height);

		base.size_allocate (alloc);

		if (scroll_to_detail && detail != null) {
			scroll_to_detail = false;
			// show the whole band if it fits, keeping the clicked row in view
			double top = row_y (open_row) - GAP;
			double bottom = band_y () + detail_h + GAP;
			var adj = vadjustment;
			if (bottom > adj.value + adj.page_size)
				adj.value = double.min (top, bottom - adj.page_size);
			else if (top < adj.value)
				adj.value = top;
		}
	}

	/* ---------- painting ---------- */

	public override bool draw (Cairo.Context cr) {
		if (!Gtk.cairo_should_draw_window (cr, get_bin_window ()))
			return base.draw (cr);

		uint w, h;
		get_size (out w, out h);
		var ctx = get_style_context ();
		ctx.render_background (cr, 0, 0, w, h);

		double top = vadjustment.value;
		double bottom = top + get_allocated_height ();
		var fg = ctx.get_color (StateFlags.NORMAL);

		for (int i = 0; i < albums.length; i++) {
			int x, y;
			cell_rect (i, out x, out y);
			if (y + CELL_H < top || y > bottom)
				continue;

			if (i == open_index) {
				Gdk.RGBA accent;
				if (!get_style_context ().lookup_color ("it7_accent", out accent))
					accent = { 0.24, 0.43, 0.79, 1 };
				cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.18);
				rounded_rect (cr, x - 4, y - 4, CELL_W + 8, CELL_H + 8, 6);
				cr.fill ();
			}

			var pix = App.covers.get_album_art_from_key (albums[i].get_album_artist (), albums[i].get_album ())
			          ?? App.covers.DEFAULT_COVER_SHADOW;
			Gdk.cairo_set_source_pixbuf (cr, pix, x + (CELL_W - pix.width) / 2, y);
			cr.paint ();

			draw_text (cr, albums[i].get_album (), x, y + COVER + 2, true, fg);
			draw_text (cr, albums[i].get_album_artist (), x, y + COVER + 20, false, fg);
		}

		if (detail != null)
			draw_band (cr, w);

		return base.draw (cr);
	}

	void draw_text (Cairo.Context cr, string text, int x, int y, bool bold, Gdk.RGBA fg) {
		var layout = create_pango_layout (text);
		layout.set_width (CELL_W * Pango.SCALE);
		layout.set_ellipsize (Pango.EllipsizeMode.END);
		layout.set_alignment (Pango.Alignment.CENTER);
		var attrs = new Pango.AttrList ();
		if (bold)
			attrs.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
		layout.set_attributes (attrs);
		cr.set_source_rgba (fg.red, fg.green, fg.blue, bold ? fg.alpha : fg.alpha * 0.65);
		cr.move_to (x, y);
		Pango.cairo_show_layout (cr, layout);
	}

	/** White band with a triangle pointing at the open cover */
	void draw_band (Cairo.Context cr, uint width) {
		int cx, cy;
		cell_rect (open_index, out cx, out cy);
		double tip = cx + CELL_W / 2.0;
		double y = band_y () + ARROW_H + 0.5;
		double bottom = band_y () + detail_h - 0.5;

		cr.move_to (0, y);
		cr.line_to (tip - ARROW_W / 2.0, y);
		cr.line_to (tip, y - ARROW_H);
		cr.line_to (tip + ARROW_W / 2.0, y);
		cr.line_to (width, y);
		cr.line_to (width, bottom);
		cr.line_to (0, bottom);
		cr.close_path ();
		// skins may recolor the band (see itunes.css)
		Gdk.RGBA bg, edge;
		if (!get_style_context ().lookup_color ("it7_detail_bg", out bg))
			bg = { 1, 1, 1, 1 };
		if (!get_style_context ().lookup_color ("it7_detail_border", out edge))
			edge = { 0.74, 0.74, 0.74, 1 };
		Gdk.cairo_set_source_rgba (cr, bg);
		cr.fill_preserve ();
		Gdk.cairo_set_source_rgba (cr, edge);
		cr.set_line_width (1);
		cr.stroke ();
	}

	static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
		cr.new_sub_path ();
		cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
		cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
		cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
		cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
		cr.close_path ();
	}

	/* ---------- input ---------- */

	int index_at (double px, double py) {
		for (int i = 0; i < albums.length; i++) {
			int x, y;
			cell_rect (i, out x, out y);
			if (px >= x && px < x + CELL_W && py >= y && py < y + CELL_H)
				return i;
		}
		return -1;
	}

	public override bool button_press_event (Gdk.EventButton ev) {
		if (ev.button != 1 || ev.window != get_bin_window ())
			return false;
		int i = index_at (ev.x, ev.y);
		if (ev.type == Gdk.EventType.DOUBLE_BUTTON_PRESS) {
			if (i >= 0)
				album_activated (albums[i]);
			return true;
		}
		if (ev.type != Gdk.EventType.BUTTON_PRESS)
			return true;
		if (i < 0 || i == open_index)
			close_detail ();
		else
			open_detail (i);
		return true;
	}

	public override bool motion_notify_event (Gdk.EventMotion ev) {
		if (ev.window == get_bin_window ())
			ev.window.set_cursor ((index_at (ev.x, ev.y) >= 0) ? new Gdk.Cursor.for_display (get_display (), Gdk.CursorType.HAND2) : null);
		return false;
	}

	/* ---------- the detail band ---------- */

	void close_detail () {
		if (detail != null)
			detail.destroy ();
		detail = content = null;
		open_album = null;
		open_index = -1;
		queue_resize ();
	}

	void open_detail (int index) {
		close_detail ();
		open_index = index;
		open_album = albums[index];
		content = build_detail (open_album);
		var holder = new Box (Orientation.VERTICAL, 0);
		holder.pack_start (content, true, true, 0);
		detail = holder;
		put (detail, 0, 0);
		detail.show_all ();
		scroll_to_detail = true;
		queue_resize ();
	}

	Widget build_detail (Album album) {
		var medias = album.get_medias_sorted ();
		Media? first = null;
		uint seconds = 0;
		foreach (var m in medias) {
			first = first ?? m;
			seconds += m.length;
		}

		// Big cover: the original file in the cache, if there is one
		Gdk.Pixbuf? pix = null;
		if (first != null) {
			try {
				var path = App.covers.get_cached_album_art_path (App.covers.get_media_coverart_key (first));
				pix = App.covers.add_shadow_to_album_art (new Gdk.Pixbuf.from_file_at_scale (path, DETAIL_COVER, DETAIL_COVER, false), false);
			} catch (Error err) {}
		}
		var cover = new Image.from_pixbuf (pix ?? App.covers.get_album_art_from_key (album.get_album_artist (), album.get_album ())
		                                       ?? App.covers.DEFAULT_COVER_SHADOW);

		var title = new Label (album.get_album ());
		title.get_style_context ().add_class ("album-detail-title");
		var artist = new Label (album.get_album_artist ());
		artist.get_style_context ().add_class ("album-detail-artist");
		string info = ngettext ("%d song", "%d songs", medias.size).printf (medias.size)
		              + ", " + ngettext ("%d minute", "%d minutes", seconds / 60).printf ((int)(seconds / 60));
		if (first != null && first.year > 0)
			info += " · %u".printf (first.year);
		if (first != null && first.genre != "")
			info += " · " + first.genre;
		var details = new Label (info);
		details.get_style_context ().add_class ("dim-label");
		foreach (var l in new Label[] { title, artist, details }) {
			l.wrap = true;
			l.max_width_chars = 24;
			l.justify = Justification.CENTER;
		}
		var play = new Button.with_label (_("Play"));
		play.image = new Image.from_icon_name ("media-playback-start-symbolic", IconSize.MENU);
		play.always_show_image = true;
		play.halign = Align.CENTER;
		play.clicked.connect (() => album_activated (album));

		var left = new Box (Orientation.VERTICAL, 4);
		left.valign = Align.START;
		left.set_size_request (DETAIL_COVER + 20, -1);
		left.pack_start (cover, false, false, 0);
		left.pack_start (title, false, false, 2);
		left.pack_start (artist, false, false, 0);
		left.pack_start (details, false, false, 0);
		left.pack_start (play, false, false, 8);

		// Same track list as the popup window
		var tvs = new TreeViewSetup (MusicColumn.ARTIST, SortType.ASCENDING, TreeViewSetup.Hint.ALBUM_LIST);
		var list = new MusicList (tvs);
		list.set_sort_column_id (tvs.sort_column_id, tvs.sort_direction);
		list.set_parent_wrapper (wrapper);
		var table = new HashTable<int, Media> (null, null);
		foreach (var m in medias)
			table.set ((int)table.size (), m);
		list.set_table (table);
		var list_scroll = new ScrolledWindow (null, null);
		list_scroll.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
		list_scroll.propagate_natural_height = true;
		list_scroll.max_content_height = 440;
		list_scroll.valign = Align.START;
		list_scroll.add (list);

		var band = new Box (Orientation.HORIZONTAL, 18);
		band.get_style_context ().add_class ("album-detail");
		band.border_width = 16;
		band.pack_start (left, false, false, 0);
		band.pack_start (list_scroll, true, true, 0);
		return band;
	}
}
