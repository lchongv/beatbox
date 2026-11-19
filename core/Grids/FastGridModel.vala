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


/** The covers a FastGrid shows: its visible table (sorted and searched by the grid) as a
 *  GLib.ListModel for Gtk.GridView (Gtk.TreeModel is deprecated since GTK 4.10). */
[GIR (visible = false)] // internal, not for plugins
public class BeatBox.FastGridModel : GLib.Object, GLib.ListModel {
	GenericArray<GLib.Object> rows = new GenericArray<GLib.Object> ();

	public Type get_item_type () {
		return typeof (GLib.Object);
	}

	public uint get_n_items () {
		return rows.length;
	}

	public Object? get_item (uint position) {
		return position < rows.length ? rows[position] : null;
	}

	/** Shows the objects of a table numbered 0..n-1 (no gaps) */
	public void set_table (HashTable<int, GLib.Object> table) {
		uint old_n = rows.length;
		var fresh = new GenericArray<GLib.Object> (table.size ());
		for (int i = 0; i < table.size (); i++)
			fresh.add (table.get (i));
		rows = fresh;
		items_changed (0, old_n, rows.length);
	}
}
