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

public class BeatBox.PodcastList : GenericList {
    
    
	public TreeViewSetup podcast_setup { set; get; }

	//for media list right click
	PopMenu mediaMenuActionMenu;
	PopMenuItem mediaEditMedia;
	PopMenuItem mediaFileBrowse;
	PopMenuItem mediaMenuQueue;
	PopMenuItem mediaMenuNewPlaylist;
	PopMenuItem mediaMenuAddToPlaylist; // opens the playlists menu, made on each right click
	PopMenu addToPlaylistMenu;
	RatingMenuItem mediaRateMedia;
	PopMenuItem mediaRemove;
	PopMenuItem mediaUnsubscribe;
	PopMenuItem mediaSaveLocally;
	PopMenuItem importToLibrary;

	public PodcastList(TreeViewSetup tvs) {
		base(tvs);
		
		//last_search = "";
		//timeout_search = new LinkedList<string>();
		//showing_all = true;
		//removing_medias = false;

		buildUI();
	}

	public override void update_sensitivities() {
		if(get_hint() == TreeViewSetup.Hint.PODCAST) {
			mediaRemove.set_visible(true);
			mediaRemove.set_label(_("Remove from Library"));
			mediaUnsubscribe.set_visible(true);
			importToLibrary.set_visible(false);
		}
		else if(get_hint() == TreeViewSetup.Hint.DEVICE_PODCAST) {
			mediaRemove.set_visible(false);
			mediaUnsubscribe.set_visible(false);
			mediaRemove.set_label(_("Remove from Device"));
			importToLibrary.set_visible(true);
			mediaSaveLocally.set_visible(false);
			mediaMenuAddToPlaylist.set_visible(false);
			mediaMenuNewPlaylist.set_visible(false);
		}
		else {
			mediaRemove.set_visible(false);
			mediaUnsubscribe.set_visible(false);
		}
	}

    public void buildUI() {
		add_columns();
		
		set_compare_func(view_compare_func);
        set_search_func(view_search_func);
        set_value_func(view_value_func);

		click_gesture.pressed.connect(view_click);

		// column chooser menu (header right click)
		add_column_toggle("Episode", _("Episode"));
		add_column_toggle("Name", _("Name"));
		add_column_toggle("Length", _("Length"));
		add_column_toggle("Artist", _("Artist"));
		add_column_toggle("Podcast", _("Podcast"));
		add_column_toggle("Date", _("Date"));
		add_column_toggle("Category", _("Category"));
		add_column_toggle("Comment", _("Comment"));
		add_column_toggle("Rating", _("Rating"));


		//media list right click menu
		mediaMenuActionMenu = new PopMenu();
		mediaEditMedia = new PopMenuItem.with_label(_("Edit Podcast"));
		mediaFileBrowse = new PopMenuItem.with_label(_("Show in File Browser"));
		mediaMenuQueue = new PopMenuItem.with_label(_("Add to Queue"));
		mediaMenuNewPlaylist = new PopMenuItem.with_label(_("New Playlist"));
		mediaMenuAddToPlaylist = new PopMenuItem.with_label(_("Add to Playlist"));
		mediaRemove = new PopMenuItem.with_label(_("Remove Episode"));
		mediaUnsubscribe = new PopMenuItem.with_label(_("Unsubscribe from Podcast"));
		mediaSaveLocally = new PopMenuItem.with_label(_("Download"));
		importToLibrary = new PopMenuItem.with_label(_("Import to Library"));
		mediaRateMedia = new RatingMenuItem();
		mediaMenuActionMenu.append(mediaEditMedia);
		mediaMenuActionMenu.append(mediaFileBrowse);
		mediaMenuActionMenu.append(mediaSaveLocally);

		mediaMenuActionMenu.append(mediaRateMedia);

		mediaMenuActionMenu.append(new PopMenuSeparator());
		mediaMenuActionMenu.append(mediaMenuQueue);
		mediaMenuActionMenu.append(mediaMenuNewPlaylist);
		mediaMenuActionMenu.append(mediaMenuAddToPlaylist);
		mediaMenuActionMenu.append(new PopMenuSeparator());
		mediaMenuActionMenu.append(mediaRemove);
		mediaMenuActionMenu.append(mediaUnsubscribe);
		mediaMenuActionMenu.append(importToLibrary);
		mediaEditMedia.clicked.connect(mediaMenuEditClicked);
		mediaFileBrowse.clicked.connect(mediaFileBrowseClicked);
		mediaSaveLocally.clicked.connect(mediaSaveLocallyClicked);
		mediaMenuQueue.clicked.connect(mediaMenuQueueClicked);
		mediaMenuNewPlaylist.clicked.connect(mediaMenuNewPlaylistClicked);
		mediaRemove.clicked.connect(mediaRemoveClicked);
		mediaUnsubscribe.clicked.connect(mediaUnsubscribeClicked);
		importToLibrary.clicked.connect(importToLibraryClicked);
		mediaRateMedia.clicked.connect(mediaRateMediaClicked);
		mediaMenuAddToPlaylist.keep_open = true; // the playlists open beside the menu
		mediaMenuAddToPlaylist.clicked.connect(() => addToPlaylistMenu.popup_under(mediaMenuAddToPlaylist));

		update_sensitivities();
	}
	
	public void cellTitleEdited(string path, string new_text) {
		/*int rowid;
		debug("done!\n");
		if((rowid = list_model.getRowidFromPath(path)) != 0) {
			App.library.media_from_id(rowid).title = new_text;

			App.library.update_media(App.library.media_from_id(rowid), true);
		}
		cellTitle.editable = false; */
	}

	/* a press on a row: the menus, and keeping the selection while several rows are dragged */
	void view_click(int n_press, double x, double y) {
		// a double click is no click for the menus or the selection
		if(n_press != 1)
			return;
		uint button = click_gesture.get_current_button();

		if(button == Gdk.BUTTON_SECONDARY) { //right click
			// the menu acts on the clicked row: select it first, unless it is part of the selection
			int clicked = row_at(x, y);
			if(clicked >= 0 && !is_row_selected(clicked))
				select_only(clicked);

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
			int external_count = 0;
			int temporary_count = 0;
			int total_count = 0;
			string podcast_folder = App.library.podcast_library.folder.get_uri();
			
			foreach(Media m in get_selected_medias()) {
				if(!m.uri.has_prefix(podcast_folder))
					++external_count;
				if(m.isTemporary)
					++temporary_count;

				++total_count;
			}

			if(external_count == 0)
				mediaSaveLocally.set_sensitive(false);
			else {
				mediaSaveLocally.set_sensitive(true);
				if(external_count != total_count)
					mediaSaveLocally.label = "Download " + external_count.to_string() + " of " + total_count.to_string() + " selected episodes";
				else
					mediaSaveLocally.label = "Download" + ((external_count > 1) ? (" " + external_count.to_string() + " episodes") : "");
			}

			if(temporary_count == 0)
				importToLibrary.set_sensitive(false);
			else {
				importToLibrary.set_sensitive(true);
				if(temporary_count != total_count)
					importToLibrary.label = "Import " + temporary_count.to_string() + " of " + total_count.to_string() + " selected episodes";
				else
					importToLibrary.label = "Import" + ((temporary_count > 1) ? (" " + temporary_count.to_string() + " episodes") : "");
			}

			//mediaMenuActionMenu.show_all();

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
			click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
	}

	protected override void updateTreeViewSetup() {
		if(tvs == null || get_n_columns() != tvs.get_columns().length())
			return;

		int sort_id = PodcastColumn.ARTIST;
		SortType sort_dir = Gtk.SortType.ASCENDING;
		get_sort_column_id(out sort_id, out sort_dir);

		if(sort_id < 0)
			sort_id = PodcastColumn.ARTIST;

		tvs.set_columns(get_column_setup());
		tvs.sort_column_id = sort_id;
		tvs.sort_direction = sort_dir;
	}

	 void mediaFileBrowseClicked() {
		int count = 0;
		foreach(Media m in get_selected_medias()) {
			try {
				AppInfo.launch_default_for_uri(File.new_for_uri(m.uri).get_parent().get_uri(), null);
			}
			catch(GLib.Error err) {
				warning("Could not browse media %s: %s", m.uri, err.message);
			}

			if(count > 10) {
				App.window.doAlert(_("Stopping File Browse"), _("Too many medias have already been opened in File Browser. Stopping any more openings."));
				return;
			}
		}
	}

	void mediaSaveLocallyClicked() {
		var toSave = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			toSave.add(m);
		}
		
		App.podcasts.download_podcasts(toSave);
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

	 void mediaRemoveClicked() {
		LinkedList<Media> toRemove = new LinkedList<Media>();

		foreach(Media m in get_selected_medias()) {
			toRemove.add(m);
		}

		if(get_hint() == TreeViewSetup.Hint.PODCAST) {
			var dialog = new RemoveFilesDialog (toRemove, get_hint());

			dialog.remove_media.connect ( (delete_files) => {
				App.library.remove_medias (toRemove, delete_files);
			});
		}
	}

	/* Subscriptions are the feeds of the episodes in the library, so unsubscribing is
	 * removing every episode of the feeds of the selection. */
	void mediaUnsubscribeClicked() {
		var feeds = new HashSet<string>();
		foreach(Media m in get_selected_medias()) {
			if(m.rss_uri != null && m.rss_uri != "")
				feeds.add(m.rss_uri);
		}

		var toRemove = new LinkedList<Media>();
		foreach(Media m in App.library.podcast_library.medias()) {
			if(!m.isTemporary && m.rss_uri != null && feeds.contains(m.rss_uri))
				toRemove.add(m);
		}
		if(toRemove.size == 0)
			return;

		var dialog = new RemoveFilesDialog (toRemove, get_hint());
		dialog.remove_media.connect ( (delete_files) => {
			App.library.remove_medias (toRemove, delete_files);
		});
	}

	void importToLibraryClicked() {
		var to_import = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			to_import.add(m);
		}

		import_requested(to_import);
	}
	
	int view_compare_func (int col, Gtk.SortType dir, Media a_media, Media b_media) {
		int rv = 0;
		
		Podcast a = (Podcast)a_media;
		Podcast b = (Podcast)b_media;
		
		if(col == PodcastColumn.EPISODE) {
			if(a.episode == b.episode)
				rv = advanced_string_compare(a_media.uri, b_media.uri);
			else
				rv = (int)((int)a.episode - (int)b.episode);
		}
		else if(col == PodcastColumn.NAME) {
			rv = advanced_string_compare(a_media.title.down(), b_media.title.down());
		}
		else if(col == PodcastColumn.LENGTH) {
			rv = (int)(a_media.length - b_media.length);
		}
		else if(col == PodcastColumn.ARTIST) {
			if(a_media.artist.down() == b_media.artist.down()) {
				if(a.date_released == b.date_released) {
					rv = advanced_string_compare(a_media.uri, b_media.uri);
				}
				else {
					rv = (int)(b.date_released - a.date_released);
				}
			}
			else
				rv = advanced_string_compare(a_media.artist.down(), b_media.artist.down());
		}
		else if(col == PodcastColumn.PODCAST) {
			if(a_media.album.down() == b_media.album.down()) {
				if(a_media.artist.down() == b_media.artist.down()) {
					if(a.date_released == b.date_released) {
						rv = advanced_string_compare(a_media.uri, b_media.uri);
					}
					else {
						rv = (int)(b.date_released - a.date_released);
					}
				}
				else
					rv = advanced_string_compare(a_media.artist.down(), b_media.artist.down());
			}
			else
				rv = advanced_string_compare(a_media.album.down(), b_media.album.down());
		}
		else if(col == PodcastColumn.DATE) {
			rv = (int)(a.date_released - b.date_released);
		}
		else if(col == PodcastColumn.CATEGORY) {
			rv = advanced_string_compare(a_media.genre.down(), b_media.genre.down());
		}
		else if(col == PodcastColumn.RATING) {
			rv = (int)(a_media.rating - b_media.rating);
		}
		else {
			rv = 0;
		}
		
		if(rv == 0 && col != PodcastColumn.ARTIST && col != PodcastColumn.PODCAST)
			rv = advanced_string_compare(a_media.uri, b_media.uri);
		
		if(sort_direction == SortType.DESCENDING)
			rv = (rv > 0) ? -1 : 1;
		
		return rv;
	}
	
	Value view_value_func (int row, int column, Media s) {
		Value val;
		
		Podcast p = (Podcast)s;
		
		if(column == PodcastColumn.ROWID)
			val = (int)s.rowid;
		else if(column == PodcastColumn.ICON) {
			if(App.playback.media_active && App.playback.current_media == s)
				val = playing_icon;
			else if(s.unique_status_image != null) {
				val = s.unique_status_image;
			}
			else if(s.last_played == 0)
				val = new_podcast_icon;
			else if(!s.uri.has_prefix("http://")) {
				val = saved_locally_icon;
			}
			else {
				val = Value(typeof(GLib.Icon));
			}
		}
		else if(column == PodcastColumn.EPISODE)
			val = (int)p.episode;
		else if(column == PodcastColumn.NAME)
			val = s.title;
		else if(column == PodcastColumn.LENGTH)
			val = (int)s.length;
		else if(column == PodcastColumn.ARTIST)
			val = s.artist;
		else if(column == PodcastColumn.PODCAST)
			val = s.album;
		else if(column == PodcastColumn.DATE)
			val = (int)p.date_released;
		else if(column == PodcastColumn.CATEGORY)
			val = s.genre; // category
		else if(column == PodcastColumn.COMMENT)
			val = s.comment;
		else if(column == PodcastColumn.RATING)
			val = (int)s.rating;
		else
			val = (int)s.pulseProgress;
		
		return val;
	}
}

