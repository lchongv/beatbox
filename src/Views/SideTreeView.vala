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
	HashMap<View, SideBarItem?> view_to_iter;
	
	public SideBarItem library_iter {get; private set;}
	public SideBarItem library_music_iter {get; private set;}
	public SideBarItem library_podcasts_iter {get; private set;}
	public SideBarItem library_audiobooks_iter {get; private set;}
	public SideBarItem? library_duplicates_iter {get; private set;}

	public SideBarItem devices_iter {get; private set;}
	public SideBarItem devices_cdrom_iter {get; private set;}
	
	public SideBarItem network_iter {get; private set;}
	public SideBarItem network_radio_iter {get; private set;}
	public SideBarItem network_store_iter {get; private set;}
	
	public SideBarItem playlists_iter {get; private set;}
	public SideBarItem playlists_queue_iter {get; private set;}
	public SideBarItem playlists_history_iter {get; private set;}
	public SideBarItem playlists_similar_iter {get; private set;}
	
	public SideBarItem plugins_iter { get; private set; }
	
	GLib.Menu libraryMenu;
	GLib.Menu playlistMenu;
	Gtk.GestureClick side_list_click; // GTK3 controllers need a reference
	
	public SideTreeView() {
		view_to_iter = new HashMap<View, SideBarItem?>();

		// Setup theming
		view.add_css_class ("sidebar");
		
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
		side_list_click = new Gtk.GestureClick();
		side_list_click.button = 0;
		side_list_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		side_list_click.pressed.connect(sideListClick);
		view.add_controller(side_list_click);
		this.item_activated.connect(sideListDoubleClick);
		this.true_selection_change.connect(side_list_selection_change);
		this.true_drag_received.connect(true_drag_received_signal);
		
		addBasicItems ();
	}

	/**
	 * Adds the different sidebar categories.
	 */
	private void addBasicItems() {
		// headed by the open library's name (LibrarySwitcher)
		library_iter = addItem(null, null, null, null, null, LibrarySwitcher.name_of(App.settings.main.library), null, false, false, false);
		App.settings.main.notify["library-name"].connect(() => setName(library_iter, LibrarySwitcher.name_of(App.settings.main.library)));
		devices_iter = addItem(null, null, null, null, null, _("Devices"), null, false, false, false);
		network_iter = addItem(null, null, null, null, null, _("Network"), null, false, false, false);
		plugins_iter = addItem(null, null, null, null, null, _("Plugins"), null, false, false, false);
		playlists_iter = addItem(null, null, null, null, null, _("Playlists"), null, false, false, false);
	}
	
	// TODO: Make this properly recursive
	public void add_view(View view) {
		SideBarItem? added = addItem(convert_category_to_iter(view.get_sidetree_category()), get_proper_before(view), 
								 view.get_object(), view, view.get_view_icon(), view.get_view_name(),
								 null, false, view.can_receive_drop(), false);
		
		view_to_iter.set(view, added);
		
		// We add all the iter items here, and let LW handle adding them to the notebook
		if(view.get_sub_views() != null) {
			foreach(View sub_view in view.get_sub_views()) {
				SideBarItem sub_added = addItem(added, null, sub_view.get_object(), sub_view, sub_view.get_view_icon(), sub_view.get_view_name(),
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
	
	private SideBarItem? convert_category_to_iter(SideTreeCategory category) {
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
	private SideBarItem? get_proper_before(View view) {
		SideBarItem? before_iter = null;

		// Decide which category to use
		switch (view.get_view_type()) {
			case View.ViewType.PLAYLIST:
				string name = ((BasePlaylist)view.get_object()).name;
				for(uint i = 0; i < playlists_iter.children.get_n_items(); i++) {
					var pivot = (SideBarItem) playlists_iter.children.get_item(i);
					if(pivot.object != null && pivot.object is StaticPlaylist && pivot.text > name) {
						before_iter = pivot;
						break;
					}
				}
				break;
			case View.ViewType.SMART_PLAYLIST:
				string name = ((BasePlaylist)view.get_object()).name;
				for(uint i = 0; i < playlists_iter.children.get_n_items(); i++) {
					var pivot = (SideBarItem) playlists_iter.children.get_item(i);
					if(pivot.object != null && ((pivot.object is StaticPlaylist) || pivot.text > name)) {
						before_iter = pivot;
						break;
					}
				}
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
		
		SideBarItem? to_remove = view_to_iter.get(view);
		//view_to_iter.unset(view);
		if(to_remove != null) {
			removeItem(to_remove);
		}
	}
	
	// This will get executed twice when user selects a view by clicking on
	// the sidetree, but in all other cases this gets called once.
	public void select_view(View view) {
		SideBarItem? iter = view_to_iter.get(view);
		
		if(iter != null) {
			setSelectedItem(iter);
		}
		else {
			warning("Could not find an iter for view %s", view.name);
		}
	}
	
	void sideListClick(int n_press, double x, double y) {
		uint button = side_list_click.get_current_button();
		var item = item_at(x, y);
		if(item == null)
			return;
		
		if(item.parent != null) {
			View view = (View)item.widget;
			if(button == 3) {
				if(view.get_context_menu() != null) {
					UI.popup_menu_model(this, view.get_context_menu(), x, y, view.get_context_actions());
				}
			}
			else if(button == 2) {
				if(view.can_set_as_current_list()) {
					view.set_as_current_list(null);
				}
			}
		}
		else if(button == 3) {
			if(item == library_iter) {
				if(App.actions.show_duplicates.get_enabled()) // its only item, hidden while duplicates are shown
					UI.popup_menu_model(this, libraryMenu, x, y);
			}
			else if(item == playlists_iter) {
				UI.popup_menu_model(this, playlistMenu, x, y);
			}
		}
	}
	
	void sideListDoubleClick(SideBarItem item) {
		View? view = item.widget as View;
		if(view != null && view.can_set_as_current_list()) {
			view.play_first_media();
		}
	}
	
	public void reset_view() {
		SideBarItem? iter = null;
		
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
	
	void true_drag_received_signal(SideBarItem iter, string[] uris) {
		Widget w = getWidget(iter);
		View view = (View)w;

		if(view.can_receive_drop()) {
			view.drag_received(uris);
		}
	}
}
