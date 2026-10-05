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

using Gtk;
using Gdk;
using Gee;

public class BeatBox.SimpleOptionChooser : EventBox {
	GLib.Menu menu = new GLib.Menu(); // right click: one radio item per option
	SimpleAction option = new SimpleAction.stateful("option", VariantType.INT32, new Variant.int32(0));
	Gtk.Popover? popover = null;
	Gtk.GestureMultiPress press_gesture; // GTK3 controllers need a reference
	public LinkedList<Gtk.Image> images;

	int clicked_index;
	int previous_index; // for left click

	public signal void option_changed(int index);

	public SimpleOptionChooser () {
		images = new LinkedList<Gtk.Image>();

		clicked_index = 0;
		previous_index = 0;

		// make the event box transparent
		set_above_child(true);
		set_visible_window(false);

		option.activate.connect((index) => {
			if(index.get_int32() != clicked_index)
				setOption(index.get_int32());
			popover.popdown(); // GTK3 leaves popovers open after a radio item; one choice is all there is
		});
		var actions = new SimpleActionGroup();
		actions.add_action(option);
		insert_action_group("chooser", actions);

		press_gesture = new Gtk.GestureMultiPress(this);
		press_gesture.button = 0;
		press_gesture.pressed.connect(buttonPress);
	}

	public void setOption(int index) {
		if(index >= images.size)
			return;

		option.set_state(new Variant.int32(index));

		clicked_index = index;
		option_changed(index);

		if (get_child () != null)
			remove (get_child ());

		add (images.get(index));

		show_all ();
	}

	public int append_option(string text, Gtk.Image image, string tooltip) {
		image.set_tooltip_text (tooltip);
		images.add(image);
		var item = new GLib.MenuItem(text, null);
		item.set_action_and_target_value("chooser.option", new Variant.int32(images.size - 1));
		menu.append_item(item);

		previous_index = images.size - 1; // my lazy way of making sure the bottom item is the default on/off on click

		return images.size - 1;
	}

	void buttonPress(int n_press, double x, double y) {
		uint button = press_gesture.get_current_button();
		if(button == 1) {
			if(clicked_index == 0) {
				setOption(previous_index);
			}
			else {
				previous_index = clicked_index;
				setOption(0);
			}
		}
		else if(button == 3 && images.size > 1) {
			popover = UI.popup_menu_model(this, menu, x, y);
		}
	}
}

