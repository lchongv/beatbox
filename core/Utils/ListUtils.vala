/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

namespace BeatBox.ListUtils {
	/**
	 * Moves items to position index of list, keeping their order. index counts
	 * positions in the list as it is now; items not in the list are inserted.
	 */
	public void move_to<G> (Gee.List<G> list, Gee.Collection<G> items, int index) {
		var moving = new Gee.ArrayList<G> ();
		foreach (var item in items) {
			if (moving.contains (item))
				continue;
			moving.add (item);
			int i = list.index_of (item);
			if (i >= 0) {
				if (i < index)
					index--;
				list.remove_at (i);
			}
		}
		index = index.clamp (0, list.size);
		foreach (var item in moving)
			list.insert (index++, item);
	}
}
