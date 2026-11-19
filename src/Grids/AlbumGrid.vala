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

public class BeatBox.AlbumGrid : GenericGrid {

	public AlbumGrid(SourceView parent_wrapper, TreeViewSetup tvs) {
		base(parent_wrapper, tvs, new Album("", ""));

		set_compare_func(compare_func);
		set_value_func(val_func);
		set_search_func(grid_search_func);

		drag_source.drag_begin.connect(on_drag_begin);
		drag_source.drag_end.connect(on_drag_end);
		
        default_art = App.covers.DEFAULT_COVER_SHADOW;
	}
	
	protected override void updateTreeViewSetup() {
		
	}
	
	protected override void update_sensitivities() {
		
	}
	
	public override void item_activated_handler (Object? selected) {
        if (selected == null && !has_popup_list)
            return;
        this.popup_list.set_parent_wrapper (this.parent_wrapper);

        if (selected != null) {
	        var alb = selected as Album;
	        return_if_fail (alb != null);
	        this.popup_list.set_items(alb);
	        this.popup_list.show_list();
        } else {
            this.popup_list.hide ();
        }
	}
	
	/** **********************************************************
	 * Drag and drop support. GenericView is a source for uris and can
	 * be dragged to a playlist in the sidebar. No support for reordering
	 * is implemented yet.
	***************************************************************/
	void on_drag_begin(Gdk.Drag drag) {
		dragging = true;
		App.window.dragging_from_music = true;
		debug("drag begin\n");

		string icon_name;
		if(count_selected() == 1) {
			icon_name = "audio-x-generic";
		}
		else if(count_selected() > 1) {
			icon_name = "folder-music";
		}
		else {
			return;
		}
		var icon = Gtk.IconTheme.get_for_display (get_display ()).lookup_icon (icon_name, null, 32, 1, Gtk.TextDirection.NONE, 0);
		drag_source.set_icon (icon, 0, 0);
	}

	protected override string[] get_drag_uris() {
		string[] uris = {};

		foreach(var o in get_selected_objects()) {
			Album a = (Album)o;
			foreach(var m in a.get_medias_sorted())
				uris += (m.uri);
		}

		return uris;
	}

	void on_drag_end(Gdk.Drag drag, bool delete_data) {
		dragging = false;
		App.window.dragging_from_music = false;

		debug("drag end\n");

		// no drop reset needed: a grid is only a drag source, GTK4 keeps no drop target on it
	}
	
	/** **************************************************
	 * View search. All lists use same search algorithm 
	 * *************************************************/
	protected void grid_search_func (string search, HashTable<int, GLib.Object> table, ref HashTable<int, GLib.Object> show) {
		int show_index = 0;
		
		for(int i = 0; i < table.size(); ++i) {
			Album m = (Album)table.get(i);
			
			if(search in m.get_album_artist().down() || search in m.get_album().down()) {
				if(parent_wrapper.album_passes_filters(m)) {
					show.set(show_index++, m);
				}
			}
		}
	}
	
	/***********************************************
	 * Grid value func. Returns markup and pix based on Album
	 * ********************************************/
	string TEXT_MARKUP = "<b>%s</b>\n<span fgalpha='65%%'>%s</span>";
	string TOOLTIP_MARKUP = "%s\n%s";
	Value val_func (int row, int column, GLib.Object a_o) {
		Album a = (Album)a_o;
		Value val;
		
		if(column == PIXBUF_COLUMN) {
			var pix = App.covers.get_album_art_from_key(a.get_album_artist(), a.get_album());
			if(pix == null)
				pix = default_art;
				
			val = pix;
		}
		else if(column == MARKUP_COLUMN) {
			string album_artist, album;
			
			album = String.ellipsize(a.get_album(), 30);

			album_artist = String.ellipsize(a.get_album_artist(), 25);
			
			album = Markup.escape_text(album);
			album_artist = Markup.escape_text(album_artist);
			val = TEXT_MARKUP.printf(album, album_artist);
		}
		else if(column == TOOLTIP_COLUMN) {
			string album = Markup.escape_text(a.get_album());
			string album_artist = Markup.escape_text(a.get_album_artist());
			
			val = TOOLTIP_MARKUP.printf (album, album_artist);
		}
		else {
			val = a;
		}
		
		return val;
	}
	
	int compare_func(GLib.Object o_a, GLib.Object o_b) {
		Album a = (Album)o_a;
		Album b = (Album)o_b;
		
		// by the sort names of a song of each (the Sorting tab), if they have any
		var ma = first_media(a);
		var mb = first_media(b);
		string artist_a = (ma != null) ? ma.album_artist_key : a.get_album_artist().down();
		string artist_b = (mb != null) ? mb.album_artist_key : b.get_album_artist().down();
		if(artist_a == artist_b) {
			string album_a = (ma != null) ? ma.album_key : a.get_album().down();
			string album_b = (mb != null) ? mb.album_key : b.get_album().down();
			if(album_a == album_b) {
				return a.count() - b.count();
			}
			else {
				return advanced_string_compare(album_a, album_b);
			}
		}
		else {
			return advanced_string_compare(artist_a, artist_b);
		}
	}
	
	static Media? first_media(Album album) {
		foreach(var m in album.get_medias())
			return m;
		return null;
	}
	
	int advanced_string_compare(string a, string b) {
		if(a == "" && b != "")
			return 1;
		else if(a != "" && b == "")
			return -1;
		else if(a == b)
			return 0;
		
		return (a > b) ? 1 : -1;
	}
}

