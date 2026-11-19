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

/** A column of a song list as it is kept between sessions: its title (the English key the
 *  lists match on), its width and whether it shows */
public class BeatBox.ListColumn : GLib.Object {
	public string title;
	public int width;
	public bool visible;

	public ListColumn(string title, int width, bool visible) {
		this.title = title;
		this.width = width;
		this.visible = visible;
	}
}

public class BeatBox.TreeViewSetup : GLib.Object {
	
	// TODO: Fixme. I am a duplicate of DuplicateList.CHECKBOX_COLUMN_TITLE
	// for core dependency reasons
	public const string CHECKBOX_COLUMN_TITLE = "";
	
	public const int MUSIC_COLUMN_COUNT = 18; // MusicColumn but PRICE, which no list shows
	public const int DUPLICATE_COLUMN_COUNT = 19;
	public const int PODCAST_COLUMN_COUNT = 12;
	public const int RADIO_COLUMN_COUNT = 6;
	
	public const int ID_WIDTH = 10;
	public const int ICON_WIDTH = 24;
	public const int NUMBER_WIDTH = 40;
	public const int TRACK_WIDTH = 60;
	public const int TITLE_WIDTH = 220;
	public const int ALBUM_VIEW_TITLE_WIDTH = 300;
	public const int LENGTH_WIDTH = 75;
	public const int ARTIST_WIDTH = 170;
	public const int ALBUM_WIDTH = 200;
	public const int GENRE_WIDTH = 100;
	public const int YEAR_WIDTH = 50;
	public const int BITRATE_WIDTH = 85;
	public const int RATING_WIDTH = 90;
	public const int PLAYS_WIDTH = 65;
	public const int SKIPS_WIDTH = 65;
	public const int DATE_ADDED_WIDTH = 130;
	public const int LAST_PLAYED_WIDTH = 130;
	public const int BPM_WIDTH = 50;
	public const int PULSER_WIDTH = 40;
	public const int COMMENT_WIDTH = 70;
	public const int STATION_WIDTH = 300;
	
	public enum Hint {
		MUSIC,
		PODCAST,
		AUDIOBOOK,
		STATION,
		SIMILAR,
		QUEUE,
		HISTORY,
		PLAYLIST,
		SMART_PLAYLIST,
		CDROM,
		DEVICE_AUDIO,
		DEVICE_PODCAST,
		DEVICE_AUDIOBOOK,
		ALBUM_LIST,
		DUPLICATES,
		NOW_PLAYING,
		FILES_NOT_FOUND;
	}
	
	Hint hint;
	public int sort_column_id; // Index of sort column
	public Gtk.SortType sort_direction; // ASCENDING, DESCENDING
	GLib.List<ListColumn> _columns;
	
	public TreeViewSetup(int sort_col, SortType sort_dir, Hint hint) {
		this.hint = hint;
		sort_column_id = sort_col;
		sort_direction = sort_dir;
		
		create_default_columns ();
	}
	
	public Hint get_hint() {
		return hint;
	}
	
	public void set_hint(Hint hint) {
		this.hint = hint;
		if(!is_valid_setup())
			create_default_columns ();
	}
	
	// TODO: Translate these column names. This requires removing string
	// comparisions to find what column it is throughout. 
	// TODO: Make nice add_new_column(string title, bool visible, int fixed_width) func
	// TODO: Use const int values
	/** A column as a new list shows it: plain values, so the defaults can be read without making widgets */
	class DefaultColumn {
		public string title;
		public int width;
		public bool visible;
		public DefaultColumn(string title, int width, bool visible) {
			this.title = title;
			this.width = width;
			this.visible = visible;
		}
	}
	
	static Gee.List<DefaultColumn> default_columns (Hint hint) {
		var d = new Gee.ArrayList<DefaultColumn>();
		
		/* initial column state */
		if(hint == TreeViewSetup.Hint.PODCAST || hint == TreeViewSetup.Hint.DEVICE_PODCAST) {
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("Episode", TRACK_WIDTH, false));
			d.add(new DefaultColumn("Name", TITLE_WIDTH, true));
			d.add(new DefaultColumn("Length", LENGTH_WIDTH, true));
			d.add(new DefaultColumn("Artist", ARTIST_WIDTH, true));
			d.add(new DefaultColumn("Podcast", ALBUM_WIDTH, true));
			d.add(new DefaultColumn("Date", LAST_PLAYED_WIDTH, true));
			d.add(new DefaultColumn("Category", GENRE_WIDTH, false));
			d.add(new DefaultColumn("Comment", COMMENT_WIDTH, true));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, false));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		else if(hint == TreeViewSetup.Hint.AUDIOBOOK || hint == TreeViewSetup.Hint.DEVICE_AUDIOBOOK) {
			
		}
		else if(hint == TreeViewSetup.Hint.STATION) {
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("Station", STATION_WIDTH, true));
			d.add(new DefaultColumn("Genre", GENRE_WIDTH, true));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, true));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		else if(hint == TreeViewSetup.Hint.ALBUM_LIST) { // same as normal music list, but most are hidden
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("#", NUMBER_WIDTH, (hint == TreeViewSetup.Hint.QUEUE || hint == TreeViewSetup.Hint.HISTORY || hint == TreeViewSetup.Hint.PLAYLIST)));
			d.add(new DefaultColumn("Track", TRACK_WIDTH, false));
			d.add(new DefaultColumn("Title", ALBUM_VIEW_TITLE_WIDTH, true));
			d.add(new DefaultColumn("Length", LENGTH_WIDTH, true));
			d.add(new DefaultColumn("Artist", ARTIST_WIDTH, false));
			d.add(new DefaultColumn("Album", ALBUM_WIDTH, false));
			d.add(new DefaultColumn("Genre", GENRE_WIDTH, false));
			d.add(new DefaultColumn("Year", YEAR_WIDTH, false));
			d.add(new DefaultColumn("Bitrate", BITRATE_WIDTH, false));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, false));
			d.add(new DefaultColumn("Plays", PLAYS_WIDTH, false));
			d.add(new DefaultColumn("Skips", SKIPS_WIDTH, false));
			d.add(new DefaultColumn("Date Added", DATE_ADDED_WIDTH, false));
			d.add(new DefaultColumn("Last Played", LAST_PLAYED_WIDTH, false));
			d.add(new DefaultColumn("BPM", BPM_WIDTH, false));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		else if(hint == TreeViewSetup.Hint.NOW_PLAYING) { // same as normal music list, but most are hidden and is not very wide
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("#", NUMBER_WIDTH, (hint == TreeViewSetup.Hint.QUEUE || hint == TreeViewSetup.Hint.HISTORY || hint == TreeViewSetup.Hint.PLAYLIST)));
			d.add(new DefaultColumn("Track", TRACK_WIDTH, true));
			d.add(new DefaultColumn("Title", TITLE_WIDTH, true));
			d.add(new DefaultColumn("Length", LENGTH_WIDTH, true));
			d.add(new DefaultColumn("Artist", ARTIST_WIDTH, false));
			d.add(new DefaultColumn("Album", ALBUM_WIDTH, false));
			d.add(new DefaultColumn("Genre", GENRE_WIDTH, false));
			d.add(new DefaultColumn("Year", YEAR_WIDTH, false));
			d.add(new DefaultColumn("Bitrate", BITRATE_WIDTH, false));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, false));
			d.add(new DefaultColumn("Plays", PLAYS_WIDTH, false));
			d.add(new DefaultColumn("Skips", SKIPS_WIDTH, false));
			d.add(new DefaultColumn("Date Added", DATE_ADDED_WIDTH, false));
			d.add(new DefaultColumn("Last Played", LAST_PLAYED_WIDTH, false));
			d.add(new DefaultColumn("BPM", BPM_WIDTH, false));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		else if(hint == TreeViewSetup.Hint.DUPLICATES) {
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(CHECKBOX_COLUMN_TITLE, 30, true));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("#", NUMBER_WIDTH, false));
			d.add(new DefaultColumn("Track", TRACK_WIDTH, false));
			d.add(new DefaultColumn("Title", TITLE_WIDTH, true));
			d.add(new DefaultColumn("Length", LENGTH_WIDTH, true));
			d.add(new DefaultColumn("Artist", ARTIST_WIDTH, true));
			d.add(new DefaultColumn("Album", ALBUM_WIDTH, true));
			d.add(new DefaultColumn("Genre", GENRE_WIDTH, false));
			d.add(new DefaultColumn("Year", YEAR_WIDTH, false));
			d.add(new DefaultColumn("Bitrate", BITRATE_WIDTH, true));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, false));
			d.add(new DefaultColumn("Plays", PLAYS_WIDTH, false));
			d.add(new DefaultColumn("Skips", SKIPS_WIDTH, false));
			d.add(new DefaultColumn("Date Added", DATE_ADDED_WIDTH, false));
			d.add(new DefaultColumn("Last Played", LAST_PLAYED_WIDTH, false));
			d.add(new DefaultColumn("BPM", BPM_WIDTH, false));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		else {
			d.add(new DefaultColumn("id", ID_WIDTH, false));
			d.add(new DefaultColumn(" ", ICON_WIDTH, true));
			d.add(new DefaultColumn("#", NUMBER_WIDTH, (hint == TreeViewSetup.Hint.QUEUE || hint == TreeViewSetup.Hint.HISTORY || hint == TreeViewSetup.Hint.PLAYLIST)));
			d.add(new DefaultColumn("Track", TRACK_WIDTH, false));
			d.add(new DefaultColumn("Title", TITLE_WIDTH, true));
			d.add(new DefaultColumn("Length", LENGTH_WIDTH, true));
			d.add(new DefaultColumn("Artist", ARTIST_WIDTH, true));
			d.add(new DefaultColumn("Album", ALBUM_WIDTH, true));
			d.add(new DefaultColumn("Genre", GENRE_WIDTH, true));
			d.add(new DefaultColumn("Year", YEAR_WIDTH, false));
			d.add(new DefaultColumn("Bitrate", BITRATE_WIDTH, false));
			d.add(new DefaultColumn("Rating", RATING_WIDTH, false));
			d.add(new DefaultColumn("Plays", PLAYS_WIDTH, false));
			d.add(new DefaultColumn("Skips", SKIPS_WIDTH, false));
			d.add(new DefaultColumn("Date Added", DATE_ADDED_WIDTH, false));
			d.add(new DefaultColumn("Last Played", LAST_PLAYED_WIDTH, false));
			d.add(new DefaultColumn("BPM", BPM_WIDTH, false));
			d.add(new DefaultColumn("Pulser", PULSER_WIDTH, false));
		}
		
		return d;
	}
	
	void create_default_columns () {
		_columns = new GLib.List<ListColumn>();
		foreach(var c in default_columns(hint))
			_columns.append(new ListColumn(c.title, c.width, c.visible));
	}
	
	public void set_column_visible(int index, bool val) {
		_columns.nth_data(index).visible = val;
	}
	
	public string sort_direction_to_string() {
		if(sort_direction == SortType.ASCENDING)
			return "ASCENDING";
		else
			return "DESCENDING";
	}
	
	public void set_sort_direction_from_string(string dir) {
		if(dir == "ASCENDING")
			sort_direction = SortType.ASCENDING;
		else
			sort_direction = SortType.DESCENDING;
	}
	
	public GLib.List<ListColumn> get_columns() {
		var rv = new GLib.List<ListColumn>();
		foreach(var c in _columns)
			rv.append(c);
			
		return rv;
	}
	
	public void set_columns(GLib.List<ListColumn> cols) {
		_columns = new GLib.List<ListColumn>();
		foreach(var c in cols)
			_columns.append(c);
	}
	
	public void import_columns(string cols) {
		string[] col_strings = cols.split("<column_seperator>", 0);
		_columns = new GLib.List<ListColumn>();
		
		for(int index = 0; index < col_strings.length - 1; ++index) { /* the '-1' because col_strings has blank column at end */
			string[] pieces_of_column = col_strings[index].split("<value_seperator>", 0);
			if(pieces_of_column.length < 3)
				continue;
			_columns.append(new ListColumn(pieces_of_column[0], int.parse(pieces_of_column[1]), int.parse(pieces_of_column[2]) == 1));
		}
		is_valid_setup(); // one saved with other columns starts anew
	}
	
	public bool is_valid_setup() {
		bool rv = true;
		if(hint == TreeViewSetup.Hint.PODCAST || hint == TreeViewSetup.Hint.DEVICE_PODCAST) {
			if(_columns.length() != PODCAST_COLUMN_COUNT) {
				rv = false;
			}
		}
		/*else if((hint == TreeViewSetup.Hint.AUDIOBOOK || hint == TreeViewSetup.Hint.DEVICE_AUDIOBOOK) && 
		_columns.length() != AUDIOBOOK_) {
			return false;
		}*/
		else if(hint == TreeViewSetup.Hint.STATION) {
			if(_columns.length() != RADIO_COLUMN_COUNT) {
				rv = false;
			}
		}
		else if(hint == TreeViewSetup.Hint.DUPLICATES) {
			if(_columns.length() != DUPLICATE_COLUMN_COUNT) {
				rv = false;
			}
		}
		else if(_columns.length() != MUSIC_COLUMN_COUNT) {
			rv = false;
		}
		
		if(!rv) {
			warning("Invalid treeview setup found. Creating a new one!%u %d %d\n", _columns.length(), PODCAST_COLUMN_COUNT, RADIO_COLUMN_COUNT);
			create_default_columns ();
			return false;
		}
		
		return true;
	}
	
	public string columns_to_string() {
		string rv = "";
		
		// Find the last column that is visible. This column will use a sane
		// default width, since gtk treeview likes to make it super wide
		// which results in horizontal scrolling
		var defaults = default_columns(hint); // not a whole new setup: that made GTK columns, every 15 seconds
		string last_visible_column = "NO_MATCH";
		int default_width_for_last_visible = 70; // 70 is a sane default width
		for(int i = (int)_columns.length() - 1; i >= 0; --i) {
			if(_columns.nth_data(i).visible && i < defaults.size) {
				last_visible_column = defaults[i].title;
				default_width_for_last_visible = defaults[i].width;
				break;
			}
		}
		
		foreach(ListColumn tvc in _columns) {
			int width_to_use = tvc.width;
			
			if(tvc.title == last_visible_column) {
				width_to_use = default_width_for_last_visible;
			}
			
			rv += tvc.title + "<value_seperator>" + width_to_use.to_string() + "<value_seperator>" + ( (tvc.visible) ? "1" : "0" ) + "<column_seperator>";
		}
		
		return rv;
	}
	
	// TODO: FIXME from sort_column to sort_column_id
#if HAVE_GPOD
	[GIR (visible = false)]
	public GPod.PlaylistSortOrder get_gpod_sortorder() {
		warning("FIXME");
		/*if(sort_column == "#")
			return GPod.PlaylistSortOrder.MANUAL;
		else if(sort_column == "Track" || sort_column == "Episode")
			return GPod.PlaylistSortOrder.TRACK_NR;
		else if(sort_column == "Title" || sort_column == "Name")
			return GPod.PlaylistSortOrder.TITLE;
		else if(sort_column == "Length")
			return GPod.PlaylistSortOrder.TIME;
		else if(sort_column == "Artist")
			return GPod.PlaylistSortOrder.ARTIST;
		else if(sort_column == "Album")
			return GPod.PlaylistSortOrder.ALBUM;
		else if(sort_column == "Genre")
			return GPod.PlaylistSortOrder.GENRE;
		else if(sort_column == "Bitrate")
			return GPod.PlaylistSortOrder.BITRATE;
		else if(sort_column == "Year")
			return GPod.PlaylistSortOrder.YEAR;
		else if(sort_column == "Date")
			return GPod.PlaylistSortOrder.RELEASE_DATE;
		else if(sort_column == "Date Added")
			return GPod.PlaylistSortOrder.TIME_ADDED;
		else if(sort_column == "Plays")
			return GPod.PlaylistSortOrder.PLAYCOUNT;
		else if(sort_column == "Last Played")
			return GPod.PlaylistSortOrder.TIME_PLAYED;
		else if(sort_column == "BPM")
			return GPod.PlaylistSortOrder.BPM;
		else if(sort_column == "Rating")
			return GPod.PlaylistSortOrder.RATING;
		else if(sort_column == "Comments")
			return GPod.PlaylistSortOrder.DESCRIPTION;
		else*/
			return GPod.PlaylistSortOrder.MANUAL;
	}
#endif
}

/** A text cell for the song lists, as tall as GTK3 made their rows */
