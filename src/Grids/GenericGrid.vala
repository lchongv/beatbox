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

using Gee;
using Gtk;


public abstract class BeatBox.GenericGrid : FastGrid {
	protected SourceView parent_wrapper;

	// Share popover across multiple grid views. For speed and memory saving
	private static PopupListView? _popup_list_view = null;
	/** Whether the popup was ever made: hiding one that wasn't needn't make it */
	protected static bool has_popup_list { get { return _popup_list_view != null; } }
	
	protected PopupListView popup_list {
		get {
			if (_popup_list_view == null) {
				debug ("Creating Grid view popup");
				_popup_list_view = new PopupListView (this.parent_wrapper);

				// when it loses the focus to the main window, it stays in front
				_popup_list_view.notify["is-active"].connect ( () => {
					if (!_popup_list_view.is_active && popup_list.visible && App.window.has_focus) {
						popup_list.show_all ();
						popup_list.present ();
					}
				});
			}

			return _popup_list_view;
		}
	}

    protected Gdk.Pixbuf default_art;

	// For shuffle
	protected int old_sort_col;
	protected SortType old_sort_dir;
	
	protected TreeViewSetup tvs;
	public int relative_id;
	protected bool is_current_list;
	
	protected bool scrolled_recently;
	protected bool dragging;

	// GTK3 controllers need a reference
	Gtk.GestureMultiPress click_gesture;
	Gtk.EventControllerMotion motion_controller;
	double pointer_x = -1; // where the pointer is, in widget coordinates
	double pointer_y = -1;
	
	public signal void import_requested(LinkedList<Media> to_import);
	

	private const int ITEM_PADDING = 0;
	private const int MIN_SPACING = 24;
	private const int ITEM_WIDTH = Icons.ALBUM_VIEW_IMAGE_SIZE;

	protected GenericGrid(SourceView parent_wrapper, TreeViewSetup tvs, GLib.Object default_value) {
		base(default_value);

        set_parent_wrapper (parent_wrapper);
		this.tvs = tvs;
		
		get_style_context ().add_class ("albumgrid");
		
		item_width = ITEM_WIDTH;
		item_padding = ITEM_PADDING;
		columns = -1; // let GtkIconView fit as many columns as the width allows
		set_column_spacing (MIN_SPACING);
		set_row_spacing (MIN_SPACING);

		// drag source
		TargetEntry te = { "text/uri-list", TargetFlags.SAME_APP, 0};
		drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, { te }, Gdk.DragAction.COPY);
		//enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK, {te}, Gdk.DragAction.COPY);
		
		//row_activated.connect(row_activated_signal);
		//rows_reordered.connect(updateTreeViewSetup);
		App.playback.current_cleared.connect(current_cleared);
		//App.library.media_played.connect(media_played);
		//App.library.medias_updated.connect(medias_updated);


		this.add_events (Gdk.EventMask.POINTER_MOTION_MASK);
		// the pointer's shape follows the item under it, when it moves and when the view scrolls
		motion_controller = new Gtk.EventControllerMotion (this);
		motion_controller.motion.connect ((x, y) => {
			pointer_x = x;
			pointer_y = y;
			set_pointer ();
		});
		motion_controller.leave.connect (() => pointer_x = pointer_y = -1);
		// (the scrolled window around it brings its own adjustment)
		notify["vadjustment"].connect (() => {
			if (vadjustment != null)
				vadjustment.value_changed.connect (set_pointer);
		});

		// CAPTURE: GtkIconView handles the clicks itself and passes none on
		click_gesture = new Gtk.GestureMultiPress (this);
		click_gesture.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		click_gesture.released.connect (on_released);

        // For smart spacing...
		int MIN_N_ITEMS = 2; // we will allocate horizontal space for at least two items
		int TOTAL_ITEM_WIDTH = ITEM_WIDTH + 2 * ITEM_PADDING;
		int TOTAL_MARGIN = MIN_N_ITEMS * (MIN_SPACING + ITEM_PADDING);
		int MIDDLE_SPACE = MIN_N_ITEMS * MIN_SPACING;
		parent_wrapper.set_size_request (MIN_N_ITEMS * TOTAL_ITEM_WIDTH + TOTAL_MARGIN + MIDDLE_SPACE, -1);
	}

	public void set_parent_wrapper(SourceView parent) {
		this.parent_wrapper = parent;
		//vadjustment.value_changed.connect(view_scroll);
	}
	
	public abstract void update_sensitivities();
	
	/** TreeViewColumn header functions. Has to do with sorting and
	 * remembering column widths/sort column/sort direction between
	 * sessions.
	**/
	protected abstract void updateTreeViewSetup();
	
	
	void current_cleared() {
		is_current_list = false;
	}
	
	/***************************************
	 * Simple setters and getters
	 * *************************************/
	public void set_hint(TreeViewSetup.Hint hint) {
		tvs.set_hint(hint);
	}
	
	public TreeViewSetup.Hint get_hint() {
		return tvs.get_hint();
	}
	
	public void set_relative_id(int id) {
		this.relative_id = id;
	}
	
	public int get_relative_id() {
		return relative_id;
	}
	
	public bool get_is_current_list() {
		return is_current_list;
	}

    public abstract void item_activated_handler (Object? selected);

	private void on_released (int n_press, double widget_x, double widget_y) {
		int x, y;
		convert_widget_to_bin_window_coords ((int) widget_x, (int) widget_y, out x, out y);
		TreePath? path;
		CellRenderer cell;

		this.get_item_at_pos (x, y, out path, out cell);

		if (path != null)
			item_activated_handler (get_selected_objects().nth_data (0));
		else
			item_activated_handler (null);
	}

	private void set_pointer () {
		if (pointer_x < 0 || get_window () == null)
			return;
		int x, y;
		convert_widget_to_bin_window_coords ((int) pointer_x, (int) pointer_y, out x, out y);
		TreePath? path;
		CellRenderer cell;

		this.get_item_at_pos (x, y, out path, out cell);

		if (path == null) // blank area
			this.get_window ().set_cursor (null);
		else
			this.get_window ().set_cursor (new Gdk.Cursor.from_name (get_display (), "pointer"));
	}



}
