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

public abstract class BeatBox.ActionsInterface : GLib.Object {
	public SimpleAction create_playlist { get; protected set; }
	public SimpleAction create_smart_playlist { get; protected set; }
	public SimpleAction import_playlist { get; protected set; }
	public SimpleAction import_station { get; protected set; }
	public SimpleAction add_podcast_feed { get; protected set; }
	public SimpleAction refresh_podcasts { get; protected set; }
	public SimpleAction show_preferences { get; protected set; }
	public SimpleAction show_equalizer { get; protected set; }
	public SimpleAction next { get; protected set; }
	public SimpleAction play_pause { get; protected set; }
	public SimpleAction previous { get; protected set; }
	public SimpleAction lastfm_ban { get; protected set; }
	public SimpleAction lastfm_love { get; protected set; }
	public SimpleAction show_duplicates { get; protected set; }
	public SimpleAction hide_duplicates { get; protected set; }
	public SimpleAction exit { get; protected set; }
	
	/** All the actions, as "bb.<name>" */
	public SimpleActionGroup group { get; protected set; }
	
	/** A menu item labelled for the action, greyed out (or hidden, for some) while it is disabled */
	public abstract Gtk.MenuItem menu_item(SimpleAction action);
	
	public abstract void destroy_equalizer();
	public abstract void show_set_library_folder_dialog(Library library);
	public abstract void show_import_folders_dialog(Library library);
}
