/*
 * Cover grid where clicking a cover unfolds the album INLINE, as a full-width
 * band under its row that pushes the rows below down.
 *
 * The covers are painted by hand on a Gtk.Fixed (hundreds of albums, no
 * widget per cell); the only child widget is the detail band, moved into the
 * gap left under the open row. A triangle on top of the band points at the
 * open cover.
 */

using Gtk;

/* A plain widget with its own measure and size_allocate, holding the band as its only child.
 * (GTK3's Gtk.Layout became a Gtk.Fixed in the port, and the Fixed's layout manager kept
 * GTK 4 from ever calling the overrides: one column of covers and no band.) */
public class BeatBox.AlbumWall : Widget {
	const int COVER = Icons.ALBUM_VIEW_IMAGE_SIZE; // cached covers include their shadow
	const int CELL_W = COVER + 16;
	const int CELL_H = COVER + 44;                  // cover + two lines of text
	const int GAP = 18;
	const int ARROW_W = 28;
	const int ARROW_H = 14;
	const int DETAIL_TEXT_W = 220;  // width of the band's left column without a cover
	const int ANIMATION_MS = 250;   // the band unfolding and the scroll to it
	const int SIDE_SLACK = 12;      // the cover keeps its side for smaller moves (see set_detail_side)

	GenericGrid grid;
	SourceView wrapper;
	Album[] albums = {};

	int cols = 1;
	int step = GAP;          // horizontal gap, grown to spread the cells evenly
	int open_index = -1;
	Album? open_album = null;
	Revealer? detail = null; // placed in the layout, unfolds the band
	Widget? holder = null;   // its child, given the height content wants
	Widget? content = null;  // measured to size the holder
	ScrolledWindow? detail_list = null; // the band's track list: takes the wheel when the wall can't scroll
	Gdk.Pixbuf? detail_source = null;  // full size cover of the open album
	Image? detail_cover = null;
	Box? detail_left = null;
	int detail_side = -1;    // current side of detail_cover, from the settings' percentage
	int detail_percent = -1; // the percentage detail_side was made with
	int detail_h = 0;        // height of the band (arrow included)
	bool scroll_to_detail = false;
	uint scroll_tick = 0;

	/** Double click on a cover, or the band's play button */
	public signal void album_activated (Album album);

	// the widget keeps the controllers alive; the fields are for set_state and the cursor
	GestureClick click_gesture;
	EventControllerMotion motion_controller;

	/** The vertical adjustment of the ScrolledWindow the wall sits in (Fixed has none of its own) */
	Adjustment vadjustment {
		get { return ((ScrolledWindow) get_ancestor (typeof (ScrolledWindow))).vadjustment; }
	}

	public AlbumWall (GenericGrid grid, SourceView wrapper) {
		this.grid = grid;
		this.wrapper = wrapper;
		add_css_class ("albumwall");
		click_gesture = new GestureClick ();
		click_gesture.pressed.connect (on_pressed);
		add_controller (click_gesture);
		motion_controller = new EventControllerMotion ();
		motion_controller.motion.connect (on_motion);
		add_controller (motion_controller);
		var wheel = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
		wheel.scroll.connect (on_wheel);
		add_controller (wheel);

		grid.visible_changed.connect (refresh);
		App.covers.cover_changed.connect (() => queue_draw ());
		App.settings.main.notify["album-detail-cover-percent"].connect (() => queue_resize ());
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

	static int columns_for (int width) {
		return int.max (1, (width - GAP) / (CELL_W + GAP));
	}

	/** The band's height at width, arrow included: what its content needs, times how far
	 * the revealer has unfolded it. 0 without a band. */
	int band_height (int width) {
		if (detail == null)
			return 0;
		int shown_h, shown_nat, min_base, nat_base, min_w;
		detail.measure (Orientation.HORIZONTAL, -1, out min_w, out shown_nat, out min_base, out nat_base);
		detail.measure (Orientation.VERTICAL, int.max (width, min_w), out shown_h, out shown_nat, out min_base, out nat_base);
		return shown_h + ARROW_H;
	}

	/* The height depends on the width: without this GTK 4 measures the height for no width
	 * (one column of covers), and the wall scrolled into a huge blank below the last row */
	public override SizeRequestMode get_request_mode () {
		return SizeRequestMode.HEIGHT_FOR_WIDTH;
	}

	/* One column wide at least (the scrolled window gives it the rest); as tall as the rows and the band */
	public override void measure (Orientation orientation, int for_size, out int minimum, out int natural,
	                              out int minimum_baseline, out int natural_baseline) {
		minimum_baseline = natural_baseline = -1;
		int width = for_size > 0 ? for_size : CELL_W + 2 * GAP;
		if (orientation == Orientation.HORIZONTAL) {
			minimum = natural = CELL_W + 2 * GAP;
			return;
		}
		int c = columns_for (width);
		int band = band_height (width);
		minimum = natural = GAP + (albums.length + c - 1) / c * (CELL_H + GAP) + (band > 0 ? band + GAP : 0);
	}

	public override void size_allocate (int width, int height, int baseline) {
		cols = columns_for (width);
		step = int.max (GAP, (width - cols * CELL_W) / (cols + 1));

		int full_h = 0;
		if (detail != null) {
			// The band takes the whole width
			set_detail_side (width);
			int min_h, min_base, nat_base;
			content.measure (Orientation.VERTICAL, width, out min_h, out full_h, out min_base, out nat_base);
			holder.set_size_request (-1, full_h); // no-op (no relayout) when unchanged; a width would become the band's minimum
			detail_h = band_height (width);
			var at = Graphene.Point () { x = 0, y = band_y () + ARROW_H };
			detail.allocate (width, detail_h - ARROW_H, -1, new Gsk.Transform ().translate (at));
		}

		if (scroll_to_detail && detail != null) {
			scroll_to_detail = false;
			// show the whole band if it fits, keeping the clicked row in view
			double top = row_y (open_row) - GAP;
			double bottom = band_y () + full_h + ARROW_H + GAP; // where it ends once unfolded
			var adj = vadjustment;
			if (bottom > adj.value + adj.page_size)
				scroll_smoothly (double.min (top, bottom - adj.page_size));
			else if (top < adj.value)
				scroll_smoothly (top);
		}
	}

	/** Eases the view to value; the band grows meanwhile, so the target may only fit at the end */
	void scroll_smoothly (double value) {
		if (scroll_tick != 0)
			remove_tick_callback (scroll_tick);
		scroll_tick = 0;
		if (!get_settings ().gtk_enable_animations) {
			vadjustment.value = value;
			return;
		}
		double from = vadjustment.value;
		int64 start = get_frame_clock ().get_frame_time ();
		scroll_tick = add_tick_callback ((widget, clock) => {
			double t = double.min (1, (clock.get_frame_time () - start) / (ANIMATION_MS * 1000.0));
			vadjustment.value = from + (value - from) * (1 - Math.pow (1 - t, 3)); // ease out
			if (t < 1)
				return Source.CONTINUE;
			scroll_tick = 0;
			return Source.REMOVE;
		});
	}

	/* Only the visible part is painted (see snapshot), and GTK 4 scrolls by moving the last drawing:
	 * without a redraw the rows scrolled into view stay blank. Same when the view grows taller. */
	ulong scroll_id = 0;
	public override void map () {
		base.map ();
		if (scroll_id != 0)
			return;
		scroll_id = vadjustment.value_changed.connect (queue_draw);
		vadjustment.changed.connect (queue_draw);
	}

	public override void dispose () {
		if (detail != null)
			detail.unparent ();
		detail = null;
		base.dispose ();
	}

	/* ---------- painting ---------- */

	public override void snapshot (Gtk.Snapshot s) {
		// the cairo area is only the visible part; the covers keep the coordinates of the whole wall
		var r = Graphene.Rect ();
		r.init (0, (float) vadjustment.value, get_width (), (float) vadjustment.page_size);
		var cr = s.append_cairo (r);

		int w = get_width ();
		int h = get_height ();
		// (GTK draws the CSS background of the wall, .albumwall, before this)

		double top = vadjustment.value;
		double bottom = top + h;
		var fg = get_color ();

		for (int i = 0; i < albums.length; i++) {
			int x, y;
			cell_rect (i, out x, out y);
			if (y + CELL_H < top || y > bottom)
				continue;

			if (i == open_index && detail.reveal_child) {
				Gdk.RGBA accent = UI.named_color ("bb_accent");
				cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.18);
				rounded_rect (cr, x - 4, y - 4, CELL_W + 8, CELL_H + 8, 6);
				cr.fill ();
			}

			var pix = App.covers.get_album_art_from_key (albums[i].get_album_artist (), albums[i].get_album ())
			          ?? App.covers.DEFAULT_COVER_SHADOW;
			UI.set_source_pixbuf (cr, pix, x + (CELL_W - pix.width) / 2, y);
			cr.paint ();

			draw_text (cr, albums[i].get_album (), x, y + COVER + 2, true, fg);
			draw_text (cr, albums[i].get_album_artist (), x, y + COVER + 20, false, fg);
		}

		if (detail != null)
			draw_band (cr, w);

		base.snapshot (s); // the children (the detail band) are drawn on top, in widget coordinates
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
	void draw_band (Cairo.Context cr, int width) {
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
		// skins may recolor the band (see theme.css)
		Gdk.RGBA bg = UI.named_color ("bb_detail_bg"), edge = UI.named_color ("bb_detail_border");
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

	void on_pressed (int n_press, double x, double y) {
		// a press on the band's own widgets (play button, track list) belongs to them
		if (pick (x, y, PickFlags.DEFAULT) != this)
			return;
		int i = index_at (x, y);
		// every press opens or closes the band; the second one of a double click also plays the album
		if (i < 0 || i == open_index)
			close_detail (true);
		else
			open_detail (i);
		if (n_press == 2 && i >= 0)
			album_activated (albums[i]);
		click_gesture.set_state (EventSequenceState.CLAIMED);
	}

	/** Moves adj by a wheel step (the one GtkRange takes); false when it can't move that way */
	static bool wheel_scroll (Adjustment adj, double dy) {
		double max = adj.upper - adj.page_size;
		if (max <= adj.lower)
			return false;
		double to = (adj.value + dy * Math.pow (adj.page_size, 2.0 / 3.0)).clamp (adj.lower, max);
		if (to == adj.value)
			return false;
		adj.value = to;
		return true;
	}

	/** The band's track list takes the wheel while it can scroll, then the wall does. Done here, not by
	 *  the list's ScrolledWindow: it takes the wheel even when it has nothing to scroll (Aqua or not). */
	bool on_list_wheel (double dy) {
		if (dy == 0)
			return false;
		if (!wheel_scroll (detail_list.vadjustment, dy))
			wheel_scroll (vadjustment, dy);
		return true;
	}

	/** A wall with nothing to scroll hands the wheel to the open band's track list.
	 *  Only looks at the wheel: returning false lets the event go on to the scrolled window above. */
	bool on_wheel (double dx, double dy) {
		if (dy == 0 || detail_list == null || vadjustment.upper > vadjustment.page_size)
			return false;
		return wheel_scroll (detail_list.vadjustment, dy);
	}

	void on_motion (double x, double y) {
		bool over_cover = pick (x, y, PickFlags.DEFAULT) == this && index_at (x, y) >= 0;
		set_cursor_from_name (over_cover ? "pointer" : null);
	}

	/* ---------- the detail band ---------- */

	/** animate: fold the band away first (the rows below slide up) */
	void close_detail (bool animate = false) {
		if (detail != null && animate) {
			var folding = detail;
			if (!folding.reveal_child)
				return; // already folding
			folding.notify["child-revealed"].connect (() => {
				if (folding == detail && !folding.child_revealed)
					close_detail ();
			});
			folding.reveal_child = false;
			queue_draw (); // the cover is no longer marked
			return;
		}
		if (detail != null)
			detail.unparent ();
		detail = null;
		holder = content = null;
		detail_list = null;
		detail_cover = null;
		detail_left = null;
		detail_source = null;
		open_album = null;
		open_index = -1;
		queue_resize ();
	}

	void open_detail (int index) {
		// another album of the open row: the band stays unfolded and only its content changes
		bool unfolded = detail != null && detail.reveal_child && open_row == index / cols;
		close_detail ();
		open_index = index;
		open_album = albums[index];
		content = build_detail (open_album);
		var box = new Box (Orientation.VERTICAL, 0);
		content.vexpand = true;
		box.append (content);
		holder = box;
		detail = new Revealer ();
		detail.transition_type = RevealerTransitionType.SLIDE_DOWN;
		detail.transition_duration = unfolded ? 0 : ANIMATION_MS;
		detail.set_child (holder);
		detail.set_parent (this);
		detail.reveal_child = true;
		scroll_to_detail = true;
		queue_resize ();
	}

	/** Cover side = band width × Preferences percentage (0 hides it). No-op when unchanged,
	 * so calling it from size_allocate doesn't loop. A move under SIDE_SLACK keeps the old side:
	 * the wall's scrollbar comes and goes with the band's height and takes its width, and a side
	 * that followed every pixel would make the band taller and shorter in turn. */
	void set_detail_side (int width) {
		int percent = App.settings.main.album_detail_cover_percent;
		int side = width * percent / 100;
		if (percent == detail_percent && detail_side >= 0 && (side - detail_side).abs() < SIDE_SLACK)
			return;
		if (side == detail_side || detail_cover == null)
			return;
		detail_percent = percent;
		detail_side = side;
		if (side < 16) {
			detail_cover.hide ();
			detail_left.set_size_request (DETAIL_TEXT_W, -1);
			return;
		}
		var scaled = detail_source.scale_simple (side, side, Gdk.InterpType.BILINEAR);
		UI.show_pixbuf (detail_cover, App.covers.add_shadow_to_album_art (scaled, false));
		detail_cover.show ();
		detail_left.set_size_request (int.max (side, DETAIL_TEXT_W) + 20, -1);
	}

	Widget build_detail (Album album) {
		var medias = album.get_medias_sorted ();
		Media? first = null;
		uint seconds = 0;
		foreach (var m in medias) {
			first = first ?? m;
			seconds += m.length;
		}

		// Big cover: the original file in the cache, if there is one; sized by set_detail_side
		detail_source = null;
		if (first != null) {
			try {
				detail_source = new Gdk.Pixbuf.from_file (App.covers.get_cached_album_art_path (App.covers.get_media_coverart_key (first)));
			} catch (Error err) {}
		}
		detail_source = detail_source ?? App.covers.get_album_art_from_key (album.get_album_artist (), album.get_album ())
		                              ?? App.covers.DEFAULT_COVER_SHADOW;
		var cover = new Image ();
		cover.visible = false; // shown by set_detail_side, once it knows the side
		detail_cover = cover;
		detail_side = -1;

		var title = new Label (album.get_album ());
		title.add_css_class ("album-detail-title");
		var artist = new Label (album.get_album_artist ());
		artist.add_css_class ("album-detail-artist");
		string info = ngettext ("%d song", "%d songs", medias.size).printf (medias.size)
		              + ", " + ngettext ("%d minute", "%d minutes", seconds / 60).printf ((int)(seconds / 60));
		if (first != null && first.year > 0)
			info += " · %u".printf (first.year);
		if (first != null && first.genre != "")
			info += " · " + first.genre;
		var details = new Label (info);
		details.add_css_class ("dim-label");
		foreach (var l in new Label[] { title, artist, details }) {
			l.wrap = true;
			l.max_width_chars = 24;
			l.justify = Justification.CENTER;
		}
		var play_box = new Box (Orientation.HORIZONTAL, 6);
		play_box.append (new Image.from_icon_name ("media-playback-start-symbolic"));
		play_box.append (new Label (_("Play")));
		var play = new Button ();
		play.child = play_box;
		play.halign = Align.CENTER;
		play.clicked.connect (() => album_activated (album));

		var left = new Box (Orientation.VERTICAL, 4);
		left.valign = Align.START;
		detail_left = left;
		left.append (cover);
		title.margin_top = title.margin_bottom = 2;
		left.append (title);
		left.append (artist);
		left.append (details);
		play.margin_top = play.margin_bottom = 8;
		left.append (play);

		// Same track list as the popup window
		var tvs = new TreeViewSetup (MusicColumn.ARTIST, SortType.ASCENDING, TreeViewSetup.Hint.ALBUM_LIST);
		var list = new MusicList (tvs);
		list.set_sort_column_id (tvs.sort_column_id, tvs.sort_direction);
		list.set_parent_wrapper (wrapper);
		var table = new HashTable<int, Media> (null, null);
		foreach (var m in medias)
			table.set ((int)table.size (), m);
		list.set_table (table);
		var list_scroll = new ScrolledWindow ();
		list_scroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC); // shrinks when the cover is big
		list_scroll.propagate_natural_height = true;
		list_scroll.max_content_height = 440;
		list_scroll.valign = Align.FILL; // as tall as the band: the cover column may be taller than 440
		list_scroll.set_child (list);
		detail_list = list_scroll;
		var list_wheel = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
		list_wheel.scroll.connect ((dx, dy) => on_list_wheel (dy));
		list_scroll.add_controller (list_wheel);

		// the band's padding (border_width in GTK3) goes to its children as margins
		var band = new Box (Orientation.HORIZONTAL, 18);
		band.add_css_class ("album-detail");
		left.margin_top = left.margin_bottom = left.margin_start = 16;
		band.append (left);
		list_scroll.hexpand = true;
		var list_wrap = AquaScroll.wrap (list_scroll);
		list_wrap.margin_top = list_wrap.margin_bottom = list_wrap.margin_end = 16;
		band.append (list_wrap);
		return band;
	}
}
