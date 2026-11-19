//
//  Copyright (C) 2012 Mario Guerriero <mefrio.g@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Gtk;
using Gdk;

public class BeatBox.NavigationArrows : Gtk.Box {

	public signal void previous_clicked ();
	public signal void next_clicked ();

	// Style properties. Please note that style class names are for internal
	// use only. Theme developers should use GraniteWidgetsNavigationArrows instead.
	
	private Gtk.Button previous_button;
	private Gtk.Button next_button;
	
	private const string STYLESHEET = """
		.GraniteNavigationArrows .button {
			border-radius: 0 0 0 0;
			border-style: solid;
			border-width: 1px 0 1px 1px;

		}

		.GraniteNavigationArrows .button:active,
		.GraniteNavigationArrows .button:disabled {
		}

		.GraniteNavigationArrows .button:first-child {
			border-radius: 3px 0 0 3px;
			border-width: 1px 0 1px 1px;

		}

		.GraniteNavigationArrows .button:last-child {
			border-radius: 0 3px 3px 0;
			border-width: 1px;

		}
	""";

	public NavigationArrows () {

		UI.add_css (STYLESHEET); // its rules only match under .GraniteNavigationArrows
		add_css_class ("GraniteNavigationArrows");

		homogeneous = true;
		spacing = 0;

		can_focus = true;
		
		previous_button = new NavigationArrow ();
		var previous_image = new Image.from_icon_name ("go-previous-symbolic");
		previous_button.child = previous_image;
		
		previous_button.clicked.connect (() => {
			previous_clicked ();
		});
		
		next_button = new NavigationArrow ();
		var next_image = new Image.from_icon_name ("go-next-symbolic");
		next_button.child = next_image;
		
		next_button.clicked.connect (() => {
			next_clicked ();
		});
		
		append (previous_button);
		append (next_button);
	}

	public void set_item_visible (int index, bool val) {
		var item = UI.children (this).nth_data (index);
		if (item == null)
			return;

		item.set_visible (val);
	}

}

private class BeatBox.NavigationArrow : Gtk.Button {
	public NavigationArrow () {
		focusable = false;

		add_css_class("raised");
	}
}

