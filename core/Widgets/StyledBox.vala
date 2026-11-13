/*-
 * Copyright (c) 2012       Scott Ringwelski <sgringwe@mtu.edu>
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

public class BeatBox.StyledBox : Gtk.Box {
	CssProvider style_provider;
	string class_style;
	
	private const string WIDGET_STYLESHEET = """
        .borderButton{
			
			background-image: linear-gradient(to bottom, shade(#d5d3d1, 1.05), #d5d3d1);
			

        }
        
        .StyledBox .top {
			border-radius: 6px 6px 0 0;
		}
		
		.StyledBox .right {
			border-radius: 0 0 0 0;
		}
		
		.StyledBox .bottom {
			border-radius: 0 0 6px 6px;
		}
		
		.StyledBox .left {
			border-radius: 0 0 0 0;
		}
        
        .gray {
			background-image: linear-gradient(to bottom, shade(#d5d3d1, 1.05), #d5d3d1);
		}
		
		.black {
			background-image: linear-gradient(to bottom, shade(#383838, 1.05), #383838);
		}
		
		.white {
			background-image: linear-gradient(to bottom, shade(#f8f8f8, 1.05), #f8f8f8);
		}
		
		.pure_white {
			background-color: #fff;
			background-image: none;
		}
		
		.transparent {
			background-image: none;
			background-color: rgba(0,0,0,0);
		}
		
    """;
    
    Gtk.Box inner;
	Gtk.Label title_label;
	Gtk.Box center;
	Gtk.Box content;
	
	public StyledBox(string title, string class_style) {
		this.class_style = class_style;
		title_label = new Gtk.Label("");
		content = new Box(Orientation.VERTICAL, 0);
		
		style_provider = new CssProvider();
        style_provider.load_from_data (WIDGET_STYLESHEET.data);
        
		get_style_context().add_class("StyledBox");
		get_style_context().add_class(class_style);
		get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		homogeneous = false;
		
		inner = new Box(Orientation.HORIZONTAL, 0);
		var top = new Button();
		var right = new Button();
		var bottom = new Button();
		var left = new Button();
		
		center = new Box(Orientation.VERTICAL, 0);
		if(class_style != "white") {
			center.get_style_context().add_class(class_style);
			center.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		}
		center.append(content);
		
		if(title != "") {
			Box title_box = new Box(Orientation.VERTICAL, 0);
			title_box.get_style_context().add_class("pure_" + class_style);
			title_box.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
			title_box.append(title_label);
			title_label.set_markup("<b>" + Markup.escape_text(title) + "</b>");
			content.append(title_box);
		}
		
		inner.append(left);
		center.hexpand = true;
		inner.append(center);
		inner.append(right);
		
		this.set_orientation(Orientation.VERTICAL);
		append(top);
		inner.vexpand = true;
		append(inner);
		append(bottom);
		hexpand = vexpand = false; // its parts fill it; it doesn't ask its parent for more room
		
		top.get_style_context().add_class("top");
		right.get_style_context().add_class("right");
		bottom.get_style_context().add_class("bottom");
		left.get_style_context().add_class("left");
		top.get_style_context().add_class("borderButton");
		right.get_style_context().add_class("borderButton");
		bottom.get_style_context().add_class("borderButton");
		left.get_style_context().add_class("borderButton");
		top.get_style_context().add_class(class_style);
		right.get_style_context().add_class(class_style);
		bottom.get_style_context().add_class(class_style);
		left.get_style_context().add_class(class_style);
		top.get_style_context().remove_class("button");
		right.get_style_context().remove_class("button");
		bottom.get_style_context().remove_class("button");
		left.get_style_context().remove_class("button");
		
		top.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		right.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		bottom.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		left.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
	}
	
	private string _title;
	public string title {
		get {
			return _title;
		}
		set {
			_title = value;
			
		}
	}
	
	public void set_widget(Widget w) {
		w.vexpand = true;
		content.append(w);
		w.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		
		// Turn off scrolling on w: the controller takes the wheel before w sees it
		if(w is ScrolledWindow) {
			var no_scroll = new EventControllerScroll(EventControllerScrollFlags.BOTH_AXES);
			no_scroll.propagation_phase = PropagationPhase.CAPTURE;
			w.add_controller(no_scroll);
		}
	}
}

