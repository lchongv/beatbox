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
using Gee;

public class BeatBox.SideTreeView : BeatBox.SideBar {
	HashMap<View, TreeIter?> view_to_iter;
	
	public TreeIter library_iter {get; private set;}
	public TreeIter library_music_iter {get; private set;}
	public TreeIter library_podcasts_iter {get; private set;}
	public TreeIter library_audiobooks_iter {get; private set;}
	public TreeIter? library_duplicates_iter {get; private set;}

	public TreeIter devices_iter {get; private set;}
	public TreeIter devices_cdrom_iter {get; private set;}
	
	public TreeIter network_iter {get; private set;}
	public TreeIter network_radio_iter {get; private set;}
	public TreeIter network_store_iter {get; private set;}
	
	public TreeIter playlists_iter {get; private set;}
	public TreeIter playlists_queue_iter {get; private set;}
	public TreeIter playlists_history_iter {get; private set;}
	public TreeIter playlists_similar_iter {get; private set;}
	
	public TreeIter plugins_iter { get; private set; }
	
	GLib.Menu libraryMenu;
	GLib.Menu playlistMenu;
	Gtk.GestureMultiPress side_list_click; // GTK3 controllers need a reference
	
	public SideTreeView() {
		view_to_iter = new HashMap<View, TreeIter?>();

		// Setup theming
		get_style_context().add_class (STYLE_CLASS_SIDEBAR);
		
		buildUI();
	}
	
	public void buildUI() {
		libraryMenu = new GLib.Menu();
		libraryMenu.append_item(App.actions.model_item(App.actions.show_duplicates));
		
		playlistMenu = new GLib.Menu();
		playlistMenu.append_item(App.actions.model_item(App.actions.create_playlist));
		playlistMenu.append_item(App.actions.model_item(App.actions.create_smart_playlist));
		playlistMenu.append_item(App.actions.model_item(App.actions.import_playlist));
		
		// CAPTURE: before the tree view handles the press (selection)
		side_list_click = new Gtk.GestureMultiPress(this);
		side_list_click.button = 0;
		side_list_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		side_list_click.pressed.connect(sideListClick);
		this.row_activated.connect(sideListDoubleClick);
		this.true_selection_change.connect(side_list_selection_change);
		this.true_drag_received.connect(true_drag_received_signal);
		
		this.expand_all();
		
		addBasicItems ();
	}

	/**
	 * Adds the different sidebar categories.
	 */
	private void addBasicItems() {
		library_iter = addItem(null, null, null, null, null, _("Library"), null, false, false, false);
		devices_iter = addItem(null, null, null, null, null, _("Devices"), null, false, false, false);
		network_iter = addItem(null, null, null, null, null, _("Network"), null, false, false, false);
		plugins_iter = addItem(null, null, null, null, null, _("Plugins"), null, false, false, false);
		playlists_iter = addItem(null, null, null, null, null, _("Playlists"), null, false, false, false);
	}
	
	// TODO: Make this properly recursive
	public void add_view(View view) {
		TreeIter? added = addItem(convert_category_to_iter(view.get_sidetree_category()), get_proper_before(view), 
								 view.get_object(), view, view.get_view_icon(), view.get_view_name(),
								 null, false, view.can_receive_drop(), false);
		
		view_to_iter.set(view, added);
		
		// We add all the iter items here, and let LW handle adding them to the notebook
		if(view.get_sub_views() != null) {
			foreach(View sub_view in view.get_sub_views()) {
				TreeIter sub_added = addItem(added, null, sub_view.get_object(), sub_view, sub_view.get_view_icon(), sub_view.get_view_name(),
					 null, false, sub_view.can_receive_drop(), false);
				
				view_to_iter.set(sub_view, sub_added);
			}
		}
		
		// FIXME: Without recursion, this logic is only
		// applied to view, not to sub_view's
		var hint = view.get_view_type();
		if(hint == View.ViewType.MUSIC) {
			library_music_iter = added;
		}
		else if(hint == View.ViewType.PODCAST) {
			library_podcasts_iter = added;
		}
		else if(hint == View.ViewType.AUDIOBOOK) {
			library_audiobooks_iter = added;
		}
		else if(hint == View.ViewType.DUPLICATES) {
			library_duplicates_iter = added;
		}
		else if(hint == View.ViewType.CDROM) {
			devices_cdrom_iter = added;
		}
		else if(hint == View.ViewType.STORE) {
			network_store_iter = added;
		}
		else if(hint == View.ViewType.STATION) {
			network_radio_iter = added;
		}
		else if(hint == View.ViewType.SIMILAR) {
			playlists_similar_iter = added;
		}
		else if(hint == View.ViewType.QUEUE) {
			playlists_queue_iter = added;
		}
		else if(hint == View.ViewType.HISTORY) {
			playlists_history_iter = added;
		}
	}
	
	private TreeIter? convert_category_to_iter(SideTreeCategory category) {
		switch(category) {
			case SideTreeCategory.LIBRARY:
				return library_iter;
			case SideTreeCategory.DEVICE:
				return devices_iter;
			case SideTreeCategory.NETWORK:
				return network_iter;
			case SideTreeCategory.PLUGIN:
				return plugins_iter;
			case SideTreeCategory.PLAYLIST:
				return playlists_iter;
			default:
				error("Unknown SideTreeCategory supplied from view: %s", category.to_string());
		}
	}
	
	// TODO: Abstract this to View api? If I do, could cause unwanted behavior
	// from 3rd party plugins
	private TreeIter? get_proper_before(View view) {
		TreeIter? before_iter = null;

		// Decide which category to use
		switch (view.get_view_type()) {
			case View.ViewType.PLAYLIST:
				string name = ((BasePlaylist)view.get_object()).name;
				TreeIter pivot;
				tree.iter_children(out pivot, playlists_iter);
				
				do {
					string tempName;
					GLib.Object tempO;
					tree.get(pivot, SideBarColumn.COLUMN_OBJECT, out tempO, SideBarColumn.COLUMN_TEXT, out tempName);
					
					if(tempO != null && tempO is StaticPlaylist && tempName > name) {
						before_iter = pivot;
						break;
					}
					else if(!tree.iter_next(ref pivot)) {
						break;
					}
					
				} while(true);
				
				break;
			case View.ViewType.SMART_PLAYLIST:
				string name = ((BasePlaylist)view.get_object()).name;
				TreeIter pivot;
				tree.iter_children(out pivot, playlists_iter);
				
				do {
					string tempName;
					GLib.Object tempO;
					tree.get(pivot, SideBarColumn.COLUMN_OBJECT, out tempO, SideBarColumn.COLUMN_TEXT, out tempName);
					
					if(tempO != null && ((tempO is StaticPlaylist) || tempName > name)) {
						before_iter = pivot;
						break;
					}
					else if(!tree.iter_next(ref pivot)) {
						break;
					}
					
				} while(true);
				
				break;
			default:
				break;
		}

		return before_iter;
	}
	
	// Reorders the view in the sidebar based on its
	// ordering method. Currently used only by playlists
	public void update_view_position(View view) {
		remove_view(view);
		add_view(view);
	}
	
	// We remove the sub views first
	public void remove_view(View view) {
		/*if(view.get_sub_views() != null) {
			foreach(View sub_view in view.get_sub_views()) {
				remove_view(sub_view);
			}
		}*/
		
		var hint = view.get_view_type();
		if(hint == View.ViewType.DUPLICATES) {
			library_duplicates_iter = null;
		}
		
		TreeIter? to_remove = view_to_iter.get(view);
		//view_to_iter.unset(view);
		if(to_remove != null) {
			removeItem(to_remove);
		}
	}
	
	// This will get executed twice when user selects a view by clicking on
	// the sidetree, but in all other cases this gets called once.
	public void select_view(View view) {
		TreeIter? iter = view_to_iter.get(view);
		
		if(iter != null) {
			setSelectedIter(convertToFilter(iter));
		}
		else {
			warning("Could not find an iter for view %s", view.name);
		}
	}
	
	void sideListClick(int n_press, double widget_x, double widget_y) {
		uint button = side_list_click.get_current_button();
		int x, y;
		convert_widget_to_bin_window_coords((int)widget_x, (int)widget_y, out x, out y);
		TreeIter iter;
		TreePath path;
		TreeViewColumn column;
		int cell_x;
		int cell_y;
		
		this.get_path_at_pos(x, y, out path, out column, out cell_x, out cell_y);
		if(path == null)
			return;
		
		if(!filter.get_iter(out iter, path))
			return;
		
		TreeIter parent;
		if(filter.iter_parent(out parent, iter)) {
			Widget w;
			filter.get(iter, SideBarColumn.COLUMN_WIDGET, out w);
			
			View view = (View)w;
			if(button == 3) {
				if(view.get_context_menu() != null) {
					UI.popup_menu_model(this, view.get_context_menu(), widget_x, widget_y, view.get_context_actions());
				}
			}
			else if(button == 2) {
				if(view.can_set_as_current_list()) {
					view.set_as_current_list(null);
				}
			}
		}
		else {
			if(button == 3) {
				if(iter == convertToFilter(library_iter)) {
					if(App.actions.show_duplicates.get_enabled()) // its only item, hidden while duplicates are shown
						UI.popup_menu_model(this, libraryMenu, widget_x, widget_y);
				}
				else if(iter == convertToFilter(playlists_iter)) {
					UI.popup_menu_model(this, playlistMenu, widget_x, widget_y);
				}
			}
		}
	}
	
	void sideListDoubleClick(TreePath path, TreeViewColumn column) {
		TreeIter iter_f;
		TreeIter iter;
		
		if(!filter.get_iter(out iter_f, path))
			return;
			
		iter = convertToChild(iter_f);
			
		Widget w = getWidget(iter);
		View view = (View)w;
		
		if(view.can_set_as_current_list()) {
			view.play_first_media();
		}
	}
	
	public void reset_view() {
		TreeIter? iter = null;
		
        if(App.playback.current_media == null || App.playback.current_media is Song) {
			iter = library_music_iter;
		}
		else if(App.playback.current_media is Podcast) {
			iter = library_podcasts_iter;
		}
		else if(App.playback.current_media is Podcast) {
			iter = library_music_iter;
		}
		else if(App.playback.current_media is Station) {
			iter = network_radio_iter;
		}

        if (iter != null) {
            Widget w = getWidget(iter);
			App.window.set_active_view ((View)w);
        }
        else {
            critical ("Couldn't select an iter for the sidebar. Library iters must be invalid.");
		}
	}

	// Sets the current sidebar item as the active view
	public void side_list_selection_change () {
		var w = getSelectedWidget ();
		
		// Switch to that view in the library window
		App.window.set_active_view ((View)w);
	}
	
	void true_drag_received_signal(TreeIter iter, Gtk.SelectionData data) {
		Widget w = getWidget(convertToChild(iter));
		View view = (View)w;
		
		if(view.can_receive_drop()) {
			view.drag_received(data);
		}
	}
}
