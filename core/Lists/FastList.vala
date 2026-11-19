/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 *
 * A list of medias on a Gtk.ColumnView (Gtk.TreeView is deprecated since GTK 4.10). The
 * list keeps a table of its medias, sorts it itself (compare func) and shows the ones the
 * search lets through; the cells read their values from the value func, by column number.
 */

using Gtk;

[GIR (visible = false)] // internal, not for plugins
public class BeatBox.FastList : ScrollableBin {
	public const int OPTIMAL_COLUMN = -2;

	/** How a column shows the value the value func gives it */
	public enum CellKind {
		TEXT,     // a string
		NUMBER,   // an int, blank when below 1 (track, year, plays...)
		LENGTH,   // the media's length as m:ss
		DATE,     // seconds since 1970
		BITRATE,  // an int, with "kbps"
		RATING,   // an int, as stars
		ICON,     // a GLib.Icon (a spinner while the media shows its indicator), and the check box
		TOGGLE    // a bool, as a check box
	}

	protected ColumnView view;
	FastListModel fm;
	MultiSelection selection;
	HashTable<int, Media> table; // is not the same object as showing.
	HashTable<int, Media> showing; // should never point to table.
	Gee.ArrayList<ColumnViewColumn> columns = new Gee.ArrayList<ColumnViewColumn>();
	Gee.ArrayList<CellKind?> kinds = new Gee.ArrayList<CellKind?>();
	internal Gee.HashSet<FastCell> bound_cells = new Gee.HashSet<FastCell>();

	/* sortable stuff */
	public delegate int SortCompareFunc (int sort_column_id, Gtk.SortType sort_direction, Media a, Media b);
	protected int sort_column_id;
	protected SortType sort_direction;
	private unowned SortCompareFunc compare_func;
	bool sorting_from_code = false;

	/* user specific function for the cells' values */
	public delegate Value ValueReturnFunc (int row, int column, Media o);
	internal unowned ValueReturnFunc value_func;

	// search stuff
	string last_search;
	protected bool restoring_scroll; // true while do_search restores the scroll position
	public delegate void ViewSearchFunc (string search, HashTable<int, Media> table, ref HashTable<int, Media> showing);
	private unowned ViewSearchFunc search_func;

	/** Temporary medias (not in the library) show in italics */
	public bool is_mixed { get; set; default = false; }
	/** The icon column has a check box for the medias' "unchecked" */
	public bool show_checks { get; set; default = false; }
	Gdk.Texture?[] star_textures = new Gdk.Texture?[6];
	Gdk.Pixbuf? starred = null;

	/** Where a drop would go: a line above this visible row, -1 for none */
	protected int drop_line = -1;

	public signal void rows_reordered();
	/** The visible (sorted, searched) medias changed */
	public signal void visible_changed();
	/** A row was double-clicked, or got Enter */
	public signal void row_activated(int position);
	/** The user ticked or unticked a TOGGLE cell */
	public signal void cell_toggled(int position, int column, bool active);
	/** The user ticked or unticked a media's check box (show_checks) */
	public signal void check_toggled(Media m, bool active);
	/** The user resized a column */
	public signal void column_resized();
	/** The list scrolled (by the user, or by itself: see restoring_scroll) */
	public signal void scrolled();

	/* The list paints its own zebra rows (draw_stripes): the view and its rows stay transparent,
	 * whatever the skin. Skins color the text, the selection and the titles (theme.css). */
	const string CSS = """
columnview.tracklist, columnview.tracklist > listview, columnview.tracklist > listview > row {
  background-color: transparent; background-image: none;
}
columnview.tracklist > listview > row { padding: 0; min-height: 0; border-radius: 0; }
columnview.tracklist > listview > row > cell { padding: 1px 4px 1px 4px; }
columnview.tracklist > listview > row:selected { background-color: @bb_accent; color: white; }
columnview.tracklist > listview > row:selected label { color: white; }
fastcell { min-height: 23px; }
/* the dividers around a list (column browser, Cover Flow, side bar, report): their invisible grab
 * area (Adwaita gives it 8 px on each side) would take the clicks on the titles and the first
 * column (check boxes): it goes away from the list only */
paned.above-list.vertical > separator:not(.wide) { margin: -8px 0 0 0; padding: 8px 0 0 0; background-clip: content-box; }
paned.before-list.horizontal > separator:not(.wide) { margin: 0 0 0 -8px; padding: 0 0 0 8px; background-clip: content-box; }
paned.after-list.horizontal > separator:not(.wide) { margin: 0 -8px 0 0; padding: 0 8px 0 0; background-clip: content-box; }
fastcell checkbutton { padding: 0; margin: 0; min-height: 0; }
fastcell checkbutton check { margin: 0; }
""";
	
	public FastList () {
		UI.add_css(CSS);
		table = new HashTable<int, Media>(null, null);
		showing = new HashTable<int, Media>(null, null);
		fm = new FastListModel();
		selection = new MultiSelection(fm);
		selection.selection_changed.connect(() => queue_draw()); // the selection's band (draw_stripes)

		sort_column_id = OPTIMAL_COLUMN;
		sort_direction = SortType.ASCENDING;
		last_search = "";

		view = new ColumnView(selection);
		view.reorderable = false;
		view.add_css_class("tracklist");
		view.activate.connect((position) => row_activated((int)position));
		view.sorter.changed.connect(sorter_changed);
		scroll_child = view;
		add_css_class("tracklist-box");

		notify["vadjustment"].connect(watch_scroll);
		watch_scroll();
		notify["is-mixed"].connect(() => refresh_all());

		set_table(table);
	}

	/* a list shown again may have missed changes that only asked for a redraw */
	public override void map () {
		base.map ();
		refresh_all ();
	}
	
	Adjustment? watched = null;
	ulong watched_id = 0;
	void watch_scroll() {
		if(watched != null && watched_id != 0)
			watched.disconnect(watched_id);
		watched = vadjustment;
		watched_id = (watched != null) ? watched.value_changed.connect(() => { scrolled(); queue_draw(); }) : 0;
	}

	/* ---- drawing: zebra rows behind the (transparent) view, and the drop line ---- */

	public override void snapshot (Gtk.Snapshot s) {
		var r = Graphene.Rect ();
		r.init (0, 0, get_width (), get_height ());
		var cr = s.append_cairo (r);
		draw_stripes (cr);
		snapshot_child (view, s); // the header and the rows go over the stripes
		if (drop_line >= 0) {
			var line = s.append_cairo (r);
			int y = header_height () + drop_line * row_height () - (int) (vadjustment != null ? vadjustment.value : 0);
			Gdk.RGBA accent = UI.named_color ("bb_accent");
			Gdk.cairo_set_source_rgba (line, accent);
			line.rectangle (0, y - 1, get_width (), 2);
			line.fill ();
		}
	}

	/** The height of the column titles, 0 when they're hidden */
	protected int header_height () {
		var header = view.get_first_child ();
		return (header != null && header.visible) ? header.get_height () : 0;
	}

	int last_row_height = 0;
	/** The height of a row: they are all alike */
	protected int row_height () {
		var list = view.get_last_child (); // the ColumnView's list, after its header
		for (var row = (list != null) ? list.get_first_child () : null; row != null; row = row.get_next_sibling ()) {
			if (row.get_height () > 0 && row.get_first_child () != null) {
				last_row_height = row.get_height ();
				break;
			}
		}
		return last_row_height > 0 ? last_row_height : 24;
	}

	/** Zebra rows: the view's own background is transparent (see theme.css), so we paint
	 * white and pale blue bands before GTK draws the rows on top. */
	void draw_stripes (Cairo.Context cr) {
		int row_h = row_height ();
		int first_y = header_height () - (int) (vadjustment != null ? vadjustment.value : 0);
		int height = get_height ();
		int width = get_width ();
		// skins may recolor the stripes (see theme.css)
		Gdk.RGBA row_a = UI.named_color ("bb_row_a"), row_b = UI.named_color ("bb_row_b");
		Gdk.cairo_set_source_rgba (cr, row_a);
		cr.paint ();
		Gdk.cairo_set_source_rgba (cr, row_b);
		int index = (first_y < 0) ? (-first_y / row_h) : 0;
		int first_index = index;
		for (int y = first_y + index * row_h; y < height; y += row_h, ++index) {
			if (index % 2 == 1)
				cr.rectangle (0, y, width, row_h);
		}
		cr.fill ();
		// the selection goes the whole width, past the last column (as GTK 3's did)
		Gdk.cairo_set_source_rgba (cr, UI.named_color ("bb_accent"));
		index = first_index;
		for (int y = first_y + index * row_h; y < height && index < fm.get_n_items (); y += row_h, ++index) {
			if (selection.is_selected (index))
				cr.rectangle (0, y, width, row_h);
		}
		cr.fill ();
	}

	/* ---- columns ---- */

	/** Adds the next column (its number is the value func's column number). key is the
	 *  title the setups keep (English), title the one shown. */
	public ColumnViewColumn add_column (string key, string? title, CellKind kind, int width, bool visible,
	                                    bool sortable = true, bool resizable = true) {
		int index = columns.size;
		var factory = new SignalListItemFactory ();
		factory.setup.connect ((obj) => {
			var cell = (ColumnViewCell) obj;
			cell.child = new FastCell (this, index, kind);
			cell.focusable = false;
		});
		factory.bind.connect ((obj) => {
			var cell = (ColumnViewCell) obj;
			var fast = (FastCell) cell.child;
			fast.item = cell;
			bound_cells.add (fast);
			fast.refresh ();
		});
		factory.unbind.connect ((obj) => {
			var fast = (FastCell) ((ColumnViewCell) obj).child;
			bound_cells.remove (fast);
			fast.item = null;
		});
		var column = new ColumnViewColumn (title, factory);
		column.id = key;
		column.fixed_width = width > 0 ? width : -1;
		column.visible = visible;
		column.resizable = resizable;
		if (sortable)
			column.sorter = new CustomSorter (null); // the list sorts its table itself
		column.notify["fixed-width"].connect (() => column_resized ());
		view.append_column (column);
		columns.add (column);
		kinds.add (kind);
		return column;
	}

	public ColumnViewColumn? get_column (int index) {
		return (index >= 0 && index < columns.size) ? columns[index] : null;
	}

	public int get_n_columns () {
		return columns.size;
	}

	/** The column whose key (English title) is key */
	public ColumnViewColumn? column_titled (string key) {
		foreach (var column in columns)
			if (column.id == key)
				return column;
		return null;
	}

	/** The columns as a setup keeps them */
	public GLib.List<ListColumn> get_column_setup () {
		var rv = new GLib.List<ListColumn> ();
		foreach (var column in columns)
			rv.append (new ListColumn (column.id, column.fixed_width, column.visible));
		return rv;
	}

	/** The column titles: GTK 3's lists could hide them, the header is the view's first child */
	public bool headers_visible {
		get {
			var header = view.get_first_child ();
			return header == null || header.visible;
		}
		set {
			var header = view.get_first_child ();
			if (header != null)
				header.visible = value;
		}
	}

	/** A menu for a right click on the column titles */
	public void set_header_menu (GLib.MenuModel menu) {
		foreach (var column in columns)
			column.header_menu = menu;
	}

	/** The five stars of the rating column */
	public void set_rating_icons (Gdk.Pixbuf? starred) {
		this.starred = starred;
		star_textures = new Gdk.Texture?[6];
	}

	internal Gdk.Texture? stars (int rating) {
		if (starred == null || rating <= 0)
			return null;
		rating = int.min (rating, 5);
		if (star_textures[rating] == null) {
			var canvas = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, starred.width * 5, starred.height);
			canvas.fill ((uint) 0xffffff00);
			for (int i = 0; i < rating; i++)
				starred.copy_area (0, 0, starred.width, starred.height, canvas, i * starred.width, 0);
			star_textures[rating] = UI.texture_from_pixbuf (canvas);
		}
		return star_textures[rating];
	}

	/* ---- the rows ---- */

	/** Should not be manipulated by client */
	public HashTable<int, Media> get_table() {
		return table;
	}

	/** Should not be manipulated by client */
	public HashTable<int, Media> get_visible_table() {
		return showing;
	}

	public Media get_media_from_index(int index) {
		return showing.get(index);
	}

	/** The selected medias, in order */
	public GLib.List<Media> get_selected_medias() {
		var rv = new GLib.List<Media>();
		var chosen = selection.get_selection();
		uint n = (uint) chosen.get_size();
		for(uint i = 0; i < n; i++) {
			var m = fm.get_media(chosen.get_nth(i));
			if(m != null)
				rv.append(m);
		}
		return rv;
	}

	public int count_selected() {
		return (int) selection.get_selection().get_size();
	}

	public bool is_row_selected(int row) {
		return row >= 0 && selection.is_selected(row);
	}

	/** Selects this row only */
	public void select_only(int row) {
		if(row >= 0 && row < fm.get_n_items())
			selection.select_item(row, true);
	}

	public void select_row(int row) {
		if(row >= 0 && row < fm.get_n_items())
			selection.select_item(row, false);
	}

	public void unselect_row(int row) {
		if(row >= 0)
			selection.unselect_item(row);
	}

	public void unselect_all() {
		selection.unselect_all();
	}

	/** Selects the rows of these medias, and only those */
	public void select_medias(Gee.Collection<Media> medias) {
		var chosen = new Bitset.empty();
		for(int i = 0; i < showing.size(); i++)
			if(medias.contains(showing.get(i)))
				chosen.add((uint) i);
		var mask = new Bitset.empty();
		mask.add_range(0, fm.get_n_items());
		selection.set_selection(chosen, mask);
	}

	/** Moves the keyboard focus to a row (and selects it) */
	public void focus_row(int row) {
		if(row >= 0 && row < fm.get_n_items())
			view.scroll_to(row, null, ListScrollFlags.FOCUS | ListScrollFlags.SELECT, null);
	}

	/** As a double click on the row */
	public void activate_row(int row) {
		if(row >= 0 && row < fm.get_n_items())
			row_activated(row);
	}

	/** The row under (x, y), in this widget's coordinates; -1 if none */
	public int row_at(double x, double y) {
		if(y < header_height())
			return -1;
		var cell = cell_at(x, y);
		if(cell != null && cell.item != null)
			return (int) cell.item.position;
		return -1;
	}

	/** The column under (x, y); -1 if none */
	public int column_at(double x, double y) {
		var cell = cell_at(x, y);
		return (cell != null) ? cell.column : -1;
	}

	FastCell? cell_at(double x, double y) {
		var w = pick(x, y, PickFlags.DEFAULT);
		for(; w != null && w != this; w = w.get_parent()) {
			if(w is FastCell)
				return (FastCell) w;
			// the padding of a cell, or of the row around it: their (first) cell
			string node = w.get_css_name();
			if(node == "cell" || node == "row") {
				for(var child = w.get_first_child(); child != null; child = child.get_first_child())
					if(child is FastCell)
						return (FastCell) child;
			}
		}
		return null;
	}

	/** Whether y (this widget's coordinates) is on the column titles */
	public bool on_header(double y) {
		return y < header_height();
	}

	/** The first row on screen */
	public int first_visible_row() {
		if(vadjustment == null || fm.get_n_items() == 0)
			return -1;
		return int.min((int)(vadjustment.value / row_height()), (int) fm.get_n_items() - 1);
	}

	/** Scrolls to a row: just into view, or to the top when to_top */
	public void scroll_to_row(int row, bool to_top) {
		if(row < 0 || row >= fm.get_n_items())
			return;
		if(to_top && vadjustment != null && vadjustment.upper > 0)
			vadjustment.value = double.min(row * row_height(), vadjustment.upper - vadjustment.page_size);
		else
			view.scroll_to(row, null, ListScrollFlags.NONE, null);
	}

	/** Redraws the cells of a row */
	public void redraw_row (int row_index) {
		foreach (var cell in bound_cells)
			if (cell.item != null && cell.item.position == row_index)
				cell.refresh ();
	}

	/** Redraws the rows of these medias */
	public void redraw_medias (Gee.Collection<Media> medias) {
		foreach (var cell in bound_cells)
			if (cell.item != null && medias.contains ((Media) cell.item.item))
				cell.refresh ();
	}

	/** Redraws every row on screen */
	public void refresh_all () {
		foreach (var cell in bound_cells)
			cell.refresh ();
	}

	public void set_value_func(ValueReturnFunc func) {
		value_func = func;
	}

	public void set_table (HashTable<int, Media> table, bool do_resort = true) {
		this.table = table;

		if(do_resort)
			resort(); // this also calls search
		else
			do_search(null);
	}

	// If a Media is in objects but not in table, will just ignore
	public void remove_medias (HashTable<Media, int> objects) {
		int index = 0;
		var new_table = new HashTable<int, Media>(null, null);
		for(int i = 0; i < table.size(); ++i) {
			Media o;

			// create a new table. if not in objects, and is in table, add it.
			if((o = table.get(i)) != null && objects.get(o) != 1) {
				new_table.set(index++, o);
			}
		}

		// no need to resort, just removing
		set_table(new_table, false);
		unselect_all();
	}

	// Does NOT check for duplicates
	public void add_medias (List<Media> objects) {
		// skip calling set_table and just do it ourselves (faster)
		foreach(var o in objects) {
			table.set((int)table.size(), o);
		}

		// resort the new songs in. this will also call do_search
		resort ();
	}

	public void set_search_func (ViewSearchFunc func) {
		search_func = func;
	}

	public void do_search (string? search) {
		if(search_func == null)
			return;

		var old_size = showing.size();

		// Remember the top visible song to stay on it (unless the search changed)
		Media? anchor = null;
		int anchor_index = -1;
		if(old_size > 0 && (search == null || search == last_search)) {
			anchor_index = first_visible_row();
			if(anchor_index >= 0)
				anchor = showing.get(anchor_index);
		}
		// the selection stays on its medias, wherever they go
		var selected = new Gee.HashSet<Media>();
		foreach(var m in get_selected_medias())
			selected.add(m);

		showing.remove_all();
		if(search != null)
			last_search = search;

		search_func(last_search, table, ref showing);

		fm.set_table(showing);
		if(selected.size > 0)
			select_medias(selected);
		refresh_all(); // rows that stayed may show new numbers (#)

		if(anchor != null) {
			for(int i = 0; i < showing.size(); ++i) {
				if(showing.get(i) == anchor) {
					if(i == anchor_index) // still in its row: leave the scroll alone
						break;
					restoring_scroll = true;
					int row = i;
					// once the rows are measured anew
					Idle.add(() => {
						scroll_to_row(row, true);
						Idle.add(() => { restoring_scroll = false; return false; }, Priority.LOW);
						return false;
					});
					break;
				}
			}
		}
		visible_changed();
	}

	/** Sorting is done here, not in the model. That way the whole
	 * table is sorted and ready to go and we do not need to resort every
	 * time we repopulate/search the model
	**/
	public void set_sort_column_id (int sort_column_id, SortType order) {
		show_sort(sort_column_id, order);
		reorder_requested(sort_column_id, order);
	}

	public void get_sort_column_id (out int sort_column, out SortType order) {
		sort_column = sort_column_id;
		order = sort_direction;
	}

	/** The arrow on the column title */
	void show_sort(int column, SortType order) {
		sorting_from_code = true;
		var c = get_column(column);
		view.sort_by_column((c != null && c.sorter != null) ? c : null, order);
		sorting_from_code = false;
	}

	/** A click on a column title: false keeps the order as it is */
	protected virtual bool sort_requested(int column, SortType order) {
		return true;
	}

	void sorter_changed() {
		if(sorting_from_code)
			return;
		var sorter = (ColumnViewSorter) view.sorter;
		var column = sorter.primary_sort_column;
		int index = (column != null) ? columns.index_of(column) : OPTIMAL_COLUMN;
		var order = sorter.primary_sort_order;
		if(index < 0 || !sort_requested(index, order)) {
			Idle.add(() => { show_sort(sort_column_id, sort_direction); return false; });
			return;
		}
		reorder_requested(index, order);
	}

	void reorder_requested (int column, Gtk.SortType direction) {
		if(column == sort_column_id && direction == sort_direction) {
			return;
		}

		sort_column_id = column;
		sort_direction = direction;

		quicksort(0, (int)(table.size() - 1));
		do_search(null);

		// Let it be known the row order changed
		rows_reordered();
	}

	// On the main thread: sorting in a thread raced with the UI and with
	// add_medias/set_table, which use the same table
	public void resort () {
		quicksort(0, (int)(table.size() - 1));
		do_search (null);
	}

	public void set_compare_func (SortCompareFunc func) {
		compare_func = func;
	}

	void swap (int a, int b) {
		Media temp = table.get(a);
		table.set(a, table.get(b));
		table.set(b, temp);
	}

	public void quicksort (int start, int end) {
		if(end <= start)
			return;
		Media pivot = table.get((start+end)/2);
		int i = start;
		int j = end;

		while(i <= j) {
			while(i < end && compare_func (sort_column_id, sort_direction, table.get(i), pivot) < 0) ++i;
			while(j > start && compare_func (sort_column_id, sort_direction, table.get(j), pivot) > 0) --j;
			if(i <= j) {
				swap(i, j);
				++i; --j;
			}
		}

		if(start < j)	quicksort (start, j);
		if(i < end)		quicksort (i, end);
	}
}

/** A cell of a FastList: it shows its column's value for the media of its row */
[GIR (visible = false)]
public class BeatBox.FastCell : Gtk.Widget {
	weak FastList list;
	public int column;
	FastList.CellKind kind;
	public ColumnViewCell? item = null;

	Label? label = null;
	Image? icon = null;
	Spinner? spinner = null;
	CheckButton? check = null;
	Picture? stars = null;
	bool binding = false;

	static construct {
		set_layout_manager_type (typeof (BoxLayout));
		set_css_name ("fastcell");
	}

	public FastCell (FastList list, int column, FastList.CellKind kind) {
		this.list = list;
		this.column = column;
		this.kind = kind;
		((BoxLayout) layout_manager).spacing = 4;

		switch (kind) {
			case FastList.CellKind.ICON:
				icon = new Image ();
				icon.pixel_size = 16;
				icon.set_parent (this);
				spinner = new Spinner ();
				spinner.visible = false;
				spinner.set_parent (this);
				if (list.show_checks) {
					check = new CheckButton ();
					check.focusable = false;
					check.set_parent (this);
					check.toggled.connect (() => {
						if (!binding && item != null && item.item != null)
							list.check_toggled ((Media) item.item, check.active);
					});
				}
				break;
			case FastList.CellKind.TOGGLE:
				check = new CheckButton ();
				check.focusable = false;
				check.set_parent (this);
				check.toggled.connect (() => {
					if (!binding && item != null)
						list.cell_toggled ((int) item.position, column, check.active);
				});
				break;
			case FastList.CellKind.RATING:
				stars = new Picture ();
				stars.can_shrink = false;
				stars.halign = Align.START;
				stars.set_parent (this);
				break;
			default:
				label = new Label (null);
				label.xalign = 0;
				label.hexpand = true;
				label.ellipsize = Pango.EllipsizeMode.END;
				label.single_line_mode = true;
				label.set_parent (this);
				break;
		}
	}

	public override void dispose () {
		Widget? child;
		while ((child = get_first_child ()) != null)
			child.unparent ();
		base.dispose ();
	}

	/** Reads the value anew */
	public void refresh () {
		if (item == null || item.item == null || list.value_func == null)
			return;
		var m = (Media) item.item;
		int row = (int) item.position;
		Value val = list.value_func (row, column, m);
		binding = true;
		switch (kind) {
			case FastList.CellKind.ICON:
				bool busy = m.showIndicator;
				icon.gicon = (!busy && val.holds (typeof (GLib.Icon))) ? (GLib.Icon?) val.get_object () : null;
				icon.visible = !busy;
				spinner.visible = busy;
				spinner.spinning = busy;
				if (check != null)
					check.active = !m.unchecked;
				break;
			case FastList.CellKind.TOGGLE:
				check.active = val.holds (typeof (bool)) && val.get_boolean ();
				break;
			case FastList.CellKind.RATING:
				stars.paintable = list.stars (val.holds (typeof (int)) ? val.get_int () : 0);
				break;
			default:
				set_text (format (val, m), m);
				break;
		}
		binding = false;
	}

	string format (Value val, Media m) {
		switch (kind) {
			case FastList.CellKind.TEXT:
				return (val.holds (typeof (string)) && val.get_string () != null) ? val.get_string () : "";
			case FastList.CellKind.LENGTH:
				if (m.length <= 0)
					return "";
				return "%u:%02u".printf (m.length / 60, m.length % 60);
			case FastList.CellKind.DATE:
				int date = val.holds (typeof (int)) ? val.get_int () : 0;
				return date <= 0 ? "" : Time.local (date).format ("%m/%e/%Y %l:%M %p");
			case FastList.CellKind.BITRATE:
				int rate = val.holds (typeof (int)) ? val.get_int () : 0;
				return rate <= 0 ? "" : rate.to_string () + _(" kbps");
			default: // NUMBER
				int n = val.holds (typeof (int)) ? val.get_int () : 0;
				return n <= 0 ? "" : n.to_string ();
		}
	}

	void set_text (string text, Media m) {
		if (m.isTemporary && list.is_mixed)
			label.set_markup ("<i>" + Markup.escape_text (text) + "</i>");
		else
			label.label = text;
	}
}
