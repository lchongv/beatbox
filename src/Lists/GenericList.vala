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

public abstract class BeatBox.GenericList : FastList {
	protected SourceView parent_wrapper;
	protected MediaEditor media_editor;
	
	protected TreeViewSetup tvs;
	public int relative_id;
	protected bool is_current_list;
	
	uint scroll_back_id; // the pending return to the playing song after a scroll
	protected bool scrolled_recently;
	protected Gtk.GestureClick click_gesture; // the press on the rows: see MusicList.view_click
	protected Gtk.DragSource drag_source; // drags the selected rows to the sidebar
	protected bool dragging;
	
	protected GLib.Icon playing_icon;
	protected GLib.Icon completed_icon;
	protected GLib.Icon saved_locally_icon;
	protected GLib.Icon new_podcast_icon;
	
	// To select which columns are showing: a check item per column, "columns.show-<n>"
	GLib.Menu columnChooserMenu = new GLib.Menu();
	SimpleActionGroup columnActions = new SimpleActionGroup();
	
	public signal void import_requested(LinkedList<Media> to_import);
	
	protected GenericList(TreeViewSetup tvs) {
		base();
		
		this.tvs = tvs;
		
		set_rating_icons(BeatBox.App.icons.STARRED.render (IconSize.NORMAL, null));
		
		playing_icon = App.icons.MEDIA_PLAY_SYMBOLIC.get_gicon ();
		completed_icon = App.icons.PROCESS_COMPLETED.get_gicon ();
		saved_locally_icon = new GLib.ThemedIcon.with_default_fallbacks ("document-save");
		new_podcast_icon = App.icons.NEW_PODCAST.get_gicon ();
		
		// drag source: the selected rows, as "uri1\nuri2"
		drag_source = new Gtk.DragSource();
		drag_source.actions = Gdk.DragAction.COPY;
		drag_source.prepare.connect(on_drag_prepare);
		drag_source.drag_begin.connect(on_drag_begin);
		drag_source.drag_end.connect(on_drag_end);
		add_controller(drag_source);
		
		insert_action_group("columns", columnActions);
		
		// any press, before the list handles it
		click_gesture = new Gtk.GestureClick();
		click_gesture.button = 0;
		click_gesture.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		click_gesture.pressed.connect(() => { scrolled_recently = true; });
		add_controller(click_gesture);
		row_activated.connect(row_activated_signal);
		rows_reordered.connect(updateTreeViewSetup);
		column_resized.connect(updateTreeViewSetup);
		App.playback.current_cleared.connect(current_cleared);
		App.playback.media_played.connect(media_played);
		App.playback.playback_stopped.connect(playback_stopped);
		App.library.medias_updated.connect(medias_updated);
	}
	
	public void set_parent_wrapper(SourceView parent) {
		this.parent_wrapper = parent;
		scrolled.connect(view_scroll);
	}
	
	public abstract void update_sensitivities();
	
	/** Column header functions. Has to do with sorting and
	 * remembering column widths/sort column/sort direction between
	 * sessions.
	**/
	protected abstract void updateTreeViewSetup();
	
	// Column titles are translated at runtime (see add_columns); listed here for xgettext
	const string[] COLUMN_NAMES = { N_("Title"), N_("Length"), N_("Artist"), N_("Album"), N_("Genre"),
		N_("Year"), N_("Track"), N_("Bitrate"), N_("Rating"), N_("Plays"), N_("Skips"), N_("Date Added"),
		N_("Last Played"), N_("Episode"), N_("Name"), N_("Podcast"), N_("Date"), N_("Comment"),
		N_("Category"), N_("Station") };
	
	/** The kind of cell for a column of the setups, by its (English) title */
	static CellKind kind_of(string title) {
		switch(title) {
			case " ":
				return CellKind.ICON;
			case "Rating":
				return CellKind.RATING;
			case "Bitrate":
				return CellKind.BITRATE;
			case "Length":
				return CellKind.LENGTH;
			case "Date Added":
			case "Last Played":
			case "Date":
				return CellKind.DATE;
			case "#":
			case "Track":
			case "Year":
			case "Plays":
			case "Skips":
			case "BPM":
			case "Episode":
			case "Pulser":
			case "id":
				return CellKind.NUMBER;
			case TreeViewSetup.CHECKBOX_COLUMN_TITLE:
				return CellKind.TOGGLE;
			default: // Title, Artist, Album, Genre, Name, Comment, Category, Podcast, Station
				return CellKind.TEXT;
		}
	}
	
	protected void add_columns() {
		foreach(ListColumn tvc in tvs.get_columns()) {
			var kind = kind_of(tvc.title);
			bool special = (tvc.title == " " || tvc.title == "id" || tvc.title == TreeViewSetup.CHECKBOX_COLUMN_TITLE);
			// Show the name translated; the title stays the English key the code matches on
			// (never _(""): gettext answers the empty string with the catalog's header)
			string? shown = special ? null : _(tvc.title);
			int width = tvc.width;
			if(tvc.title == " ")
				width = show_checks ? 48 : 24;
			var column = add_column(tvc.title, shown, kind, width, tvc.title != "id" && tvc.visible,
			                        !special, !special && tvc.title != "Rating");
			
			if(tvc.title == "Title" && (get_hint() == TreeViewSetup.Hint.NOW_PLAYING || get_hint() == TreeViewSetup.Hint.ALBUM_LIST)) {
				// an album's songs: the title takes the room left, the length goes to the right edge
				column.expand = true;
				column.fixed_width = -1;
			}
		}
		set_header_menu(columnChooserMenu);
	}
	
	/** A check item in the header's right click menu that shows or hides the column titled title */
	protected void add_column_toggle(string title, string label) {
		var column = column_titled(title);
		if(column == null)
			return;
		var action = new SimpleAction.stateful("show-%d".printf(columnChooserMenu.get_n_items()), null, new Variant.boolean(column.visible));
		action.change_state.connect((visible) => {
			column.visible = visible.get_boolean();
			updateTreeViewSetup();
		});
		column.notify["visible"].connect(() => action.set_state(new Variant.boolean(column.visible)));
		columnActions.add_action(action);
		columnChooserMenu.append(label, "columns." + action.name);
	}
	
	/** A click on a column title: if the songs play shuffled, it unshuffles instead of sorting */
	protected override bool sort_requested(int column, SortType order) {
		// If the user tries to sort, then make sure that all other views
		// become sorted (unshuffled) if they are shuffled
		if(App.settings.main.shuffle_mode == (int)PlaybackInterface.ShuffleMode.ALL) {
			App.settings.main.shuffle_mode = 0;
			return false;
		}
		return true;
	}
	
	public void row_activated_signal(int position) {
		if(tvs.get_hint() == TreeViewSetup.Hint.DEVICE_AUDIO || tvs.get_hint() == TreeViewSetup.Hint.DEVICE_PODCAST) {
			App.window.doAlert(_("Playing not Supported"), _("Due to issues with playing songs on certain iOS devices, playing songs on devices is currently not supported."));
			return;
		}
		
		Media? m = (position >= 0 && position < get_visible_table().size()) ? get_media_from_index(position) : null;
		if(m == null)
			return;
		
		// We need to first set this as the current list
		if(m.location_unknown || (m.is_local && !File.new_for_uri(m.uri).query_exists())) {
			var list = new LinkedList<Media>();
			list.add(m);
			
			FileNotFoundDialog fnfd = new FileNotFoundDialog(list);
			fnfd.present();
		}
		else {
			// Now play the song
			// For songs with no attached uri, try opening its lastfm url
			if(m.uri == "") {
				try {
					new Thread<void*>.try (null, take_action);
				}
				catch (Error err) {
					warning ("Could not create thread to have fun: %s", err.message);
				}
			}
			else {
				App.playback.play_media(m, false);
				
				// Now update current_list and current_index in LM
				App.playback.clear_playback_list();
				set_as_current_list(m);
				
				if(!App.playback.playing) {
					App.playback.play();
				}
			}
		}
	}
	
	public void* take_action () {
		Media s = get_selected_medias().nth_data(0);
		if(s == null)
			return null;
		
		// open the song's last.fm page
		if(s != null && s.lastfm_url != null && s.lastfm_url != "") {
			try {
				GLib.AppInfo.launch_default_for_uri (s.lastfm_url, null);
			}
			catch(Error err) {
				stdout.printf("Couldn't open the similar media's last fm page: %s\n", err.message);
			}
		}
		
		return null;
	}
	
	void media_played(Media? m, Media? old) { // m: none from set_as_current_list with nothing playing
		// We could find the exact rows to redraw by looping through the entire
		// table which is O(n), or we could just redraw the screen for O(m) where
		// m is the # of visible rows.
		refresh_all();
		
		// TODO: Also check if old media is viewable to user. If it is,
		// they may have just adjusted the scroll only slightly and we
		// should scroll to the new media
		if(!scrolled_recently) {
			scroll_to_current_media(false);
		}
	}
	
	void playback_stopped(Media? was_playing) {
		refresh_all();
	}
	
	public void medias_updated(Collection<Media> updates) {
		// a hidden list reads the songs anew when it's drawn again
		if(!get_mapped())
			return;

		var changed = new HashSet<Media>();
		changed.add_all(updates);
		redraw_medias(changed);
	}
	
	void current_cleared() {
		is_current_list = false;
	}
	
	public void set_as_current_list(Media? m) {
		var my_medias = new LinkedList<Media>();
		
		var vis_table = get_visible_table();
		for(int i = 0; i < vis_table.size(); ++i) {
			my_medias.add(vis_table.get(i));
		}
		
		App.playback.set_playback_list(my_medias, m);
		is_current_list = true;
		
		media_played(App.playback.current_media, App.playback.current_media);
		
		scroll_to_current_media(true);
	}
	
	void view_scroll() {
		if(restoring_scroll) // our own scroll, not the user's
			return;
		
		scrolled_recently = true;
		
		// one timer, restarted by every scroll (not one per scroll event)
		if(scroll_back_id != 0)
			Source.remove(scroll_back_id);
		scroll_back_id = Timeout.add_seconds(20, () => {
			scroll_back_id = 0;
			// User has gone on to something else. Scroll to current
			// media, and if we can't find it, remove any filtering
			// and try again.
			scroll_to_current_media(true);
			return false;
		});
	}
	
	protected void mediaScrollToCurrentRequested() {
		scroll_to_current_media(true);
	}
	
	/** media menu popup clicks **/
	protected void mediaMenuEditClicked() {
		var to_edit = new LinkedList<Media>();
		
		MediaType type = MediaType.ITEM;
		foreach(Media m in get_selected_medias()) {
			to_edit.add(m);
			
			if(type == MediaType.ITEM) {
				type = m.media_type;
			}
			else if(type != m.media_type) {
				App.window.doAlert(_("Media Editor"), _("Editing of multiple media types is not allowed"));
				return;
			}
		}
		
		if(to_edit.size == 0)
			return;
		
		Media m = to_edit.get(0);
		string music_folder_uri = File.new_for_path(App.settings.main.music_folder).get_uri();
		
		// If there is only 1 media and it's location is invalid, prompt for user to find it
		if(to_edit.size == 1 && !GLib.File.new_for_uri(m.uri).query_exists() && !String.is_empty(m.uri) && m.uri.has_prefix(music_folder_uri)) {
			m.unique_status_image = App.icons.PROCESS_ERROR.render(IconSize.NORMAL, this);
			FileNotFoundDialog fnfd = new FileNotFoundDialog(to_edit);
			fnfd.present();
		}
		else {
			var list = new LinkedList<Media>();
			for(int i = 0; i < get_visible_table().size(); ++i) {
				list.add(get_media_from_index(i));
			}
			
			media_editor = new MediaEditor(list, to_edit);
			media_editor.show();
		}
	}
	
	// TODO: Convert FastList/Model and GenericList to Gee
	protected void mediaMenuQueueClicked() {
		var to_queue = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			to_queue.add(m);
		}
		
		App.playback.queue_medias(to_queue);
	}
	
	// TODO: Scroll so that the media is in the center of the viewport
	// rather than on the edge
	public void scroll_to_current_media(bool unfilter_if_not_found) {
		if(!visible || App.playback.current_media == null)
			return;
		
		// If user is editing a media, we don't want to scroll away from
		// that media. Instead, requeue a timeout by calling view_scroll
		// to try again in 20 seconds
		if(media_editor != null && media_editor.visible) {
			view_scroll();
			return;
		}
		
		for(int i = 0; i < get_visible_table().size(); ++i) {
			Media m = get_media_from_index(i);

			if(m.rowid == App.playback.current_media.rowid) {
				scroll_to_row(i, false);
				scrolled_recently = false;

				return;
			}
		}
		
		if(unfilter_if_not_found) {
			// At this point, it was not scrolled to. Let's see if it's in ALL the songs
			// and if so, undo the search and filters and scroll to it.
			var whole_table = get_table();
			for(int i = 0; i < whole_table.size(); ++i) {
				Media m = whole_table.get(i);

				if(m.rowid == App.playback.current_media.rowid) {
					// Undo search and filter
					parent_wrapper.clear_filters();
					App.window.set_search_string("");
					
					// And now scroll to it.
					scroll_to_row(i, false);
					scrolled_recently = false;

					return;
				}
			}
		}
		
		scrolled_recently = false;
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
	
	/** **************************************************
	 * Drag and drop support. GenericView is a source for uris and can
	 * be dragged to a playlist in the sidebar; the queue's list also takes
	 * drops to reorder (MusicList.enable_queue_reordering).
	***************************************************************/
	Gdk.ContentProvider? on_drag_prepare(double x, double y) {
		if(on_header(y))
			return null;
		// a drag from a row out of the selection takes that row
		int row = row_at(x, y);
		if(row >= 0 && !is_row_selected(row))
			select_only(row);
		string[] uris = {};

		foreach(Media m in get_selected_medias()) {
			uris += (m.uri);
		}

		if(uris.length == 0)
			return null;
		return new Gdk.ContentProvider.for_value(string.joinv("\n", uris));
	}

	void on_drag_begin(Gdk.Drag drag) {
		dragging = true;
		App.window.dragging_from_music = true;
		debug("drag begin\n");

		string? icon_name = null;
		if(count_selected() == 1)
			icon_name = "audio-x-generic";
		else if(count_selected() > 1)
			icon_name = "folder-music";

		if(icon_name != null) {
			var icon = Gtk.IconTheme.get_for_display(get_display()).lookup_icon(icon_name, null, 32, 1, Gtk.TextDirection.NONE, 0);
			drag_source.set_icon(icon, 0, 0);
		}
	}

	void on_drag_end(Gdk.Drag drag, bool delete_data) {
		dragging = false;
		App.window.dragging_from_music = false;

		debug("drag end\n");
	}

	/** **************************************************
	 * View search. All lists use same search algorithm 
	 * *************************************************/
	protected void view_search_func (string search, HashTable<int, Media> table, ref HashTable<int, Media> show) {
		int show_index = 0;
		
		for(int i = 0; i < table.size(); ++i) {
			Media m = table.get(i);
			
			if(search in m.artist.down() || search in m.album_artist.down() ||
			search in m.album.down() || search in m.title.down() ||
			search in m.genre.down()) {
				if(parent_wrapper != null) {
					if(parent_wrapper.passes_filters(m)) {
						show.set(show_index++, table.get(i));
					}
				}
				else {
					show.set(show_index++, table.get(i));
				}
			}
		}
	}
	
	/************************************************
	 * Used by all views to sort list
	 * ******************************************/
	protected int advanced_string_compare(string a, string b) {
		if(a == "" && b != "")
			return 1;
		else if(a != "" && b == "")
			return -1;
		else if(a == b)
			return 0;
		
		return (a > b) ? 1 : -1;
	}
}

// GTK4: multi-row drag is unverified without a display; see docs/gtk4/ESTADO.md
