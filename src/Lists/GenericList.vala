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
	bool _is_mixed; // if true, temporary songs will be italicized in CellDataHelper
	public bool is_mixed {
		get { return cellHelper.is_mixed; }
		set { cellHelper.is_mixed = value; }
	}
	public int relative_id;
	protected bool is_current_list;
	
	uint scroll_back_id; // the pending return to the playing song after a scroll
	protected bool scrolled_recently;
	Gtk.GestureMultiPress click_gesture; // GTK3 controllers need a reference
	protected bool dragging;
	
	protected CellDataFunctionHelper cellHelper;
	
	protected GLib.Icon playing_icon;
	protected GLib.Icon completed_icon;
	protected GLib.Icon saved_locally_icon;
	protected GLib.Icon new_podcast_icon;
	
	// To select which columns are showing: a check item per column, "columns.show-<n>"
	GLib.Menu columnChooserMenu = new GLib.Menu();
	SimpleActionGroup columnActions = new SimpleActionGroup();
	
	public signal void import_requested(LinkedList<Media> to_import);
	
	protected GenericList(GLib.List<Type> types, TreeViewSetup tvs, Media default_value) {
		base(types, default_value);
		
		this.tvs = tvs;
		
		set_headers_clickable(true);
		set_headers_visible(true);
		set_fixed_height_mode(true);
		set_reorderable(false);
		
		// Make the 
		int icon_column = MusicColumn.ICON;
		if(tvs.get_hint() == TreeViewSetup.Hint.DUPLICATES)
			icon_column = DuplicateColumn.ICON;
		
		var starred = BeatBox.App.icons.STARRED.render (IconSize.MENU, null);
		var not_starred = BeatBox.App.icons.NOT_STARRED.render (IconSize.MENU, null);
		
		cellHelper = new CellDataFunctionHelper(this, _is_mixed, icon_column, starred, not_starred);
		
		playing_icon = App.icons.MEDIA_PLAY_SYMBOLIC.get_gicon ();
		completed_icon = App.icons.PROCESS_COMPLETED.get_gicon ();
		saved_locally_icon = new GLib.ThemedIcon.with_default_fallbacks ("document-save");
		new_podcast_icon = App.icons.NEW_PODCAST.get_gicon ();
		
		// drag source
		TargetEntry te = { "text/uri-list", TargetFlags.SAME_APP, 0};
		drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, { te }, Gdk.DragAction.COPY);
		
		// allow selecting multiple rows
		get_selection().set_mode(SelectionMode.MULTIPLE);
		
		insert_action_group("columns", columnActions);
		
		drag_begin.connect(on_drag_begin);
		drag_data_get.connect(on_drag_data_get);
		drag_end.connect(on_drag_end);
		// any press, before the list handles it
		click_gesture = new Gtk.GestureMultiPress(this);
		click_gesture.button = 0;
		click_gesture.propagation_phase = Gtk.PropagationPhase.CAPTURE;
		click_gesture.pressed.connect(() => { scrolled_recently = true; });
		row_activated.connect(row_activated_signal);
		rows_reordered.connect(updateTreeViewSetup);
		App.playback.current_cleared.connect(current_cleared);
		App.playback.media_played.connect(media_played);
		App.playback.playback_stopped.connect(playback_stopped);
		App.library.medias_updated.connect(medias_updated);
	}
	
	public void set_parent_wrapper(SourceView parent) {
		this.parent_wrapper = parent;
		vadjustment.value_changed.connect(view_scroll);
	}
	
	public abstract void update_sensitivities();
	
	/** TreeViewColumn header functions. Has to do with sorting and
	 * remembering column widths/sort column/sort direction between
	 * sessions.
	**/
	protected abstract void updateTreeViewSetup();
	
	// Column titles are translated at runtime (see add_columns); listed here for xgettext
	const string[] COLUMN_NAMES = { N_("Title"), N_("Length"), N_("Artist"), N_("Album"), N_("Genre"),
		N_("Year"), N_("Track"), N_("Bitrate"), N_("Rating"), N_("Plays"), N_("Skips"), N_("Date Added"),
		N_("Last Played"), N_("Episode"), N_("Name"), N_("Podcast"), N_("Date"), N_("Comment"),
		N_("Category"), N_("Station") };
	
	protected void add_columns() {
		int index = 0;
		
		foreach(TreeViewColumn tvc in tvs.get_columns()) {
			tvc.sizing = Gtk.TreeViewColumnSizing.FIXED;
			
			if(!(tvc.title == " " || tvc.title == "id")) {
				// Music, General
				if(tvc.title == "Bitrate")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.bitrateTreeViewFiller);
				else if(tvc.title == "Length")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.lengthTreeViewFiller);
				else if(tvc.title == "Date Added")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.dateTreeViewFiller);
				else if(tvc.title == "Last Played")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.dateTreeViewFiller);
				else if(tvc.title == "Rating") {
					insert_column_with_data_func(-1, tvc.title, new CellRendererPixbuf() , cellHelper.ratingTreeViewFiller);
				}
				else if(tvc.title == "Year")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "#")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Track")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Plays")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Skips")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Title")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Artist")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Album")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Genre")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "BPM")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				
				// Podcast
				else if(tvc.title == "Date")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.dateTreeViewFiller);
				else if(tvc.title == "Episode")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.intelligentTreeViewFiller);
				else if(tvc.title == "Name")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Comment")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Category")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Podcast")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				else if(tvc.title == "Pulser")
					insert_column(tvc, index); // cells for pulser is made ready to go in TVS
				
				// Radio
				else if(tvc.title == "Station")
					insert_column_with_data_func(-1, tvc.title, new CellRendererText(), cellHelper.stringTreeViewFiller);
				
				// Duplicates
				else if(tvc.title == DuplicateList.CHECKBOX_COLUMN_TITLE)
					insert_column_with_data_func(-1, tvc.title, new CellRendererToggle(), cellHelper.toggleColumnFiller);
				
				else {
					warning("Unknown column found. Adding anyways (%s)\n", tvc.title);
					insert_column(tvc, index);
				}


				get_column(index).resizable = (tvc.title != "Rating");
				get_column(index).reorderable = false;
				get_column(index).clickable = true;
				get_column(index).sort_column_id = index;
				get_column(index).set_sort_indicator(false);
				get_column(index).visible = tvc.visible;
				
				if(tvc.title == "Title" && get_hint() == TreeViewSetup.Hint.NOW_PLAYING) {
					get_column(index).sizing = Gtk.TreeViewColumnSizing.AUTOSIZE;
					get_column(index).expand = true;
				}
				else {
					get_column(index).sizing = Gtk.TreeViewColumnSizing.FIXED;
					get_column(index).fixed_width = tvc.fixed_width;
				}
			}
			else if(tvc.title == " ") {
				insert_column(tvc, index);

				get_column(index).fixed_width = 24;
				get_column(index).clickable = false;
				get_column(index).sort_column_id = -1;
				get_column(index).resizable = false;
				get_column(index).reorderable = false;

				get_column(index).set_cell_data_func(tvc.get_cells().nth_data(0), cellHelper.iconDataFunc);
				get_column(index).set_cell_data_func(tvc.get_cells().nth_data(1), cellHelper.iconDataFunc);
			}
			else if(tvc.title == "id") {
				insert_column(tvc, index);
			}
			else {
				warning("Inserting unknown column %s at index %d\n", tvc.title, index);
				insert_column(tvc, index);
			}

			// Show the name translated; the title stays the English key the code matches on
			// (never _(""): gettext answers the empty string with the catalog's header)
			if(tvc.title != " " && tvc.title != "id" && tvc.title != "") {
				var header = new Label(_(tvc.title));
				header.show();
				get_column(index).widget = header;
			}
			
			// CAPTURE: before the header button turns the press into a click (sorting)
			var header_click = new Gtk.GestureMultiPress(get_column(index).get_button());
			header_click.button = 0;
			header_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
			header_click.pressed.connect(view_header_click);
			get_column(index).get_button().set_data("click-gesture", header_click); // GTK3 controllers need a reference
			get_column(index).notify["width"].connect(updateTreeViewSetup);

			++index;
		}
	}
	
	protected TreeViewColumn? column_titled(string title) {
		foreach(var column in get_columns())
			if(column.title == title)
				return column;
		return null;
	}
	
	/** A check item in the header's right click menu that shows or hides the column titled title */
	protected void add_column_toggle(string title, string label) {
		var column = column_titled(title);
		if(column == null)
			return;
		var action = new SimpleAction.stateful("show-%d".printf(columnChooserMenu.get_n_items()), null, new Variant.boolean(column.visible));
		action.change_state.connect((visible) => {
			column.visible = visible.get_boolean();
			tvs.set_columns(get_columns());
		});
		column.notify["visible"].connect(() => action.set_state(new Variant.boolean(column.visible)));
		columnActions.add_action(action);
		columnChooserMenu.append(label, "columns." + action.name);
	}
	
	protected void view_header_click(Gtk.GestureMultiPress gesture, int n_press, double x, double y) {
		uint button = gesture.get_current_button();
		if(button == 3) {
			UI.popup_menu_model(gesture.get_widget(), columnChooserMenu, x, y);
			gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
		else if(button == 1) {
			// If the user tries to sort, then make sure that all other views
			// become sorted (unshuffled) if they are shuffled
			if(App.settings.main.shuffle_mode == (int)PlaybackInterface.ShuffleMode.ALL) {
				App.settings.main.shuffle_mode = 0;
				gesture.set_state(Gtk.EventSequenceState.CLAIMED);
				return;
			}
			
			updateTreeViewSetup();
		}
	}
	
	public void row_activated_signal(TreePath path, TreeViewColumn column) {
		if(tvs.get_hint() == TreeViewSetup.Hint.DEVICE_AUDIO || tvs.get_hint() == TreeViewSetup.Hint.DEVICE_PODCAST) {
			App.window.doAlert(_("Playing not Supported"), _("Due to issues with playing songs on certain iOS devices, playing songs on devices is currently not supported."));
			return;
		}
		
		Media m = get_selected_medias().nth_data(0);
		
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
	
	void media_played(Media m, Media? old) {
		// We could find the exact rows to redraw by looping through the entire
		// table which is O(n), or we could just redraw the screen for O(m) where
		// m is the # of visible rows.
		queue_draw();
		
		// TODO: Also check if old media is viewable to user. If it is,
		// they may have just adjusted the scroll only slightly and we
		// should scroll to the new media
		if(!scrolled_recently) {
			scroll_to_current_media(false);
		}
	}
	
	void playback_stopped(Media? was_playing) {
		queue_draw();
	}
	
	public void medias_updated(Collection<Media> updates) {
		// a hidden list reads the songs anew when it's drawn again
		if(!get_mapped())
			return;

		var map = new HashMap<int, int>();
		foreach(Media m in updates)
			map.set(m.rowid, 1);
		
		for(int i = 0; i < get_visible_table().size(); ++i) {
			if(map.get(get_visible_table().get(i).rowid) == 1) {
				redraw_row (i);
			}
		}
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
			m.unique_status_image = App.icons.PROCESS_ERROR.render(IconSize.MENU, get_style_context());
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
				scroll_to_cell(new TreePath.from_string(i.to_string()), null, false, 0.0f, 0.0f);
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
					scroll_to_cell(new TreePath.from_string(i.to_string()), null, false, 0.0f, 0.0f);
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
	
	/** **********************************************************
	 * Drag and drop support. GenericView is a source for uris and can
	 * be dragged to a playlist in the sidebar; the queue's list also takes
	 * drops to reorder (MusicList.enable_queue_reordering).
	***************************************************************/
	void on_drag_begin(Gtk.Widget sender, Gdk.DragContext context) {
		dragging = true;
		App.window.dragging_from_music = true;
		debug("drag begin\n");

		Gdk.drag_abort(context, Gtk.get_current_event_time());

		if(get_selection().count_selected_rows() == 1) {
			drag_source_set_icon_name(this, "audio-x-generic");
		}
		else if(get_selection().count_selected_rows() > 1) {
			drag_source_set_icon_name(this, "folder-music");
		}
		else {
			return;
		}
	}
	
	void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data, uint info, uint time_) {
		string[] uris = null;

		foreach(Media m in get_selected_medias()) {
			uris += (m.uri);
		}

		if (uris != null)
			selection_data.set_uris(uris);
	}
	
	void on_drag_end(Gtk.Widget sender, Gdk.DragContext context) {
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
					if((m.album_artist.down() == parent_wrapper.artist_filter.down() || parent_wrapper.artist_filter == "") &&
					(m.album.down() == parent_wrapper.album_filter.down() || parent_wrapper.album_filter == "") &&
					(m.genre.down() == parent_wrapper.genre_filter.down() || parent_wrapper.genre_filter == "")) {
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
