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

public class BeatBox.AdvancedSearchBox : Gtk.Entry {
	PopMenu search_suggester;
	Gtk.EventControllerKey suggester_keys; // GTK3 controllers need a reference
	bool listen_for_change;
	string last_search;
	
	View current_view;
	HashTable<View, string> views_search;
	
	public AdvancedSearchBox() {
		placeholder_text = _("Search...");
		// what GTK 3's search entry drew: a lens, and a clear button while there is text (GTK 4 leaves it to the entry)
		set_icon_from_icon_name (Gtk.EntryIconPosition.PRIMARY, "system-search-symbolic");
		set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, "edit-clear-symbolic");
		icon_press.connect ((entry, pos) => { if (pos == Gtk.EntryIconPosition.SECONDARY) set_text (""); });
		changed.connect (() => set_icon_from_icon_name (Gtk.EntryIconPosition.SECONDARY, get_text () == "" ? null : "edit-clear-symbolic"));
		
		search_suggester = new PopMenu();
		search_suggester.set_size_request (Icons.ALBUM_VIEW_IMAGE_SIZE, -1);
		
		listen_for_change = true;
		views_search = new HashTable<View, string>(null, null);
		
		this.changed.connect(search_field_changed);
		this.activate.connect(search_field_activate);
		// CAPTURE: before the menu's own key handling
		suggester_keys = new Gtk.EventControllerKey();
		suggester_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		suggester_keys.key_pressed.connect(keyPressed);
		((Gtk.Widget) search_suggester).add_controller (suggester_keys);
		App.window.view_changed.connect(view_changed);
	}
	
	void view_changed(View view) {
		if(current_view != null) {
			views_search.set(current_view, get_text());
		}
		
		current_view = view;
		
		if(views_search.get(current_view) != null) {
			listen_for_change = false;
			set_text(views_search.get(current_view));
			listen_for_change = true;
		}
	}
	
	void search_field_activate() {
		View view = App.window.get_current_view();
		
		if(view.supports_search()) {
			view.search_activated(get_text());
		}
	}
	
	void search_field_changed() {
		if(!listen_for_change) {
			return;
		}
		
		View view = App.window.get_current_view();
		var new_search = get_text();
		last_search = new_search;
		
		if(view.supports_search()) {
			// First notify that the search field changed
			view.search_changed(new_search);
			
			// Now to show the menu. Do so in a thread since it can take
			// a while potentially (analyzing, fetching to web).
			if(new_search == "") {
				clear_menu();
				search_suggester.popdown ();
			}
			else {
				if(view.requested_search_timeout() == 0) {
					start_show_menu_process(new_search);
				}
				else {
					Timeout.add(view.requested_search_timeout(), () => {
						start_show_menu_process(new_search);
						
						return false;
					});
				}
			}
		}
	}
	
	void start_show_menu_process(string search) {
		if(search == last_search && search.length > 2) {
			try {
				new Thread<void*>.try (null, update_contents);
			} catch (Error err) {
				warning ("Could not create search suggester thread: %s", err.message);
			}
		}
		else if(search.length <= 2) {
			clear_menu();
			search_suggester.popdown ();
		}
	}
	
	// go through visible table and find top tracks, albums, artists, genres.
	void* update_contents() {
		var new_menu_items = App.window.get_current_view().get_search_menu(last_search);
		
		Idle.add( () => {
			if(new_menu_items != null) {
				clear_menu();
				foreach(var item in new_menu_items) {
					search_suggester.append(item);
				}
				
				search_suggester.popup_under(this);
			}
			
			return false;
		});
		
		return null;
	}
	
	public void clear_menu() {
		UI.clear (search_suggester);
	}
	
	bool keyPressed(uint keyval, uint keycode, Gdk.ModifierType state) {
		// Handled here: letting the menu pass the key on typed every letter twice
		if(keyval == Gdk.Key.BackSpace) { //backspace
			backspace ();
			return true;
		}
		else {
			unichar c = Gdk.keyval_to_unicode (keyval);
			string str = c.to_string ();
			if(Regex.match_simple("[a-zA-Z0-9]", str) || 
					str == "-" || str == "-" || str == "&" ||
					str == "(" || str == ")" || str == "/" ||
					str == "." || str == "!" || str == "?" ||
					str == " ") {
				insert_at_cursor(str);
				return true;
			}
		}

		return false;
	}
	
	void backspace () {
		int pos = get_position ();
		if (pos <= 0)
			return;
		string text = get_text ();
		int start = text.index_of_nth_char (pos - 1);
		int end = text.index_of_nth_char (pos);
		set_text (text.substring (0, start) + text.substring (end));
		set_position (pos - 1);
	}
	
	void insert_at_cursor (string str) {
		int pos = get_position ();
		string text = get_text ();
		int at = text.index_of_nth_char (pos);
		set_text (text.substring (0, at) + str + text.substring (at));
		set_position (pos + str.char_count ());
	}
}
