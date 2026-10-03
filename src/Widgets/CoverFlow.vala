/*
 * iTunes-style Cover Flow drawn with Cairo (GTK3, no OpenGL).
 *
 * Side covers are faked into perspective by painting them as thin vertical
 * strips whose height shrinks towards the far edge. Each cover is
 * pre-rendered once (with its floor reflection) into a cached surface.
 */

using Gtk;

public class BeatBox.CoverFlow : DrawingArea {
	const int STRIPS = 48;          // perspective quality of side covers
	const double SIDE_SCALE = 0.36; // horizontal squash of side covers
	const double FAR_SCALE = 0.78;  // height of a side cover's far edge
	const double REFLECTION = 0.4;  // reflection height, relative to cover
	const int CROP = 6;             // shadow margin baked into cached covers

	GenericGrid grid;
	Album[] albums = {};
	HashTable<Album, Cairo.ImageSurface> surfaces = new HashTable<Album, Cairo.ImageSurface>(direct_hash, direct_equal);

	double position = 0;  // animated, fractional index of the centered cover
	int target = 0;       // index we're animating to
	uint tick_id = 0;
	int64 last_frame = 0;

	/** The centered album changed (after the user navigated) */
	public signal void album_selected(Album album);
	/** Double click / Enter on the centered album */
	public signal void album_activated(Album album);

	public CoverFlow(GenericGrid grid) {
		this.grid = grid;
		can_focus = true;
		set_size_request(-1, 300);
		add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.SCROLL_MASK
		           | Gdk.EventMask.SMOOTH_SCROLL_MASK | Gdk.EventMask.KEY_PRESS_MASK);
		get_style_context().add_class("coverflow");

		grid.visible_changed.connect(refresh);
		App.covers.cover_changed.connect(() => { surfaces.remove_all(); queue_draw(); });
		App.playback.media_played.connect((m, old) => center_on(m));
		refresh();
	}

	/** Reload the albums from the grid (same order and search filter) */
	public void refresh() {
		var table = grid.get_visible_table();
		Album? current = (albums.length > 0) ? albums[target] : null;

		albums = {};
		for (int i = 0; i < table.size(); i++)
			albums += (Album)table.get(i);
		surfaces.remove_all();

		target = 0;
		// start on the album that is playing
		if (current == null && App.playback.media_active) {
			var m = App.playback.current_media;
			for (int i = 0; i < albums.length; i++)
				if (albums[i].get_album() == m.album && albums[i].get_album_artist() == m.album_artist)
					target = i;
		}
		for (int i = 0; current != null && i < albums.length; i++) {
			if (albums[i] == current
			    || (albums[i].get_album() == current.get_album() && albums[i].get_album_artist() == current.get_album_artist()))
				target = i;
		}
		position = target;
		queue_draw();
	}

	public Album? get_selected() {
		return (albums.length > 0) ? albums[target] : null;
	}

	/** Glide to the album of the track being played */
	void center_on(Media m) {
		for (int i = 0; i < albums.length; i++) {
			if (albums[i].get_album() == m.album && albums[i].get_album_artist() == m.album_artist) {
				move_to(i);
				return;
			}
		}
	}
	
	void go_to(int index) {
		if (albums.length > 0 && index.clamp(0, albums.length - 1) != target) {
			move_to(index);
			album_selected(albums[target]);
		}
	}
	
	void move_to(int index) {
		if (albums.length == 0)
			return;
		index = index.clamp(0, albums.length - 1);
		if (index == target)
			return;
		target = index;
		if (tick_id == 0) {
			last_frame = 0;
			tick_id = add_tick_callback(animate);
		}
	}

	bool animate(Widget widget, Gdk.FrameClock clock) {
		int64 now = clock.get_frame_time();
		double dt = (last_frame == 0) ? 0.016 : (now - last_frame) / 1000000.0;
		last_frame = now;

		// exponential easing towards the target
		position += (target - position) * (1 - Math.exp(-dt * 10));
		if ((target - position).abs() < 0.002) {
			position = target;
			queue_draw();
			tick_id = 0;
			return Source.REMOVE;
		}
		queue_draw();
		return Source.CONTINUE;
	}

	/** Cover + fading floor reflection, rendered once per album */
	Cairo.ImageSurface surface_for(Album album, int size) {
		var cached = surfaces.get(album);
		if (cached != null && cached.get_width() == size)
			return cached;

		var art = App.covers.get_album_art_from_key(album.get_album_artist(), album.get_album());
		var pix = art ?? App.covers.DEFAULT_COVER_SHADOW;
		if (pix.width > 2 * CROP && pix.height > 2 * CROP)
			pix = new Gdk.Pixbuf.subpixbuf(pix, CROP, CROP, pix.width - 2 * CROP, pix.height - 2 * CROP);
		pix = pix.scale_simple(size, size, Gdk.InterpType.BILINEAR);

		int reflection = (int)(size * REFLECTION);
		var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, size, size + reflection);
		var cr = new Cairo.Context(surface);
		Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0);
		cr.paint();

		// reflection: flipped copy, masked with a fading gradient
		cr.save();
		cr.rectangle(0, size, size, reflection);
		cr.clip();
		cr.translate(0, 2 * size);
		cr.scale(1, -1);
		Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0);
		var fade = new Cairo.Pattern.linear(0, size, 0, size - reflection);
		fade.add_color_stop_rgba(0, 0, 0, 0, 0.35);
		fade.add_color_stop_rgba(1, 0, 0, 0, 0);
		cr.mask(fade);
		cr.restore();

		if (art != null) // the real cover may still be loading: don't cache the placeholder
			surfaces.set(album, surface);
		return surface;
	}

	/**
	 * Paints a cover whose left edge is at x0 and right edge at x1 (in
	 * screen space), with heights h0/h1 at each edge, bottom aligned on
	 * the floor line.
	 */
	void paint_cover(Cairo.Context cr, Cairo.ImageSurface surface, int size,
	                 double x0, double x1, double h0, double h1, double floor_y, double alpha) {
		double total_h = surface.get_height();
		if ((h0 - h1).abs() < 0.5) {
			// facing the viewer: a plain scaled paint
			double s = h0 / size;
			cr.save();
			cr.translate(x0, floor_y - h0);
			cr.scale((x1 - x0) / size, s);
			cr.set_source_surface(surface, 0, 0);
			cr.rectangle(0, 0, size, total_h);
			cr.clip();
			cr.paint_with_alpha(alpha);
			cr.restore();
			return;
		}

		double strip_w = (x1 - x0) / STRIPS;
		double src_w = (double)size / STRIPS;
		for (int i = 0; i < STRIPS; i++) {
			double t = (i + 0.5) / STRIPS;
			double h = h0 + (h1 - h0) * t;
			double s = h / size;
			cr.save();
			cr.rectangle(x0 + i * strip_w, floor_y - h, strip_w + 0.6, total_h * s);
			cr.clip();
			cr.translate(x0 + i * strip_w, floor_y - h);
			cr.scale(strip_w / src_w, s);
			cr.set_source_surface(surface, -i * src_w, 0);
			cr.paint_with_alpha(alpha);
			cr.restore();
		}
	}

	public override bool draw(Cairo.Context cr) {
		int width = get_allocated_width();
		int height = get_allocated_height();

		// black stage with a subtle glow, like iTunes
		var bg = new Cairo.Pattern.linear(0, 0, 0, height);
		bg.add_color_stop_rgb(0, 0.16, 0.16, 0.18);
		bg.add_color_stop_rgb(0.6, 0, 0, 0);
		bg.add_color_stop_rgb(1, 0, 0, 0);
		cr.set_source(bg);
		cr.paint();

		if (albums.length == 0)
			return true;

		int size = int.min((int)(height * 0.56), (int)(width * 0.3));
		if (size < 16)
			return true;
		double floor_y = height * 0.08 + size;
		double center = width / 2.0;
		double side_w = size * SIDE_SCALE;
		double gap = size * 0.78;     // from the center cover to the first side cover
		double spacing = side_w * 0.55;

		// draw from the outside in so nearer covers overlap farther ones
		int first = int.max(0, (int)Math.floor(position) - 12);
		int last = int.min(albums.length - 1, (int)Math.ceil(position) + 12);
		var order = new Gee.ArrayList<int>();
		for (int i = first; i <= last; i++)
			order.add(i);
		order.sort((a, b) => {
			double da = (a - position).abs(), db = (b - position).abs();
			return (da > db) ? -1 : (da < db) ? 1 : 0;
		});

		foreach (int i in order) {
			double offset = i - position;           // <0 left, >0 right
			double d = offset.abs();
			double k = double.min(d, 1);             // 0 = facing, 1 = fully turned
			double w = size + (side_w - size) * k;
			double near_h = size * (1 - 0.06 * k);
			double far_h = size * (1 - (1 - FAR_SCALE) * k);

			double cx = center + Math.copysign(gap * k + spacing * double.max(d - 1, 0), offset);
			double x0 = cx - w / 2, x1 = cx + w / 2;
			double alpha = (d > 8) ? double.max(0, 1 - (d - 8) / 4) : 1;
			var surface = surface_for(albums[i], size);
			if (offset < 0)
				paint_cover(cr, surface, size, x0, x1, far_h, near_h, floor_y, alpha);
			else
				paint_cover(cr, surface, size, x0, x1, near_h, far_h, floor_y, alpha);
		}

		// caption of the centered album
		var album = albums[target];
		var layout = create_pango_layout(null);
		layout.set_markup("<b>%s</b>\n<span foreground='#a0a0a0'>%s</span>".printf(
			Markup.escape_text(album.get_album()), Markup.escape_text(album.get_album_artist())), -1);
		layout.set_alignment(Pango.Alignment.CENTER);
		layout.set_width((int)(width * 0.8) * Pango.SCALE);
		layout.set_ellipsize(Pango.EllipsizeMode.END);
		int tw, th;
		layout.get_pixel_size(out tw, out th);
		cr.set_source_rgb(1, 1, 1);
		cr.move_to(center - width * 0.4, height - th - 10);
		Pango.cairo_show_layout(cr, layout);
		return true;
	}

	/** Which album is under x (center cover first, then the side ones) */
	int index_at(double x) {
		int width = get_allocated_width();
		int height = get_allocated_height();
		int size = int.min((int)(height * 0.56), (int)(width * 0.3));
		double center = width / 2.0;
		if ((x - center).abs() <= size / 2.0)
			return target;
		double side_w = size * SIDE_SCALE;
		double gap = size * 0.78, spacing = side_w * 0.55;
		double dist = (x - center).abs() - gap + side_w / 2;
		int steps = 1 + (int)Math.floor(double.max(dist, 0) / spacing);
		return target + ((x < center) ? -steps : steps);
	}

	public override bool button_press_event(Gdk.EventButton event) {
		grab_focus();
		if (event.button != 1 || albums.length == 0)
			return false;
		int index = index_at(event.x);
		if (event.type == Gdk.EventType.2BUTTON_PRESS && index == target)
			album_activated(albums[target]);
		else if (event.type == Gdk.EventType.BUTTON_PRESS)
			go_to(index);
		return true;
	}

	double scroll_accum = 0;
	public override bool scroll_event(Gdk.EventScroll event) {
		switch (event.direction) {
			case Gdk.ScrollDirection.UP:
			case Gdk.ScrollDirection.LEFT:
				go_to(target - 1);
				break;
			case Gdk.ScrollDirection.DOWN:
			case Gdk.ScrollDirection.RIGHT:
				go_to(target + 1);
				break;
			case Gdk.ScrollDirection.SMOOTH:
				double dx, dy;
				event.get_scroll_deltas(out dx, out dy);
				scroll_accum += (dx.abs() > dy.abs()) ? dx : dy;
				if (scroll_accum.abs() >= 1) {
					go_to(target + (int)scroll_accum);
					scroll_accum -= (int)scroll_accum;
				}
				break;
		}
		return true;
	}

	public override bool key_press_event(Gdk.EventKey event) {
		switch (event.keyval) {
			case Gdk.Key.Left:  go_to(target - 1); return true;
			case Gdk.Key.Right: go_to(target + 1); return true;
			case Gdk.Key.Home:  go_to(0); return true;
			case Gdk.Key.End:   go_to(albums.length - 1); return true;
			case Gdk.Key.Return:
			case Gdk.Key.KP_Enter:
				if (albums.length > 0)
					album_activated(albums[target]);
				return true;
		}
		return false;
	}
}
