/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player and Granite Library
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 * Granite Library:      http://www.launchpad.net/granite
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
 * A source list: headings (depth 1) with the pages under them. On a Gtk.ListView over a
 * Gtk.TreeListModel (Gtk.TreeView is deprecated since GTK 4.10); each row is a SideBarItem.
 */

using Gtk;
using Gdk;

/** A row of the side bar: a heading, or a page under one */
public class BeatBox.SideBarItem : GLib.Object {
	public GLib.Object? object;
	public Widget? widget;
	public Gdk.Pixbuf? pixbuf { get; set; }
	public string text { get; set; }
	public bool draggable;
	public bool droppable;
	public bool is_selectable_parent; // a heading shown (and chosen) even with nothing under it
	/** Shown in the side bar: hidden ones keep their place, and their rows under them */
	public bool shown { get; set; default = true; }
	/** Under the pointer of a drag that can drop here */
	public bool highlighted { get; set; default = false; }

	public weak SideBarItem? parent = null;
	public GLib.ListStore children = new GLib.ListStore (typeof (SideBarItem));
	internal CustomFilter filter;
	internal FilterListModel shown_children;

	public SideBarItem () {
		filter = new CustomFilter ((o) => ((SideBarItem) o).shown);
		shown_children = new FilterListModel (children, filter);
	}

	public int depth { get { return parent == null ? 1 : parent.depth + 1; } }
}

public class BeatBox.SideBar : ScrollableBin {
	public ListView view { get; private set; }
	GLib.ListStore roots = new GLib.ListStore (typeof (SideBarItem));
	CustomFilter roots_filter;
	TreeListModel rows;
	SingleSelection selection;
	Gtk.GestureClick side_bar_click;

	SideBarItem? selectedItem = null;
	SideBarItem? highlight_item = null;
	bool quiet = false; // selection changed from code

	public signal void true_selection_change(SideBarItem selected);
	public signal void true_drag_received(SideBarItem item, string[] uris);
	/** A row was double-clicked, or got Enter */
	public signal void item_activated(SideBarItem item);

	public SideBar() {
		roots_filter = new CustomFilter((o) => ((SideBarItem) o).shown);
		rows = new TreeListModel(new FilterListModel(roots, roots_filter), false, true,
			(o) => ((SideBarItem) o).shown_children);
		selection = new SingleSelection(rows) { autoselect = false, can_unselect = true };

		var factory = new SignalListItemFactory();
		factory.setup.connect((o) => ((ListItem) o).child = new SideBarRow());
		factory.bind.connect((o) => {
			var li = (ListItem) o;
			var row = (TreeListRow) li.item;
			var item = (SideBarItem) row.item;
			((SideBarRow) li.child).bind(item, row, li);
			// headings are not chosen (unless they stand for a page)
			li.selectable = li.activatable = (item.depth > 1 || item.is_selectable_parent);
		});
		factory.unbind.connect((o) => ((SideBarRow) ((ListItem) o).child).unbind());

		view = new ListView(selection, factory);
		view.name = "SidebarContent";
		view.single_click_activate = false;
		view.activate.connect((position) => {
			var item = item_at_position(position);
			if(item != null)
				item_activated(item);
		});
		scroll_child = view;

		selection.notify["selected"].connect(selectionChange);
		// CAPTURE: before the list handles the press (selection)
		side_bar_click = new Gtk.GestureClick();
		side_bar_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		side_bar_click.pressed.connect(sideBarClick);
		view.add_controller(side_bar_click);

		// drag and drop: only strings, i.e. the "\n" joined uris of the rows dragged inside
		// BeatBox. Files from outside are not accepted (as the old SAME_APP target)
		var dest = new Gtk.DropTarget(typeof(string), Gdk.DragAction.COPY);
		dest.motion.connect(drag_motion_signal);
		dest.leave.connect(drag_leave_signal);
		dest.drop.connect(drag_received);
		view.add_controller(dest);
	}

	/* Convenient add/remove/edit methods */
	public SideBarItem addItem(SideBarItem? parent, SideBarItem? before, GLib.Object? o, Widget? w,
							Gdk.Pixbuf? pixbuf, string text, Gdk.Pixbuf? clickable,
							bool draggable, bool droppable,
							bool is_selectable_parent) {
		var item = new SideBarItem();
		item.object = o;
		item.widget = w;
		item.pixbuf = pixbuf;
		item.text = text;
		item.draggable = draggable;
		item.droppable = droppable;
		item.is_selectable_parent = is_selectable_parent;
		item.parent = parent;
		// a heading shows once something is under it
		item.shown = parent != null || is_selectable_parent;

		var store = (parent != null) ? parent.children : roots;
		uint position = 0;
		if(before == null || !store.find(before, out position))
			position = store.get_n_items();
		store.insert(position, item);

		if(parent != null)
			setVisibility(parent, true);

		return item;
	}

	public bool removeItem(SideBarItem item) {
		var store = (item.parent != null) ? item.parent.children : roots;
		uint position = 0;
		if(!store.find(item, out position))
			return false;
		if(item == selectedItem)
			selectedItem = null;
		store.remove(position);

		var parent = item.parent;
		if(parent != null)
			setVisibility(parent, store.get_n_items() > 0 || parent.is_selectable_parent);
		return true;
	}

	public void setVisibility(SideBarItem item, bool val) {
		if(item.shown == val)
			return;
		item.shown = val;
		var filter = (item.parent != null) ? item.parent.filter : roots_filter;
		filter.changed(val ? FilterChange.LESS_STRICT : FilterChange.MORE_STRICT);
		reselect();
	}

	public void setName(SideBarItem item, string name) {
		item.text = name;
	}

	public bool setNameFromObject(SideBarItem parent, GLib.Object o, string name) {
		var item = getItemFromObject(parent, o);
		if(item == null)
			return false;
		item.text = name;
		return true;
	}

	public SideBarItem? getSelectedItem() {
		return selection.selected_item != null ? (SideBarItem) ((TreeListRow) selection.selected_item).item : null;
	}

	public void setSelectedItem(SideBarItem? item) {
		if(item == null || item == selectedItem)
			return;

		selectedItem = item;
		reselect();
		true_selection_change(item);
	}

	/** Every heading open: the old tree showed all rows */
	public void expand_all() {
		for(uint i = 0; i < rows.get_n_items(); i++) {
			var row = rows.get_row(i);
			if(row != null && row.expandable)
				row.expanded = true;
		}
	}

	public GLib.Object? getObject(SideBarItem item) {
		return item.object;
	}

	public Widget? getWidget(SideBarItem item) {
		return item.widget;
	}

	public SideBarItem? getItemFromObject(SideBarItem parent, GLib.Object o) {
		for(uint i = 0; i < parent.children.get_n_items(); i++) {
			var item = (SideBarItem) parent.children.get_item(i);
			if(item.object == o)
				return item;
		}
		return null;
	}

	public Widget? getSelectedWidget() {
		var item = getSelectedItem();
		return item != null ? item.widget : null;
	}

	public Object? getSelectedObject() {
		var item = getSelectedItem();
		return item != null ? item.object : null;
	}

	/** The row of an item, or INVALID_LIST_POSITION while it (or a heading over it) is hidden */
	uint position_of(SideBarItem item) {
		for(uint i = 0; i < rows.get_n_items(); i++) {
			var row = rows.get_row(i);
			if(row != null && row.item == item)
				return i;
		}
		return INVALID_LIST_POSITION;
	}

	SideBarItem? item_at_position(uint position) {
		var row = rows.get_row(position);
		return row != null ? (SideBarItem) row.item : null;
	}

	/** Puts the selection back on the chosen item (rows come and go as headings show and hide) */
	void reselect() {
		uint position = (selectedItem != null) ? position_of(selectedItem) : INVALID_LIST_POSITION;
		if(selection.selected == position)
			return;
		quiet = true;
		selection.selected = position;
		quiet = false;
	}

	/* stops user from selecting the root nodes */
	void selectionChange() {
		if(quiet)
			return;
		var pending = getSelectedItem();
		if(pending == null || (pending.depth == 1 && !pending.is_selectable_parent)) {
			// nothing, or a heading: back to the last chosen
			Idle.add(() => { reselect(); return false; });
			return;
		}
		if(pending != selectedItem) {
			selectedItem = pending;
			true_selection_change(pending);
		}
	}

	/** The item under a point of the list */
	public SideBarItem? item_at(double x, double y) {
		var w = view.pick(x, y, PickFlags.DEFAULT);
		while(w != null && w != view) {
			if(w is SideBarRow)
				return ((SideBarRow) w).item;
			var child = w.get_first_child(); // the row around it (its padding)
			if(child is SideBarRow)
				return ((SideBarRow) child).item;
			w = w.get_parent();
		}
		return null;
	}

	/* click event functions: a click on a heading opens or closes it */
	void sideBarClick(int n_press, double x, double y) {
		if(side_bar_click.get_current_button() != 1)
			return;
		var item = item_at(x, y);
		if(item == null || item.depth != 1)
			return;
		uint position = position_of(item);
		var row = (position != INVALID_LIST_POSITION) ? rows.get_row(position) : null;
		if(row != null && row.expandable)
			row.expanded = !row.expanded;
	}

	/** The item a drop at a point goes to: the row, or its heading if that takes drops */
	SideBarItem? drop_item_at(double x, double y) {
		var item = item_at(x, y);
		if(item == null)
			return null;
		if(item.droppable)
			return item;
		if(item.parent != null && item.parent.droppable)
			return item.parent;
		return null;
	}

	void set_highlight(SideBarItem? item) {
		if(highlight_item == item)
			return;
		if(highlight_item != null)
			highlight_item.highlighted = false;
		highlight_item = item;
		if(item != null)
			item.highlighted = true;
	}

	Gdk.DragAction drag_motion_signal(double x, double y) {
		set_highlight(drop_item_at(x, y));
		return (highlight_item != null) ? Gdk.DragAction.COPY : 0;
	}

	void drag_leave_signal() {
		set_highlight(null);
	}

	bool drag_received(GLib.Value value, double x, double y) {
		string[] uris = value.get_string().split("\n");
		var item = drop_item_at(x, y);
		set_highlight(null);
		if(item == null)
			return false;
		message("Drag dropped on %s\n", item.text);
		true_drag_received(item, uris);
		return true;
	}

}// END CLASS

/**
 * One row of the side bar, drawn as the GTK 3 renderer did: headings in small grey capitals with
 * a triangle at the right, pages with their icon (symbolic ones in the text's color) and name.
 */
public class BeatBox.SideBarRow : Gtk.Widget {
	public static int EXPANDER_SIZE = 8;
	public static int DEPTH_INDENT_SIZE = 8;

	public SideBarItem? item { get; private set; default = null; }
	TreeListRow? list_row = null;
	ulong item_changed = 0;
	ulong row_changed = 0;

	static HashTable<Pixbuf, bool> monochrome = new HashTable<Pixbuf, bool>(direct_hash, direct_equal);

	internal void bind(SideBarItem item, TreeListRow row, ListItem li) {
		unbind();
		this.item = item;
		list_row = row;
		item_changed = item.notify.connect(() => { queue_resize(); queue_draw(); });
		row_changed = row.notify["expanded"].connect(() => queue_draw());
		tooltip_text = null;
		queue_resize();
	}

	internal void unbind() {
		if(item != null && item_changed != 0)
			item.disconnect(item_changed);
		if(list_row != null && row_changed != 0)
			list_row.disconnect(row_changed);
		item_changed = row_changed = 0;
		item = null;
		list_row = null;
	}

	public override void dispose() {
		unbind();
		base.dispose();
	}

	/** True for symbolic icons: every visible pixel is a shade of grey */
	static bool is_monochrome(Pixbuf pix) {
		if(monochrome.contains(pix))
			return monochrome[pix];
		bool result = pix.has_alpha && pix.n_channels == 4;
		unowned uint8[] px = pix.get_pixels_with_length();
		for(int y = 0; result && y < pix.height; y++) {
			for(int x = 0; x < pix.width; x++) {
				int i = y * pix.rowstride + x * 4;
				if(px[i + 3] > 64 && (((int)px[i] - px[i + 1]).abs() > 12 || ((int)px[i + 1] - px[i + 2]).abs() > 12)) {
					result = false;
					break;
				}
			}
		}
		monochrome[pix] = result;
		return result;
	}

	static string heading_color() {
		RGBA c = UI.named_color("bb_sidebar_heading");
		return "#%02x%02x%02x".printf((int)(c.red * 255), (int)(c.green * 255), (int)(c.blue * 255));
	}

	Pango.Layout make_layout() {
		var layout = create_pango_layout(null);
		if(item == null)
			return layout;
		if(item.depth > 1)
			layout.set_text(item.text, -1);
		else
			layout.set_markup("<span size='small' weight='bold' foreground='%s'>".printf(heading_color()) + Markup.escape_text(item.text.up()) + "</span>", -1);
		return layout;
	}

	public override SizeRequestMode get_request_mode() {
		return SizeRequestMode.CONSTANT_SIZE;
	}

	public override void measure(Orientation orientation, int for_size, out int minimum, out int natural,
	                             out int minimum_baseline, out int natural_baseline) {
		minimum_baseline = natural_baseline = -1;
		if(orientation == Orientation.HORIZONTAL) {
			// as narrow as the side bar is made: the text is cut at its edge
			int w = 0, h;
			if(item != null) {
				make_layout().get_pixel_size(out w, out h);
				w += item.depth * DEPTH_INDENT_SIZE + ((item.depth > 1) ? 20 : EXPANDER_SIZE + 6);
			}
			minimum = 1;
			natural = w;
		}
		else {
			int dumby;
			create_pango_layout("Test").get_pixel_size(out dumby, out minimum);
			minimum += 6 + UI.GTK3_ROW_EXTRA; // 3 px extra on each side for the text
			natural = minimum;
		}
	}

	public override void snapshot(Gtk.Snapshot s) {
		if(item == null)
			return;
		int width = get_width(), height = get_height();
		var r = Graphene.Rect();
		r.init(0, 0, width, height);
		var context = s.append_cairo(r);

		int depth = item.depth;
		var pix = item.pixbuf;
		var layout = make_layout();
		// the row's CSS color: the skin's text, or the selection's
		RGBA rgba = get_color();
		bool rtl = get_direction() == Gtk.TextDirection.RTL;

		// Draw a blank space for each level of indent
		double start_x = depth * DEPTH_INDENT_SIZE;
		double start_y = 3 + UI.GTK3_ROW_EXTRA / 2;
		if(rtl)
			start_x = width - start_x;

		// Draw picture if it is not level 1
		if(depth != 1 && pix != null) {
			int image_y = (height - pix.height > 0) ? ((height - pix.height)/2) : 0;
			UI.set_source_pixbuf (context, pix, (int)(rtl ? start_x - pix.width : start_x), image_y);
			if(is_monochrome(pix)) {
				// symbolic icon: paint it in the text color (white when selected, light on dark skins)
				var icon = context.get_source();
				context.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha);
				context.mask(icon);
			}
			else {
				context.paint();
			}

			start_x += rtl ? -20.0 : 20.0; // for rtl, move to the left. otherwise move to right
		}

		// Draw text
		context.set_source_rgba (rgba.red, rgba.green, rgba.blue, rgba.alpha);
		if(rtl)
			layout.set_alignment(Pango.Alignment.RIGHT);

		Pango.Rectangle ink;
		Pango.Rectangle extents;
		layout.get_pixel_extents(out ink, out extents);

		context.move_to(rtl ? (start_x - extents.width) : start_x, start_y);
		Pango.cairo_show_layout(context, layout);

		// If it is supposed to be highlighted, draw the highlight
		if(item.highlighted)
			draw_highlight(context, 0, 0, width, height);

		// Draw the expander: a small triangle in the heading's color, pointing down when expanded
		// and to the side when collapsed
		if(depth == 1 && item.shown_children.get_n_items() > 0 && list_row != null) {
			// as small and as high in the row as the GTK3 themes drew it
			double size = 5, x = rtl ? 3 : width - EXPANDER_SIZE;
			double y = 5;
			var color = Gdk.RGBA();
			color.parse(heading_color());
			Gdk.cairo_set_source_rgba(context, color);
			if(list_row.expanded) {
				context.move_to(x, y + 1);
				context.line_to(x + size, y + 1);
				context.line_to(x + size / 2, y + size - 1);
			}
			else {
				double tip = rtl ? x : x + size, back = rtl ? x + size - 1 : x + 1;
				context.move_to(back, y);
				context.line_to(back, y + size);
				context.line_to(tip - (rtl ? -1 : 1), y + size / 2);
			}
			context.close_path();
			context.fill();
		}
	}

	void draw_highlight(Cairo.Context context, double x, double y, double width, double height) {
		double corner_radius = (height * 2) / 10.0;   /* and corner curvature radius */
		double radius = corner_radius;
		double degrees = Math.PI / 180.0;
		x += 1.5; y += 1.5; width -= 3; height -= 3;

		context.new_sub_path();
		context.arc (x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees);
		context.arc (x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees);
		context.arc (x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees);
		context.arc (x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
		context.close_path();

		context.set_source_rgba (0.0, 0.3, 1.0, 0.1);
		context.fill_preserve ();
		context.set_source_rgb (0.0, 0.0, 1);
		context.set_line_width (3.0);
		context.stroke ();
	}
}
