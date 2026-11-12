/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
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

public class BeatBox.MusicList : GenericList {

	//for media list right click
	PopMenu mediaMenuActionMenu;
	PopMenuItem mediaEditMedia;
	PopMenuItem mediaFileBrowse;
	PopMenuItem mediaMenuQueue;
	PopMenuItem mediaMenuPlayNext;
	PopMenuItem queueMoveUp;
	PopMenuItem queueMoveDown;
	PopMenuItem queueClear;
	PopMenuItem saveArtInFiles;
	PopMenuItem fillTags;
	PopMenuItem findReplace;
	PopMenuItem mediaMenuNewPlaylist;
	PopMenuItem mediaMenuAddToPlaylist; // opens the playlists menu, made on each right click
	PopMenu addToPlaylistMenu;
	RatingMenuItem mediaRateMedia;
	PopMenuItem mediaRemove;
	PopMenuItem importToLibrary;
	PopMenuItem mediaScrollToCurrent;

	/**
	 * for sort_id use 0+ for normal, -1 for auto, -2 for none
	 */
	public MusicList(TreeViewSetup tvs) {
		var types = new GLib.List<Type>();
		types.append(typeof(int)); // id
		types.append(typeof(GLib.Icon)); // icon
		types.append(typeof(int)); // #
		types.append(typeof(int)); // track
		types.append(typeof(string)); // title
		types.append(typeof(int)); // length
		types.append(typeof(string)); // artist
		types.append(typeof(string)); // album
		types.append(typeof(string)); // genre
		types.append(typeof(int)); // year
		types.append(typeof(int)); // bitrate
		types.append(typeof(int)); // rating
		types.append(typeof(int)); // plays
		types.append(typeof(int)); // skips
		types.append(typeof(int)); // date added
		types.append(typeof(int)); // last played
		types.append(typeof(int)); // bpm
		types.append(typeof(int)); // pulser};
		base(types, tvs, new Song(""));
		
		//last_search = "";
		//timeout_search = new LinkedList<string>();
		//showing_all = true;
		//removing_medias = false;


		buildUI();
	}

	public override void update_sensitivities() {
		bool in_queue = get_hint() == TreeViewSetup.Hint.QUEUE;
		// files on a device or a CD aren't BeatBox's to change
		saveArtInFiles.visible = CoverEmbedder.available() && get_hint() != TreeViewSetup.Hint.DEVICE_AUDIO && get_hint() != TreeViewSetup.Hint.CDROM;
		fillTags.visible = get_hint() != TreeViewSetup.Hint.DEVICE_AUDIO && get_hint() != TreeViewSetup.Hint.CDROM;
		findReplace.visible = fillTags.visible;
		queueMoveUp.visible = queueMoveDown.visible = queueClear.visible = in_queue;

		if(get_hint() == TreeViewSetup.Hint.MUSIC) {
			mediaRemove.set_visible(true);
			mediaRemove.set_label(_("Remove from Library"));
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.SIMILAR) {
			mediaRemove.set_visible(false);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.QUEUE) {
			mediaRemove.set_visible(true);
			mediaRemove.set_label(_("Remove from Queue"));
			mediaMenuQueue.set_visible(false);
			mediaMenuPlayNext.set_visible(false);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.HISTORY) {
			mediaRemove.set_visible(false);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.PLAYLIST) {
			mediaRemove.set_visible(true);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.SMART_PLAYLIST) {
			mediaRemove.set_visible(false);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.DEVICE_AUDIO) {
			mediaEditMedia.set_visible(false);
			mediaRemove.set_visible(true);
			mediaRemove.set_label(_("Remove from Device"));
			mediaMenuQueue.set_visible(false);
			mediaMenuPlayNext.set_visible(false);
			importToLibrary.set_visible(true);
			mediaMenuAddToPlaylist.set_visible(false);
			mediaMenuNewPlaylist.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.CDROM) {
			mediaEditMedia.set_visible(true);
			mediaRemove.set_visible(false);
			importToLibrary.set_visible(true);
			mediaMenuAddToPlaylist.set_visible(false);
			mediaMenuNewPlaylist.set_visible(false);
		}
		else {
			mediaRemove.set_visible(false);
		}
	}

	public void buildUI() {
		add_columns ();
		
		set_compare_func(view_compare_func);
        set_search_func(view_search_func);
        set_value_func(view_value_func);
        
		click_gesture.pressed.connect(view_click);
		click_gesture.released.connect(view_click_release);

		// column chooser menu (header right click)
		if(get_hint() == TreeViewSetup.Hint.MUSIC && column_titled("#") != null)
			column_titled("#").visible = false; // the library has no order of its own: no "#"
		else
			add_column_toggle("#", _("#"));
		add_column_toggle("Track", _("Track"));
		add_column_toggle("Title", _("Title"));
		add_column_toggle("Length", _("Length"));
		add_column_toggle("Artist", _("Artist"));
		add_column_toggle("Album", _("Album"));
		add_column_toggle("Genre", _("Genre"));
		add_column_toggle("Year", _("Year"));
		add_column_toggle("Bitrate", _("Bitrate"));
		add_column_toggle("Rating", _("Rating"));
		add_column_toggle("Plays", _("Plays"));
		add_column_toggle("Skips", _("Skips"));
		add_column_toggle("Date Added", _("Date Added"));
		add_column_toggle("Last Played", _("Last Played"));
		add_column_toggle("BPM", _("BPM"));

		//media list right click menu
		mediaMenuActionMenu = new PopMenu();
		mediaEditMedia = new PopMenuItem.with_label(_("Edit Song Info"));
		mediaFileBrowse = new PopMenuItem.with_label(_("Show in File Browser"));
		mediaMenuQueue = new PopMenuItem.with_label(_("Add to Queue"));
		mediaMenuPlayNext = new PopMenuItem.with_label(_("Play Next"));
		queueMoveUp = new PopMenuItem.with_label(_("Move Up"));
		queueMoveDown = new PopMenuItem.with_label(_("Move Down"));
		queueClear = new PopMenuItem.with_label(_("Clear Queue"));
		saveArtInFiles = new PopMenuItem.with_label(_("Save Album Art into the Files"));
		fillTags = new PopMenuItem.with_label(_("Fill In Tags from File Names…"));
		findReplace = new PopMenuItem.with_label(_("Find and Replace in Tags…"));
		mediaMenuNewPlaylist = new PopMenuItem.with_label(_("New Playlist"));
		mediaMenuAddToPlaylist = new PopMenuItem.with_label(_("Add to Playlist"));
		mediaRemove = new PopMenuItem.with_label(_("Remove Song"));
		importToLibrary = new PopMenuItem.with_label(_("Import to Library"));
		mediaScrollToCurrent = new PopMenuItem.with_label(_("Scroll to Current Song"));
		mediaRateMedia = new RatingMenuItem();
		mediaMenuActionMenu.append(mediaEditMedia);
		mediaMenuActionMenu.append(mediaFileBrowse);
		mediaMenuActionMenu.append(saveArtInFiles);
		mediaMenuActionMenu.append(fillTags);
		mediaMenuActionMenu.append(findReplace);
		mediaMenuActionMenu.append(mediaRateMedia);
		mediaMenuActionMenu.append(new PopMenuSeparator());
		mediaMenuActionMenu.append(mediaMenuQueue);
		mediaMenuActionMenu.append(mediaMenuPlayNext);
		mediaMenuActionMenu.append(queueMoveUp);
		mediaMenuActionMenu.append(queueMoveDown);
		mediaMenuActionMenu.append(mediaMenuNewPlaylist);
		mediaMenuActionMenu.append(mediaMenuAddToPlaylist);
		if(tvs.get_hint() != TreeViewSetup.Hint.DEVICE_AUDIO && tvs.get_hint() != TreeViewSetup.Hint.SMART_PLAYLIST) {
			mediaMenuActionMenu.append(new PopMenuSeparator());
		}
		mediaMenuActionMenu.append(mediaRemove);
		mediaMenuActionMenu.append(queueClear);
		mediaMenuActionMenu.append(importToLibrary);
		if(tvs.get_hint() != TreeViewSetup.Hint.CDROM) {
			mediaMenuActionMenu.append(new PopMenuSeparator());
			mediaMenuActionMenu.append(mediaScrollToCurrent);
		}
		mediaEditMedia.clicked.connect(mediaMenuEditClicked);
		mediaFileBrowse.clicked.connect(mediaFileBrowseClicked);
		mediaMenuQueue.clicked.connect(mediaMenuQueueClicked);
		if(tvs.get_hint() == TreeViewSetup.Hint.QUEUE)
			enable_queue_reordering();
		mediaMenuPlayNext.clicked.connect(() => { App.playback.insert_in_queue(selected_list(), 0); });
		queueMoveUp.clicked.connect(() => move_selected_in_queue(-1));
		queueMoveDown.clicked.connect(() => move_selected_in_queue(1));
		queueClear.clicked.connect(() => App.playback.clear_queue());
		saveArtInFiles.clicked.connect(save_art_in_files);
		fillTags.clicked.connect(() => FillTagsDialog.run_for(selected_list()));
		findReplace.clicked.connect(() => FindReplaceDialog.run_for(selected_list()));
		mediaMenuNewPlaylist.clicked.connect(mediaMenuNewPlaylistClicked);
		mediaMenuAddToPlaylist.keep_open = true; // the playlists open beside the menu
		mediaMenuAddToPlaylist.clicked.connect(() => addToPlaylistMenu.popup_under(mediaMenuAddToPlaylist));
		mediaRemove.clicked.connect(mediaRemoveClicked);
		importToLibrary.clicked.connect(importToLibraryClicked);
		mediaRateMedia.clicked.connect(mediaRateMediaClicked);
		mediaScrollToCurrent.clicked.connect(mediaScrollToCurrentRequested);
		row_activated.connect((path, column) => row_activated_signal_event(path, column));
		
		set_headers_visible(tvs.get_hint() != TreeViewSetup.Hint.ALBUM_LIST &&
							tvs.get_hint() != TreeViewSetup.Hint.NOW_PLAYING);
		
		update_sensitivities();
	}

	public void rearrangeColumns(LinkedList<string> correctOrder) {
		move_column_after(get_column(6), get_column(7));
		//debug("correctOrder.length = %d, get_columns.length() = %d\n", correctOrder.size, (int)get_columns().length());
		/* iterate through get_columns and if a column is not in the
		 * same location as correctOrder, move it there.
		*/
		for(int index = 0; index < get_columns().length(); ++index) {
			//debug("on index %d column %s originally moving to %d\n", index, get_column(index).title, correctOrder.index_of(get_column(index).title));
			if(get_column(index).title != correctOrder.get(index)) {
				move_column_after(get_column(index), get_column(correctOrder.index_of(get_column(index).title)));
			}
		}
	}

	//void cellTitleEdited(string path, string new_text) {
		/*int rowid;
		debug("done!\n");
		if((rowid = list_model.getRowidFromPath(path)) != 0) {
			App.library.media_from_id(rowid).title = new_text;

			App.library.update_media(App.library.media_from_id(rowid), true);
		}
		cellTitle.editable = false; */
	//}

	/*void sortColumnChanged() {
		updateTreeViewSetup();
	}*/

	/*void modelRowsReordered(TreePath path, TreeIter? iter, void* new_order) {
		/*if(TreeViewSetup.Hint == "queue") {
			App.library.clear_queue();

			TreeIter item;
			for(int i = 0; list_model.get_iter_from_string(out item, i.to_string()); ++i) {
				int id;
				list_model.get(item, 0, out id);

				App.library.queue_media_by_id(id);
			}
		}*
		
		// TODO: FIXME
		//if(is_current_view) {
		//	set_as_current_list(0, false);
		//}

		if(!scrolled_recently) {
			scroll_to_current_media(false);
		}
	}*/

	/* a press on a row: the menus, and keeping the selection while several rows are dragged */
	void view_click(int n_press, double x, double y) {
		// a double click is no click for the menus or the selection
		if(n_press != 1)
			return;
		uint button = click_gesture.get_current_button();
		bool modified = (click_gesture.get_current_event_state() & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;

		if(button == Gdk.BUTTON_SECONDARY) { //right click
			// the menu acts on the clicked row: select it first, unless it is part of the selection
			TreePath? clicked;
			if(row_at(x, y, out clicked) && !get_selection().path_is_selected(clicked)) {
				get_selection().unselect_all();
				get_selection().select_path(clicked);
			}
			
			/* create add to playlist menu */
			addToPlaylistMenu = new PopMenu();
			foreach(BasePlaylist p in App.playlists.playlists()) {
				if(p is StaticPlaylist) {
					StaticPlaylist static_p = (StaticPlaylist)p;
					
					PopMenuItem playlist = new PopMenuItem.with_label(p.name);
					addToPlaylistMenu.append(playlist);

					playlist.clicked.connect( () => {
						var to_add = new LinkedList<Media>();
						
						foreach(Media m in get_selected_medias()) {
							to_add.add(m);
						}
						static_p.add_medias(to_add);
						App.playlists.update_playlist(p);
						mediaMenuActionMenu.popdown();
					});
				}
			}

			if(App.playlists.playlists().size == 0)
				mediaMenuAddToPlaylist.set_sensitive(false);
			else
				mediaMenuAddToPlaylist.set_sensitive(true);

			// if all medias are downloaded already, desensitize.
			// if half and half, change text to 'Download %external of %total'
			int temporary_count = 0;
			int total_count = 0;
			foreach(Media m in get_selected_medias()) {
				if(m.isTemporary)
					++temporary_count;

				++total_count;
			}

			if(temporary_count == 0)
				importToLibrary.set_sensitive(false);
			else {
				importToLibrary.set_sensitive(true);
				if(temporary_count != total_count)
					importToLibrary.label = "Import " + temporary_count.to_string() + " of " + total_count.to_string() + " selected " + parent_wrapper.media_representation;
				else
					importToLibrary.label = "Import" + ((temporary_count > 1) ? (" " + temporary_count.to_string() + " " + parent_wrapper.media_representation + "s") : "");
			}
			
			int set_rating = -1;
			foreach(Media m in get_selected_medias()) {
				if(set_rating == -1)
					set_rating = (int)m.rating;
				else if(set_rating != m.rating) {
					set_rating = 0;
					break;
				}
			}
			mediaRateMedia.rating_value = set_rating;
			
			MediaType type = MediaType.ITEM;
			foreach(Media m in get_selected_medias()) {
				if(type == MediaType.ITEM) {
					type = m.media_type;
				}
				else if(type != m.media_type) {
					type = MediaType.ITEM;
					break;
				}
			}
			mediaEditMedia.label = _("Edit %s").printf(type.to_string(total_count));

			mediaMenuActionMenu.popup_at(this, x, y);

			TreeSelection selected = get_selection();
			selected.set_mode(SelectionMode.MULTIPLE);
			if(selected.count_selected_rows() > 1)
				click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
		else if(button == 1) {
			/* don't unselect everything if multiple selected until button release
			 * for drag and drop reasons */
			if(get_selection().count_selected_rows() > 1) {
				TreePath? path;
				row_at(x, y, out path);
				bool on_selection = path != null && get_selection().path_is_selected(path);
				if(on_selection && modified)
					get_selection().unselect_path(path);
				// a press on the selection, or a plain press away from it, is kept from the TreeView
				if(on_selection || !modified)
					click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
			}
		}
	}

	/* a release on a row: ends a drag, or selects only the row when nothing was dragged */
	void view_click_release(int n_press, double x, double y) {
		uint button = click_gesture.get_current_button();
		bool modified = (click_gesture.get_current_event_state() & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;

		/* if we were dragging, then set dragging to false */
		if(dragging && button == 1) {
			dragging = false;
			click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
		else if(modified) {
			click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
		else {
			TreePath? path;
			if(!row_at(x, y, out path))
				return;
			get_selection().unselect_all();
			get_selection().select_path(path);
		}
	}
	
	void row_activated_signal_event(TreePath path, TreeViewColumn column) {
		if(tvs.get_hint() == TreeViewSetup.Hint.QUEUE) {
			Media m = get_selected_medias().nth_data(0);
			App.playback.unqueue_media(m);
		}
	}

	protected override void updateTreeViewSetup() {
		if(tvs == null || get_hint() == TreeViewSetup.Hint.ALBUM_LIST || get_columns().length() != TreeViewSetup.MUSIC_COLUMN_COUNT)
			return;

		int sort_id = MusicColumn.ARTIST;
		SortType sort_dir = Gtk.SortType.ASCENDING;
		get_sort_column_id(out sort_id, out sort_dir);

		if(sort_id < 0)
			sort_id = MusicColumn.ARTIST;
		
		tvs.set_columns(get_columns());
		tvs.sort_column_id = sort_id;
		tvs.sort_direction = sort_dir;
	}

	void mediaFileBrowseClicked() {
		foreach(Media m in get_selected_medias()) {
			try {
				AppInfo.launch_default_for_uri(File.new_for_uri(m.uri).get_parent().get_uri(), null);
			}
			catch(GLib.Error err) {
				warning("Could not browse media %s: %s", m.uri, err.message);
			}

			return;
		}
	}

	void mediaMenuNewPlaylistClicked() {
		StaticPlaylist p = new StaticPlaylist();
		
		var to_add = new LinkedList<Media>();
		foreach(Media m in get_selected_medias()) {
			to_add.add(m);
		}
		p.add_medias(to_add);

		PlaylistNameWindow pnw = new PlaylistNameWindow(p);
		pnw.playlist_saved.connect( (newP) => {
			App.playlists.add_playlist(p);
		});
	}
	
	void mediaRateMediaClicked() {
		var los = new LinkedList<Media>();
		int new_rating = mediaRateMedia.rating_value;
		
		foreach(Media m in get_selected_medias()) {
			m.rating = new_rating;
			los.add(m);
		}
		
		App.library.update_medias(los, false, true, true);
	}

	Gee.ArrayList<Media> selected_list() {
		var selected = new Gee.ArrayList<Media>();
		foreach(Media m in get_selected_medias())
			selected.add(m);
		return selected;
	}
	
	void save_art_in_files() {
		CoverEmbedder.embed(selected_list(), (written, failed) => {
			if(failed > 0)
				App.window.doAlert(_("Album art not saved"), ngettext("%d file could not be changed (it may be read-only, or of a kind that has no room for pictures).",
				                                                       "%d files could not be changed (they may be read-only, or of a kind that has no room for pictures).", failed).printf(failed));
			else if(written > 0)
				App.window.show_notification(_("Album art saved"), ngettext("Written into %d file", "Written into %d files", written).printf(written), null);
		});
	}
	
	void move_selected_in_queue(int delta) {
		var selected = selected_list();
		// moving down: the last one first, so they don't jump over each other
		if(delta > 0)
			for(int i = selected.size - 1; i >= 0; i--)
				App.playback.move_in_queue(selected[i], delta);
		else
			foreach(var m in selected)
				App.playback.move_in_queue(m, delta);
		select_medias(selected);
	}
	
	/** Selects the rows of these medias (after the queue was reordered) */
	void select_medias(Gee.Collection<Media> medias) {
		var selection = get_selection();
		selection.unselect_all();
		var visible = get_visible_table();
		for(int i = 0; i < visible.size(); i++)
			if(medias.contains(visible.get(i)))
				selection.select_path(new TreePath.from_indices(i));
	}
	
	/* In the queue, rows dragged within the list (or from another list) are
	 * dropped at the pointer's position. */
	void enable_queue_reordering() {
		var dest = new Gtk.DropTarget(GLib.Type.INVALID, Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
		dest.set_gtypes({ typeof(string), typeof(Gdk.FileList) });
		dest.motion.connect(queue_drag_motion);
		dest.leave.connect(() => { set_drag_dest_row(null, TreeViewDropPosition.BEFORE); });
		dest.drop.connect(queue_drag_received);
		add_controller(dest);
	}
	
	int queue_drop_index(int x, int y, out TreePath? path, out TreeViewDropPosition pos) {
		pos = TreeViewDropPosition.BEFORE;
		if(!get_dest_row_at_pos(x, y, out path, out pos))
			return (int)get_visible_table().size(); // below the last row
		bool after = pos == TreeViewDropPosition.AFTER || pos == TreeViewDropPosition.INTO_OR_AFTER;
		pos = after ? TreeViewDropPosition.AFTER : TreeViewDropPosition.BEFORE;
		return path.get_indices()[0] + (after ? 1 : 0);
	}
	
	Gdk.DragAction queue_drag_motion(double x, double y) {
		TreePath? path;
		TreeViewDropPosition pos;
		queue_drop_index((int)x, (int)y, out path, out pos);
		set_drag_dest_row(path, pos);
		return Gdk.DragAction.COPY;
	}
	
	bool queue_drag_received(GLib.Value value, double x, double y) {
		TreePath? path;
		TreeViewDropPosition pos;
		int index = queue_drop_index((int)x, (int)y, out path, out pos);
		set_drag_dest_row(null, TreeViewDropPosition.BEFORE);
		string[] uris = {};
		if(value.holds(typeof(Gdk.FileList))) {
			foreach(unowned File f in ((Gdk.FileList)value.get_boxed()).get_files())
				uris += f.get_uri();
		}
		else
			uris = value.get_string().split("\n");
		var medias = new Gee.ArrayList<Media>();
		foreach(string uri in uris) {
			var m = App.library.media_from_file(uri);
			if(m != null)
				medias.add(m);
		}
		if(medias.size > 0) {
			App.playback.insert_in_queue(medias, index);
			select_medias(medias);
		}
		return true;
	}
	
	void mediaRemoveClicked() {
		LinkedList<Media> toRemove = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			toRemove.add(m);
		}

		if(get_hint() == TreeViewSetup.Hint.MUSIC) {
			var dialog = new RemoveFilesDialog (toRemove, get_hint());
			dialog.remove_media.connect ( (delete_files) => {
				App.library.remove_medias (toRemove, delete_files);
			});
		}
		else if(get_hint() == TreeViewSetup.Hint.QUEUE) {
			foreach(Media m in toRemove) {
				App.playback.unqueue_media(m);
			}
		}
		else if(get_hint() == TreeViewSetup.Hint.DEVICE_AUDIO) {
			DeviceSourceView dvw = (DeviceSourceView)parent_wrapper;
			((Device)dvw.get_object()).remove_medias(toRemove);
		}
		
		if(get_hint() == TreeViewSetup.Hint.PLAYLIST) {
			BasePlaylist p = (StaticPlaylist)App.playlists.playlist_from_id(relative_id);
			
			((StaticPlaylist)p).remove_medias(toRemove);
			App.playlists.update_playlist(p);
		}
	}

	void importToLibraryClicked() {
		var to_import = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			to_import.add(m);
		}

		import_requested(to_import);
	}

	public void apply_style_to_view(CssProvider style) {
		get_style_context().add_provider(style, STYLE_PROVIDER_PRIORITY_APPLICATION);
	}
	
	int view_compare_func (int col, Gtk.SortType dir, Media a_media, Media b_media) {
		int rv = 0;
		
		if(col == MusicColumn.NUMBER) {
			rv = 1;//a.get_position() - b.get_position();
		}
		else if(col == MusicColumn.TRACK) {
			if(a_media.track == b_media.track)
				rv = advanced_string_compare(a_media.uri, b_media.uri);
			else
				rv = (int)((int)a_media.track - (int)b_media.track);
		}
		else if(col == MusicColumn.TITLE) {
			rv = advanced_string_compare(a_media.title_key, b_media.title_key);
		}
		else if(col == MusicColumn.LENGTH) {
			rv = (int)(a_media.length - b_media.length);
		}
		else if(col == MusicColumn.ARTIST) {
			if(a_media.album_artist_key == b_media.album_artist_key) {
				if(a_media.album_key == b_media.album_key) {
					if(a_media.album_number == b_media.album_number) {
						if(a_media.track == b_media.track)
							rv = advanced_string_compare(a_media.uri, b_media.uri);
						else
							rv = (int)((sort_direction == SortType.ASCENDING) ? (int)((int)a_media.track - (int)b_media.track) : (int)((int)b_media.track - (int)a_media.track));
					}
					else
						rv = (int)((int)a_media.album_number - (int)b_media.album_number);
				}
				else
					rv = advanced_string_compare(a_media.album_key, b_media.album_key);
			}
			else
				rv = advanced_string_compare(a_media.album_artist_key, b_media.album_artist_key);
		}
		else if(col == MusicColumn.ALBUM) {
			if(a_media.album_key == b_media.album_key) {
				if(a_media.album_number == b_media.album_number) {
					if(a_media.track == b_media.track)
						rv = advanced_string_compare(a_media.uri, b_media.uri);
					else
						rv = (int)((sort_direction == SortType.ASCENDING) ? (int)((int)a_media.track - (int)b_media.track) : (int)((int)b_media.track - (int)a_media.track));
				}
				else
					rv = (int)((int)a_media.album_number - (int)b_media.album_number);

			}
			else {
				if(a_media.album == "")
					rv = 1;
				else
					rv = advanced_string_compare(a_media.album_key, b_media.album_key);
			}
		}
		else if(col == MusicColumn.GENRE) {
			rv = advanced_string_compare(a_media.genre.down(), b_media.genre.down());
		}
		else if(col == MusicColumn.YEAR) {
			rv = (int)(a_media.year - b_media.year);
		}
		else if(col == MusicColumn.BITRATE) {
			rv = (int)(a_media.bitrate - b_media.bitrate);
		}
		else if(col == MusicColumn.RATING) {
			rv = (int)(a_media.rating - b_media.rating);
		}
		else if(col == MusicColumn.LAST_PLAYED) {
			rv = (int)(a_media.last_played - b_media.last_played);
		}
		else if(col == MusicColumn.DATE_ADDED) {
			rv = (int)(a_media.date_added - b_media.date_added);
		}
		else if(col == MusicColumn.PLAY_COUNT) {
			rv = (int)(a_media.play_count - b_media.play_count);
		}
		else if(col == MusicColumn.SKIP_COUNT) {
			rv = (int)(a_media.skip_count - b_media.skip_count);
		}
		else if(col == MusicColumn.BPM) {
			rv = (int)(a_media.bpm - b_media.bpm);
		}
		else {
			rv = 0;
		}
		
		//if(rv == 0 && col != MusicColumn.ARTIST && col != MusicColumn.ALBUM)
		//	rv = advanced_string_compare(a_media.uri, b_media.uri);

		if(sort_direction == SortType.DESCENDING)
			rv = (rv > 0) ? -1 : 1;

		return rv;
	}
	
	Value view_value_func (int row, int column, Media s) {
		Value val;
		
		if(column == MusicColumn.ROWID)
			val = s.rowid;
		else if(column == MusicColumn.ICON) {
			if(App.playback.current_media != null && App.playback.current_media == s)
				val = playing_icon;
			else if(tvs.get_hint() == TreeViewSetup.Hint.CDROM && !s.isTemporary)
				val = completed_icon;
			else if(s.unique_status_image != null)
				val = s.unique_status_image;
			else if(s is Podcast && s.last_played == 0)
				val = new_podcast_icon;
			else if(s is Podcast && !s.uri.has_prefix("http://"))
				val = saved_locally_icon;
			else
				val = Value(typeof(GLib.Icon));
		}
		else if(column == MusicColumn.NUMBER)
			val = (int)(row + 1);
		else if(column == MusicColumn.TRACK)
			val = (int)s.track;
		else if(column == MusicColumn.TITLE)
			val = s.title;
		else if(column == MusicColumn.LENGTH)
			val = (int)s.length;
		else if(column == MusicColumn.ARTIST)
			val = s.artist;
		else if(column == MusicColumn.ALBUM)
			val = s.album;
		else if(column == MusicColumn.GENRE)
			val = s.genre;
		else if(column == MusicColumn.YEAR)
			val = (int)s.year;
		else if(column == MusicColumn.BITRATE)
			val = (int)s.bitrate;
		else if(column == MusicColumn.RATING)
			val = (int)s.rating;
		else if(column == MusicColumn.PLAY_COUNT)
			val = (int)s.play_count;
		else if(column == MusicColumn.SKIP_COUNT)
			val = (int)s.skip_count;
		else if(column == MusicColumn.DATE_ADDED)
			val = (int)s.date_added;
		else if(column == MusicColumn.LAST_PLAYED)
			val = (int)s.last_played;
		else if(column == MusicColumn.BPM)
			val = (int)s.bpm;
		else// if(column == 17)
			val = (int)s.pulseProgress;
		
		return val;
	}
}

