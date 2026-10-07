using Gtk;

/** Listening Statistics: the most played artists, albums and genres, from the songs' play counts.
 * ponytail: play counts only; a chart by day would need a history of plays, which BeatBox doesn't keep */
public class BeatBox.StatsWindow : Gtk.Window {
	const int TOP = 12;
	const int ROW_H = 24;
	const int LABEL_W = 220;
	const int COUNT_W = 60;

	class Row {
		public string label;
		public uint plays;
	}

	public StatsWindow () {
		title = _("Listening Statistics");
		transient_for = App.window;
		destroy_with_parent = true;
		set_default_size (620, 640);

		var artists = new Gee.HashMap<string, uint> ();
		var albums = new Gee.HashMap<string, uint> ();
		var genres = new Gee.HashMap<string, uint> ();
		uint plays = 0, played_songs = 0;
		uint64 seconds = 0;
		foreach (var m in App.library.song_library.medias ()) {
			if (m.play_count == 0)
				continue;
			plays += m.play_count;
			played_songs++;
			seconds += (uint64)m.play_count * m.length;
			count (artists, m.artist, m.play_count);
			if (m.album != "")
				// "Album — Artist": the same name by two artists is two albums
				count (albums, "%s — %s".printf (m.album, m.album_artist != "" ? m.album_artist : m.artist), m.play_count);
			count (genres, m.genre, m.play_count);
		}

		var box = new Box (Orientation.VERTICAL, 6);
		box.border_width = 16;
		var total = new Label (plays == 0 ? _("Nothing has been played yet.")
			: ngettext ("%u play of %u song", "%u plays of %u songs", plays).printf (plays, played_songs)
			  + " · " + _("%s of listening").printf (duration (seconds)));
		total.xalign = 0;
		total.wrap = true;
		box.add (total);
		box.add (section (_("Most Played Artists"), top (artists)));
		box.add (section (_("Most Played Albums"), top (albums)));
		box.add (section (_("Most Played Genres"), top (genres)));

		var scroll = new ScrolledWindow (null, null);
		scroll.hscrollbar_policy = PolicyType.NEVER;
		scroll.add (box);
		add (scroll);
	}

	static void count (Gee.HashMap<string, uint> counts, string key, uint plays) {
		string k = key.strip () != "" ? key.strip () : _("Unknown");
		counts[k] = (counts.has_key (k) ? counts[k] : 0) + plays;
	}

	static Gee.List<Row> top (Gee.HashMap<string, uint> counts) {
		var rows = new Gee.ArrayList<Row> ();
		foreach (var entry in counts.entries)
			rows.add (new Row () { label = entry.key, plays = entry.value });
		rows.sort ((a, b) => (a.plays != b.plays) ? (int)b.plays - (int)a.plays : a.label.collate (b.label));
		return (rows.size > TOP) ? rows.slice (0, TOP) : rows;
	}

	static string duration (uint64 seconds) {
		uint64 hours = seconds / 3600;
		if (hours >= 48)
			return ngettext ("%u day", "%u days", (ulong)(hours / 24)).printf ((uint)(hours / 24));
		if (hours >= 1)
			return ngettext ("%u hour", "%u hours", (ulong)hours).printf ((uint)hours);
		return ngettext ("%u minute", "%u minutes", (ulong)(seconds / 60)).printf ((uint)(seconds / 60));
	}

	/** A title and horizontal bars, drawn by hand: name, bar as long as its plays, plays */
	Widget section (string heading, Gee.List<Row> rows) {
		var title = new Label (null);
		title.set_markup ("<b>%s</b>".printf (Markup.escape_text (heading)));
		title.xalign = 0;
		title.margin_top = 12;
		var area = new DrawingArea ();
		area.set_size_request (-1, int.max (1, rows.size) * ROW_H);
		area.draw.connect ((cr) => {
			int width = area.get_allocated_width ();
			var ctx = area.get_style_context ();
			var fg = ctx.get_color (StateFlags.NORMAL);
			Gdk.RGBA accent;
			if (!ctx.lookup_color ("bb_accent", out accent) && !ctx.lookup_color ("theme_selected_bg_color", out accent))
				accent = { 0.24, 0.43, 0.79, 1 };
			if (rows.size == 0) {
				text (cr, area, _("No plays yet"), 0, 0, width, fg, 0.6);
				return true;
			}
			uint most = rows[0].plays;
			int bar_w = int.max (20, width - LABEL_W - COUNT_W - 16);
			for (int i = 0; i < rows.size; i++) {
				int y = i * ROW_H;
				text (cr, area, rows[i].label, 0, y, LABEL_W - 8, fg, 1);
				double w = bar_w * (double)rows[i].plays / most;
				Gdk.cairo_set_source_rgba (cr, accent);
				cr.rectangle (LABEL_W, y + 5, double.max (2, w), ROW_H - 10);
				cr.fill ();
				text (cr, area, rows[i].plays.to_string (), LABEL_W + (int)w + 6, y, COUNT_W, fg, 0.7);
			}
			return true;
		});
		var box = new Box (Orientation.VERTICAL, 4);
		box.add (title);
		box.add (area);
		return box;
	}

	static void text (Cairo.Context cr, Widget widget, string s, int x, int y, int width, Gdk.RGBA fg, double alpha) {
		var layout = widget.create_pango_layout (s);
		layout.set_width (width * Pango.SCALE);
		layout.set_ellipsize (Pango.EllipsizeMode.END);
		int h;
		layout.get_pixel_size (null, out h);
		cr.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha * alpha);
		cr.move_to (x, y + (ROW_H - h) / 2);
		Pango.cairo_show_layout (cr, layout);
	}
}
