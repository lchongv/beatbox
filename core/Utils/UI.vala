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

[GIR (visible = false)] // internal: plugins don't see it
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
     * Runs a dialog without blocking: returns its response once the user answers.
     * Replaces Gtk.Dialog.run (), which GTK4 does not have.
     */
    public async int run_dialog (Gtk.Dialog dialog) {
        int result = Gtk.ResponseType.NONE;
        dialog.modal = true;
        ulong id = dialog.response.connect ((r) => { result = r; run_dialog.callback (); });
        dialog.present ();
        yield;
        dialog.disconnect (id);
        return result;
    }

    /** The children of a widget, in order. Replaces get_children (). */
    public GLib.List<unowned Gtk.Widget> children (Gtk.Widget parent) {
        var list = new GLib.List<unowned Gtk.Widget> ();
        for (unowned Gtk.Widget? child = parent.get_first_child (); child != null; child = child.get_next_sibling ())
            list.append (child);
        return list;
    }

    /** Removes every child of a container. */
    public void clear (Gtk.Widget parent) {
        foreach (var child in children (parent)) {
            if (parent is Gtk.Box)
                ((Gtk.Box) parent).remove (child);
            else if (parent is Gtk.ListBox)
                ((Gtk.ListBox) parent).remove (child);
            else if (parent is Gtk.FlowBox)
                ((Gtk.FlowBox) parent).remove (child);
            else
                child.unparent ();
        }
    }

    /**
     * Shows a pixbuf at its real size. GTK4 draws an image at icon size (16 px)
     * unless pixel_size says otherwise.
     */
    public void show_pixbuf (Gtk.Image image, Gdk.Pixbuf? pixbuf) {
        image.set_from_pixbuf (pixbuf);
        image.pixel_size = pixbuf != null ? int.max (pixbuf.width, pixbuf.height) : -1;
    }

    /** The window a widget is in, or null. Replaces get_toplevel (). */
    public Gtk.Window? window_of (Gtk.Widget widget) {
        return widget.get_root () as Gtk.Window;
    }

    /**
     * A menu in a popover pointing at x, y of relative_to; actions (if any) answer
     * its "view.*" items. It goes away once closed.
     */
    public Gtk.Popover popup_menu_model (Gtk.Widget relative_to, GLib.MenuModel model, double x, double y, GLib.ActionGroup? actions = null) {
        var popover = new Gtk.PopoverMenu.from_model (model);
        popover.set_parent (relative_to);
        popover.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
        popover.position = Gtk.PositionType.BOTTOM;
        if (actions != null)
            popover.insert_action_group ("view", actions);
        popover.closed.connect (() => Idle.add (() => { popover.unparent (); return false; }));
        popover.popup ();
        return popover;
    }

    /**
     * Makes a Gtk.Window draggable by its content: the content goes into a Gtk.WindowHandle,
     * since GTK4 cannot start a move from a gesture. Call it once the window has its child.
     */
    public void make_window_draggable (Gtk.Window window) {
        // GTK4-PENDIENTE: a Gtk.WindowHandle also toggles maximized on a double click; GTK3 avoided that
        // (the move started only after the pointer moved). Revisar LcdCover y PopupListView.
        var child = window.get_child ();
        var handle = new Gtk.WindowHandle ();
        window.set_child (null);
        if (child != null)
            handle.set_child (child);
        window.set_child (handle);
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

        switch (text_style) {
            case TextStyle.TITLE:
                style_provider.load_from_data (TITLE_STYLESHEET.data);
                label.add_css_class ("title");
                break;
            case TextStyle.H1:
                style_provider.load_from_data (H1_STYLESHEET.data);
                label.add_css_class ("h1");
                break;
            case TextStyle.H2:
                style_provider.load_from_data (H2_STYLESHEET.data);
                label.add_css_class ("h2");
                break;
            case TextStyle.H3:
                style_provider.load_from_data (H3_STYLESHEET.data);
                label.add_css_class ("h3");
                break;
        }

        style_context.add_provider (style_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    public BeatBox.PopMenuItem create_suggestion_menu_item (string primary, string? secondary, Gdk.Pixbuf? pixbuf) {
        string markup = "<span weight='medium' size='10500'>" + validate_markup (primary, 20) + "</span>" +
                        (!String.is_empty (secondary) ? ("\n<span foreground=\"#999\">" + validate_markup (secondary, 20) + "</span>") : "");

        // menu items have no image of their own: a box with both
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        if (pixbuf != null) {
            var image = new Gtk.Image ();
            show_pixbuf (image, pixbuf.scale_simple (32, 32, Gdk.InterpType.BILINEAR));
            box.append (image);
        }
        var label = new Gtk.Label ("");
        label.set_markup (markup);
        label.xalign = 0;
        box.append (label);

        return new BeatBox.PopMenuItem.with_child (box);
    }

    public string validate_markup(string s, int max_length) {
        return Markup.escape_text(String.ellipsize(s, max_length + 2));
    }

    /** The warning on top of features nobody could test on today's systems (iPod, CD) */
    public Gtk.InfoBar experimental_bar(string text) {
        var bar = new Gtk.InfoBar();
        bar.message_type = Gtk.MessageType.WARNING;
        var label = new Gtk.Label(null);
        label.set_markup("<b>%s</b> %s".printf(Markup.escape_text(_("Experimental:")), Markup.escape_text(text)));
        label.wrap = true;
        label.xalign = 0;
        bar.add_child(label);
        return bar;
    }
}
