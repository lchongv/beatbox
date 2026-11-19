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
 */


using Gtk;

/** A grid of covers on a Gtk.GridView (Gtk.IconView is deprecated since GTK 4.10). As
 *  FastList, the grid keeps a table of its objects, sorts it itself and shows the ones the
 *  search lets through; the cells read the cover, the text and the tooltip from the value func. */
[GIR (visible = false)] // internal, not for plugins
public class BeatBox.FastGrid : ScrollableBin {
	protected GridView view;

	protected const int PIXBUF_COLUMN = 0;
	protected const int MARKUP_COLUMN = 1;
	protected const int TOOLTIP_COLUMN = 2;
	protected const int ALBUM_COLUMN = 3;
	
	FastGridModel fm;
	SingleSelection selection;
	HashTable<int, GLib.Object> table; // is not the same object as showing.
	HashTable<int, GLib.Object> showing; // should never point to table.
	internal Gee.HashSet<FastGridCell> bound_cells = new Gee.HashSet<FastGridCell>();
	
	/* user specific function for the cells' values */
	public delegate Value ValueReturnFunc (int row, int column, GLib.Object o);
	internal unowned ValueReturnFunc value_func;
	
	/* sortable stuff */
	public delegate int SortCompareFunc (GLib.Object a, GLib.Object b);
	private unowned SortCompareFunc compare_func;
	
	// search stuff
	string last_search;
	public delegate void ViewSearchFunc (string search, HashTable<int, GLib.Object> table, ref HashTable<int, GLib.Object> showing);
	private unowned ViewSearchFunc search_func;
	
	/** The visible (sorted, searched) objects changed */
	public signal void visible_changed();
	/** An item was clicked (single_click_activate) or got Enter */
	public signal void item_activated(int position);
	
	const string CSS = """
gridview.albumgrid { padding: 12px; }
gridview.albumgrid > child { padding: 12px; border-radius: 6px; }
""";
	
	public FastGrid () {
		UI.add_css(CSS);
		table = new HashTable<int, GLib.Object>(null, null);
		showing = new HashTable<int, GLib.Object>(null, null);
		fm = new FastGridModel();
		selection = new SingleSelection(fm) { autoselect = false, can_unselect = true };
		
		last_search = "";
		
		var factory = new SignalListItemFactory();
		factory.setup.connect((obj) => ((ListItem) obj).child = new FastGridCell(this));
		factory.bind.connect((obj) => {
			var item = (ListItem) obj;
			var cell = (FastGridCell) item.child;
			cell.item = item;
			bound_cells.add(cell);
			cell.refresh();
		});
		factory.unbind.connect((obj) => {
			var cell = (FastGridCell) ((ListItem) obj).child;
			bound_cells.remove(cell);
			cell.item = null;
		});
		
		view = new GridView(selection, factory);
		view.max_columns = 64; // as many as the width allows
		view.activate.connect((position) => item_activated((int) position));
		scroll_child = view;
		
		set_table(table);
	}
	
	/** Should not be manipulated by client */
	public HashTable<int, GLib.Object> get_table() {
		return table;
	}
	
	/** Should not be manipulated by client */
	public HashTable<int, GLib.Object> get_visible_table() {
		return showing;
	}
	
	public GLib.Object get_object_from_index(int index) {
		return showing.get(index);
	}
	
	protected GLib.List<Object> get_selected_objects() {
		var rv = new GLib.List<Object>();
		if(selection.selected_item != null)
			rv.append(selection.selected_item);
		return rv;
	}
	
	protected int count_selected() {
		return selection.selected_item != null ? 1 : 0;
	}
	
	/** The item under (x, y) in this widget's coordinates, -1 for none */
	public int item_at(double x, double y) {
		for(var w = pick(x, y, PickFlags.DEFAULT); w != null && w != this; w = w.get_parent()) {
			if(w is FastGridCell)
				return ((FastGridCell) w).item != null ? (int) ((FastGridCell) w).item.position : -1;
			if(w.get_css_name() == "child") { // the padding around a cell
				var cell = w.get_first_child() as FastGridCell;
				return (cell != null && cell.item != null) ? (int) cell.item.position : -1;
			}
		}
		return -1;
	}
	
	public void select_only(int position) {
		if(position >= 0 && position < fm.get_n_items())
			selection.selected = position;
	}
	
	public void set_value_func(ValueReturnFunc func) {
		value_func = func;
	}
	
	public void set_table (HashTable<int, GLib.Object> table, bool do_resort = true) {
		this.table = table;
		
		if(do_resort)
			resort(); // this also calls search
		else
			do_search(null);
	}
	
	// If a GLib.Object is in objects but not in table, will just ignore
	public void remove_objects (HashTable<GLib.Object, int> objects) {
		int index = 0;
		var new_table = new HashTable<int, GLib.Object>(null, null);
		for(int i = 0; i < table.size(); ++i) {
			GLib.Object o;
			
			// create a new table. if not in objects, and is in table, add it.
			if((o = table.get(i)) != null && objects.get(o) != 1) {
				new_table.set(index++, o);
			}
		}
		
		// no need to resort, just removing
		set_table(new_table, false);
	}
	
	// Does NOT check for duplicates
	public void add_objects (List<GLib.Object> objects) {
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
		
		showing.remove_all();
		if(search != null)
			last_search = search;
		
		search_func(last_search, table, ref showing);
		
		fm.set_table(showing);
		visible_changed();
	}
	
	/** Redraws the cell of an item */
	public void redraw_row (int row_index) {
		foreach(var cell in bound_cells)
			if(cell.item != null && cell.item.position == row_index)
				cell.refresh();
	}
	
	/** Redraws every cell on screen (new covers) */
	public void refresh_all () {
		foreach(var cell in bound_cells)
			cell.refresh();
	}
	
	/** Sorting is done here, not in the model. That way the whole
	 * table is sorted and ready to go and we do not need to resort every
	 * time we repopulate/search the model
	**/
	public void set_compare_func (SortCompareFunc func) {
		compare_func = func;
	}
	
	public void resort () {
		quicksort(0, (int)(table.size() - 1));
		do_search (null);
	}
	
	void swap (int a, int b) {
		GLib.Object temp = table.get(a);
		table.set(a, table.get(b));
		table.set(b, temp);
	}
	
	public void quicksort (int start, int end) {
		if(end <= start)
			return;
		GLib.Object pivot = table.get((start+end)/2);
		int i = start;
		int j = end;
		
		while(i <= j) {
			while(i < end && compare_func (table.get(i), pivot) < 0) ++i;
			while(j > start && compare_func (table.get(j), pivot) > 0) --j;
			if(i <= j) {
				swap(i, j);
				++i; --j;
			}
		}
		
		if(start < j)	quicksort (start, j);
		if(i < end)		quicksort (i, end);
	}
}

/** A cell of a FastGrid: the cover, and the text under it */
[GIR (visible = false)]
public class BeatBox.FastGridCell : Gtk.Box {
	weak FastGrid grid;
	public ListItem? item = null;
	Picture cover;
	Label text;
	
	public FastGridCell (FastGrid grid) {
		Object (orientation: Orientation.VERTICAL, spacing: 4);
		this.grid = grid;
		cover = new Picture();
		cover.can_shrink = false;
		cover.halign = Align.CENTER;
		append(cover);
		text = new Label(null);
		text.justify = Justification.CENTER;
		text.wrap = true;
		text.wrap_mode = Pango.WrapMode.WORD_CHAR;
		text.max_width_chars = 1; // as wide as the cover, not the text
		text.hexpand = false;
		text.width_request = IconsInterface.ALBUM_VIEW_IMAGE_SIZE;
		append(text);
		set_cursor_from_name("pointer");
	}
	
	public void refresh () {
		if(item == null || item.item == null || grid.value_func == null)
			return;
		int row = (int) item.position;
		Value pix = grid.value_func(row, 0, item.item);
		Value markup = grid.value_func(row, 1, item.item);
		Value tooltip = grid.value_func(row, 2, item.item);
		var pixbuf = pix.holds(typeof(Gdk.Pixbuf)) ? (Gdk.Pixbuf?) pix.get_object() : null;
		cover.paintable = (pixbuf != null) ? UI.pixbuf_texture(pixbuf) : null;
		text.set_markup(markup.holds(typeof(string)) && markup.get_string() != null ? markup.get_string() : "");
		tooltip_markup = tooltip.holds(typeof(string)) ? tooltip.get_string() : null;
	}
}
