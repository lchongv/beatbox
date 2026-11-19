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

/** The rows a FastList shows: its visible table (sorted and searched by the list) as a
 *  GLib.ListModel of Media for Gtk.ColumnView (Gtk.TreeModel is deprecated since GTK 4.10).
 *  The list does the sorting and the searching: this only hands out the rows. */
[GIR (visible = false)] // internal, not for plugins
public class BeatBox.FastListModel : GLib.Object, GLib.ListModel {
	GenericArray<Media> rows = new GenericArray<Media> ();

	public Type get_item_type () {
		return typeof (Media);
	}

	public uint get_n_items () {
		return rows.length;
	}

	public Object? get_item (uint position) {
		return position < rows.length ? rows[position] : null;
	}

	public Media? get_media (uint position) {
		return position < rows.length ? rows[position] : null;
	}

	/** Shows the rows of a table numbered 0..n-1 (no gaps). Rows that stay the same at the
	 *  start and the end are kept, so a small change redraws little. */
	public void set_table (HashTable<int, Media> table) {
		uint old_n = rows.length, new_n = table.size ();
		uint same_start = 0;
		while (same_start < old_n && same_start < new_n && rows[same_start] == table.get ((int) same_start))
			same_start++;
		uint same_end = 0;
		while (same_end < old_n - same_start && same_end < new_n - same_start
		       && rows[old_n - 1 - same_end] == table.get ((int) (new_n - 1 - same_end)))
			same_end++;
		if (same_start == old_n && old_n == new_n)
			return; // nothing changed

		var fresh = new GenericArray<Media> (new_n);
		for (int i = 0; i < new_n; i++)
			fresh.add (table.get (i));
		rows = fresh;
		items_changed (same_start, old_n - same_start - same_end, new_n - same_start - same_end);
	}
}
