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

public class BeatBox.DuplicateList : GenericList {
	public const string CHECKBOX_COLUMN_TITLE = "";
	
	//for media list right click
	PopMenu mediaMenuActionMenu;
	PopMenuItem mediaCheck;
	PopMenuItem mediaUncheck;
	PopMenuItem mediaFileBrowse;
	PopMenuItem mediaRemove;
	
	HashMap<Media, bool> checked;
	
	public signal void checked_changed();
	
	public enum DuplicateColumn {
		ROWID,
		CHECKBOX,
		ICON,
		NUMBER,
		TRACK,
		TITLE,
		LENGTH,
		ARTIST,
		ALBUM,
		GENRE,
		YEAR,
		BITRATE,
		RATING,
		PLAY_COUNT,
		SKIP_COUNT,
		DATE_ADDED,
		LAST_PLAYED,
		BPM,
		PULSER
	}

	/**
	 * for sort_id use 0+ for normal, -1 for auto, -2 for none
	 */
	public DuplicateList(TreeViewSetup tvs) {
		var types = new GLib.List<Type>();
		types.append(typeof(int)); // id
		types.append(typeof(bool)); // checkbox
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
		
		checked = new HashMap<Media, bool>();

		buildUI();
	}

	public override void update_sensitivities() {
		// GTK4 shows the menu items as they are created; there is no show_all ()
	}

	public void buildUI() {
		add_columns ();
		
		set_compare_func(view_compare_func);
        set_search_func(view_search_func);
        set_value_func(view_value_func);
        
		click_gesture.pressed.connect(view_click);
		click_gesture.released.connect(view_click_release);

		// column chooser menu (header right click)
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
		mediaCheck = new PopMenuItem.with_label(_("Check"));
		mediaUncheck = new PopMenuItem.with_label(_("Uncheck"));
		mediaFileBrowse = new PopMenuItem.with_label(_("Show in File Browser"));
		mediaRemove = new PopMenuItem.with_label(_("Remove Media"));
		mediaMenuActionMenu.append(mediaCheck);
		mediaMenuActionMenu.append(mediaUncheck);
		mediaMenuActionMenu.append(new PopMenuSeparator());
		mediaMenuActionMenu.append(mediaFileBrowse);
		mediaMenuActionMenu.append(mediaRemove);
		mediaCheck.clicked.connect(mediaCheckClicked);
		mediaUncheck.clicked.connect(mediaUncheckClicked);
		mediaFileBrowse.clicked.connect(mediaFileBrowseClicked);
		mediaRemove.clicked.connect(mediaRemoveClicked);
		
		update_sensitivities();
	}
	
	/* a press on a row: the menus, the checkbox column, and keeping the selection while several rows are dragged */
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

			mediaMenuActionMenu.popup_at(this, x, y);

			TreeSelection selected = get_selection();
			selected.set_mode(SelectionMode.MULTIPLE);
			if(selected.count_selected_rows() > 1)
				click_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
		}
		else if(button == 1) {
			// Check/uncheck column
			TreePath? path;
			if(row_at(x, y, out path)) {
				int bin_x, bin_y;
				convert_widget_to_bin_window_coords((int)x, (int)y, out bin_x, out bin_y);
				TreeViewColumn? column;
				int cell_x, cell_y;
				if(get_path_at_pos(bin_x, bin_y, out path, out column, out cell_x, out cell_y) &&
				   column != null && column.sort_column_id == DuplicateColumn.CHECKBOX) {
					Media m = get_media_from_index(int.parse(path.to_string()));
					bool cur_val = checked.get(m);
					checked.set(m, !cur_val);
					checked_changed();
				}
			}

			/* don't unselect everything if multiple selected until button release
			 * for drag and drop reasons */
			if(get_selection().count_selected_rows() > 1) {
				TreePath? clicked;
				row_at(x, y, out clicked);
				bool on_selection = clicked != null && get_selection().path_is_selected(clicked);
				if(on_selection && modified)
					get_selection().unselect_path(clicked);
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

	protected override void updateTreeViewSetup() {
		return;
	}

	void mediaCheckClicked() {
		foreach(Media m in get_selected_medias()) {
			checked.set(m, true);
		}
	}
	
	void mediaUncheckClicked() {
		foreach(Media m in get_selected_medias()) {
			checked.set(m, false);
		}
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
	
	 void mediaRemoveClicked() {
		LinkedList<Media> toRemove = new LinkedList<Media>();
		
		foreach(Media m in get_selected_medias()) {
			toRemove.add(m);
		}
		
		var dialog = new RemoveFilesDialog (toRemove, get_hint());

		dialog.remove_media.connect ( (delete_files) => {
			App.library.remove_medias (toRemove, delete_files);
		});
	}

	
	int view_compare_func (int col, Gtk.SortType dir, Media a_media, Media b_media) {
		int rv = 0;
		
		if(col == DuplicateColumn.NUMBER) {
			rv = 1;//a.get_position() - b.get_position();
		}
		else if(col == DuplicateColumn.TRACK) {
			if(a_media.track == b_media.track)
				rv = advanced_string_compare(a_media.uri, b_media.uri);
			else
				rv = (int)((int)a_media.track - (int)b_media.track);
		}
		else if(col == DuplicateColumn.TITLE) {
			rv = advanced_string_compare(a_media.title.down(), b_media.title.down());
		}
		else if(col == DuplicateColumn.LENGTH) {
			rv = (int)(a_media.length - b_media.length);
		}
		else if(col == DuplicateColumn.ARTIST) {
			if(a_media.album_artist.down() == b_media.album_artist.down()) {
				if(a_media.album.down() == b_media.album.down()) {
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
					rv = advanced_string_compare(a_media.album.down(), b_media.album.down());
			}
			else
				rv = advanced_string_compare(a_media.album_artist.down(), b_media.album_artist.down());
		}
		else if(col == DuplicateColumn.ALBUM) {
			if(a_media.album.down() == b_media.album.down()) {
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
					rv = advanced_string_compare(a_media.album.down(), b_media.album.down());
			}
		}
		else if(col == DuplicateColumn.GENRE) {
			rv = advanced_string_compare(a_media.genre.down(), b_media.genre.down());
		}
		else if(col == DuplicateColumn.YEAR) {
			rv = (int)(a_media.year - b_media.year);
		}
		else if(col == DuplicateColumn.BITRATE) {
			rv = (int)(a_media.bitrate - b_media.bitrate);
		}
		else if(col == DuplicateColumn.RATING) {
			rv = (int)(a_media.rating - b_media.rating);
		}
		else if(col == DuplicateColumn.LAST_PLAYED) {
			rv = (int)(a_media.last_played - b_media.last_played);
		}
		else if(col == DuplicateColumn.DATE_ADDED) {
			rv = (int)(a_media.date_added - b_media.date_added);
		}
		else if(col == DuplicateColumn.PLAY_COUNT) {
			rv = (int)(a_media.play_count - b_media.play_count);
		}
		else if(col == DuplicateColumn.SKIP_COUNT) {
			rv = (int)(a_media.skip_count - b_media.skip_count);
		}
		else if(col == DuplicateColumn.BPM) {
			rv = (int)(a_media.bpm - b_media.bpm);
		}
		else {
			rv = 0;
		}

		if(sort_direction == SortType.DESCENDING)
			rv = (rv > 0) ? -1 : 1;

		return rv;
	}
	
	Value view_value_func (int row, int column, Media s) {
		Value val;
		
		if(column == DuplicateColumn.ROWID)
			val = s.rowid;
		else if(column == DuplicateColumn.CHECKBOX)
			val = checked.get(s);
		else if(column == DuplicateColumn.ICON) {
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
		else if(column == DuplicateColumn.NUMBER)
			val = (int)(row + 1);
		else if(column == DuplicateColumn.TRACK)
			val = (int)s.track;
		else if(column == DuplicateColumn.TITLE)
			val = s.title;
		else if(column == DuplicateColumn.LENGTH)
			val = (int)s.length;
		else if(column == DuplicateColumn.ARTIST)
			val = s.artist;
		else if(column == DuplicateColumn.ALBUM)
			val = s.album;
		else if(column == DuplicateColumn.GENRE)
			val = s.genre;
		else if(column == DuplicateColumn.YEAR)
			val = (int)s.year;
		else if(column == DuplicateColumn.BITRATE)
			val = (int)s.bitrate;
		else if(column == DuplicateColumn.RATING)
			val = (int)s.rating;
		else if(column == DuplicateColumn.PLAY_COUNT)
			val = (int)s.play_count;
		else if(column == DuplicateColumn.SKIP_COUNT)
			val = (int)s.skip_count;
		else if(column == DuplicateColumn.DATE_ADDED)
			val = (int)s.date_added;
		else if(column == DuplicateColumn.LAST_PLAYED)
			val = (int)s.last_played;
		else if(column == DuplicateColumn.BPM)
			val = (int)s.bpm;
		else// if(column == 18)
			val = (int)s.pulseProgress;
		
		return val;
	}
	
	public void clear_checked() {
		checked.clear();
	}
	
	public void set_checked(Media m, bool val) {
		checked.set(m, val);
	}
	
	public Collection<Media> get_checked_medias() {
		var rv = new LinkedList<Media>();
		
		foreach(var m in checked.keys) {
			if(checked.get(m))
				rv.add(m);
		}
		
		return rv;
	}
}

