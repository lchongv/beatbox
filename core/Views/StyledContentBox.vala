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

using Gtk;
using Gee;

public class BeatBox.StyledContentBox : Box {
	private const string WIDGET_STYLESHEET = """
        .NowPlayingPage {
			background-image: linear-gradient(to bottom, shade(#ffffff, 1.05), #ffffff);
            border: 0;
        }
        
        .AlbumSongList {
			/*background-color: rgba(0, 0, 0, 0);*/
			padding: 0;
			/*box-shadow: 10px 10px rgba(0, 0, 0, 0.4);*/
		}
		
		.AlbumSongList row:selected {
			/*background-image: linear-gradient(to bottom, shade(@selected_bg_color, 1.20), shade(@selected_bg_color, 0.98));*/
		}
		
		.gray {
			background-image: linear-gradient(to bottom, shade(#d5d3d1, 1.00), shade(#d5d3d1, 0.95));
		}
		
		.black {
			background-image: linear-gradient(to bottom, shade(#383838, 1.05), #383838);
		}
		.padding {
			padding: 6px;
		}
		
		.white {
			background-image: linear-gradient(to bottom, shade(#f8f8f8, 1.05), #f8f8f8);
		}
		
		.pure_white {
			background-color: #fff;
			background-image: none;
		}
		
		.white_text {
			color: shade(#f0f0f0, 1.01);
			text-shadow: 1px 1px 0 alpha(#f8f8f8, 0.3);
		}
		""";
	
	Box ebox;
	// GTK 4 does not let a class derive from ScrolledWindow: this is the scrolling part, inside the box
	protected ScrolledWindow scroll;
	
	public StyledContentBox() {
		Object (orientation: Orientation.VERTICAL, spacing: 0);
		ebox = new Box(Orientation.VERTICAL, 0);
		Viewport vp = new Viewport(null, null);
		
		// Apply styling
		UI.add_scoped_css("bb-styledcontent", WIDGET_STYLESHEET);
		
		scroll = new ScrolledWindow ();
		scroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		scroll.hexpand = scroll.vexpand = true;
		
		vp.add_css_class("NowPlayingPage");
		vp.add_css_class("bb-styledcontent");
        ebox.add_css_class("NowPlayingPage");
		ebox.add_css_class("bb-styledcontent");
		
		vp.set_child(ebox);
		scroll.set_child(vp);
		append(scroll);
	}
	
	public void set_content(Widget w) {
		ebox.append(w);
	}
}
