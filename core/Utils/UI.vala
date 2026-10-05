// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*
 * Copyright (c) 2012 BeatBox Developers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this program; see the file COPYING.  If not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Authored by: Victor Eduardo <victoreduardm@gmail.com>
 * 
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 */

namespace BeatBox.UI {

    /**
     * Sets the alignment of a widget by modifying the margin and align properties.
     */
    public Gtk.Widget wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
        widget.valign = Gtk.Align.FILL;
        widget.halign = Gtk.Align.FILL;

        widget.margin_top = top;
        widget.margin_end = right;
        widget.margin_bottom = bottom;
        widget.margin_start = left;

        return widget;
    }

    /**
     * A menu in a popover pointing at x, y of relative_to; actions (if any) answer
     * its "view.*" items. It goes away once closed.
     */
    public Gtk.Popover popup_menu_model (Gtk.Widget relative_to, GLib.MenuModel model, double x, double y, GLib.ActionGroup? actions = null) {
        var popover = new Gtk.Popover.from_model (relative_to, model);
        popover.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
        popover.position = Gtk.PositionType.BOTTOM;
        if (actions != null)
            popover.insert_action_group ("view", actions);
        popover.closed.connect (() => Idle.add (() => { popover.destroy (); return false; }));
        popover.popup ();
        return popover;
    }

    /**
     * Makes a Gtk.Window draggable. The move starts once the pointer moves: a
     * click stays a click (a window manager's move would swallow a double click).
     */
    public void make_window_draggable (Gtk.Window window) {
        var drag = new Gtk.GestureDrag (window);
        drag.button = 0;
        double start_x = 0, start_y = 0;
        drag.drag_begin.connect (() => Gtk.get_current_event ().get_root_coords (out start_x, out start_y));
        drag.drag_update.connect ((dx, dy) => {
            if (!Gtk.drag_check_threshold (window, 0, 0, (int) dx, (int) dy))
                return;
            window.begin_move_drag ((int) drag.get_current_button (), (int) start_x, (int) start_y, Gtk.get_current_event_time ());
            drag.reset ();
        });
        window.set_data ("move-gesture", drag); // GTK3 controllers need a reference
    }

    /**
     * elementaryOS fonts
     */

    public enum TextStyle {
        TITLE,
        H1,
        H2,
        H3
    }

    const string H1_STYLESHEET    = ".h1 { font: bold 24px \"Open Sans\";  }";
    const string H2_STYLESHEET    = ".h2 { font: 300 18px \"Open Sans\"; }";
    const string H3_STYLESHEET    = ".h3 { font: bold 12px \"Open Sans\";  }";
    const string TITLE_STYLESHEET = ".title { font: 36px Raleway; }";

    public void apply_style_to_label (Gtk.Label label, TextStyle text_style) {
        var style_provider = new Gtk.CssProvider ();
        var style_context = label.get_style_context ();

        try {
            switch (text_style) {
                case TextStyle.TITLE:
                    style_provider.load_from_data (TITLE_STYLESHEET, -1);
                    style_context.add_class ("title");
                    break;
                case TextStyle.H1:
                    style_provider.load_from_data (H1_STYLESHEET, -1);
                    style_context.add_class ("h1");
                    break;
                case TextStyle.H2:
                    style_provider.load_from_data (H2_STYLESHEET, -1);
                    style_context.add_class ("h2");
                    break;
                case TextStyle.H3:
                    style_provider.load_from_data (H3_STYLESHEET, -1);
                    style_context.add_class ("h3");
                    break;
            }
        }
        catch (Error err) {
            warning ("Couldn't apply style to label: %s", err.message);
            return;
        }

        style_context.add_provider (style_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
    
    public Gtk.MenuItem create_suggestion_menu_item(string primary, string? secondary, Gdk.Pixbuf? pixbuf) {
		Gtk.MenuItem item;
		string markup = "<span weight='medium' size='10500'>" + validate_markup(primary, 20) + "</span>" + 
													(!String.is_empty(secondary) ? ("\n<span foreground=\"#999\">" + validate_markup(secondary, 20) + "</span>") : "");
		
		// GTK menu items have no image of their own any more: a box with both
		item = new Gtk.MenuItem();
		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		if(pixbuf != null)
			box.add(new Gtk.Image.from_pixbuf(pixbuf.scale_simple(32, 32, Gdk.InterpType.BILINEAR)));
		var label = new Gtk.Label("");
		label.set_markup(markup);
		label.xalign = 0;
		box.add(label);
		item.add(box);
		
		return item;
	}
	
	public string validate_markup(string s, int max_length) {
		return Markup.escape_text(String.ellipsize(s, max_length + 2));
	}
}

