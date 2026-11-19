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

    /* ---- Stylesheets and named colors ----
     * GTK 4.10 deprecated Gtk.StyleContext as a whole: what BeatBox used of it lives here.
     * The display-wide provider functions themselves are not deprecated in C. */

    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);
    [CCode (cname = "gtk_style_context_remove_provider_for_display")]
    extern void remove_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider);

    /** Applies a stylesheet to every window (higher priorities win) */
    public void add_css_provider (Gtk.StyleProvider provider, uint priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION) {
        add_provider_for_display (Gdk.Display.get_default (), provider, priority);
    }

    public void remove_css_provider (Gtk.StyleProvider provider) {
        remove_provider_for_display (Gdk.Display.get_default (), provider);
    }

    /** CSS for the whole display, loaded once per text: a widget's own rules go under a class of
     *  its own (GTK 4 has no stylesheets per widget any more) */
    public void add_css (string css, uint priority = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION) {
        if (added_css == null)
            added_css = new GenericSet<string> (str_hash, str_equal);
        if (css in added_css)
            return;
        added_css.add (css);
        var provider = new Gtk.CssProvider ();
        provider.load_from_string (css);
        add_css_provider (provider, priority);
    }
    GenericSet<string>? added_css = null;

    /** Rules that GTK 3 gave single widgets (StyleContext.add_provider): each selector also
     *  requires the scope class, which those widgets get with add_css_class (scope) */
    public void add_scoped_css (string scope, string css) {
        try {
            var selectors = new Regex ("(^|\\})([^{}]*)\\{");
            string scoped = selectors.replace_eval (css, -1, 0, 0, (info, result) => {
                result.append (info.fetch (1));
                string[] parts = info.fetch (2).split (",");
                for (int i = 0; i < parts.length; i++) {
                    if (i > 0)
                        result.append (",");
                    result.append ("\n%s.%s ".printf (parts[i].strip (), scope));
                }
                result.append ("{");
                return false;
            });
            add_css (scoped);
        } catch (RegexError err) {
            warning ("Could not scope a stylesheet to .%s: %s", scope, err.message);
        }
    }

    /* The colors skins name with @define-color. A probe label per name, styled "color: @name",
     * reads one; the base palette below makes sure every name BeatBox reads is defined (the
     * Adwaita skins skip the Classic look that defines most of them). */
    const string BASE_PALETTE =
        "@define-color bb_accent @theme_selected_bg_color;" +
        "@define-color bb_row_a #ffffff;" +
        "@define-color bb_row_b #dde8f5;" +
        "@define-color bb_detail_bg #ffffff;" +
        "@define-color bb_detail_border #bdbdbd;" +
        "@define-color bb_sidebar_heading #4a586d;" +
        // GTK's own themes define these; the fallbacks are for a theme that doesn't
        "@define-color theme_selected_bg_color #3d6dca;" +
        "@define-color theme_selected_fg_color #ffffff;";
    Gtk.CssProvider? probe_rules = null;
    GenericSet<string>? probed_names = null;
    HashTable<string, Gdk.RGBA?>? named_cache = null;

    /** A named color (bb_accent, bb_row_a, theme_selected_fg_color...) as the skin defines it */
    public Gdk.RGBA named_color (string name) {
        if (probe_rules == null) {
            var base_palette = new Gtk.CssProvider ();
            base_palette.load_from_string (BASE_PALETTE);
            add_css_provider (base_palette, Gtk.STYLE_PROVIDER_PRIORITY_FALLBACK);
            probe_rules = new Gtk.CssProvider ();
            add_css_provider (probe_rules, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 10);
            probed_names = new GenericSet<string> (str_hash, str_equal);
            named_cache = new HashTable<string, Gdk.RGBA?> (str_hash, str_equal);
        }
        var cached = named_cache.get (name);
        if (cached != null)
            return cached;
        if (!(name in probed_names)) {
            probed_names.add (name);
            var rules = new StringBuilder ();
            foreach (var n in probed_names.get_values ())
                rules.append (".bb-probe-%s { color: @%s; }\n".printf (n, n));
            probe_rules.load_from_string (rules.str);
        }
        var probe = new Gtk.Label (null); // a new one: an unshown widget keeps its first style
        probe.add_css_class ("bb-probe-" + name);
        Gdk.RGBA color = probe.get_color ();
        named_cache.insert (name, color);
        return color;
    }

    /** After a skin or the theme changed: named colors are read again */
    public void named_colors_changed () {
        if (named_cache != null)
            named_cache.remove_all ();
    }

    /**
     * Sets the alignment of a widget by modifying the margin and align properties.
     */
    public Gtk.Widget wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
        // alignment is left as set: the button boxes of the preferences ask for END
        // (GTK3's ButtonBox did it inside a filling Gtk.Alignment)
        widget.margin_top = top;
        widget.margin_end = right;
        widget.margin_bottom = bottom;
        widget.margin_start = left;

        return widget;
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

    /* ---- Pixbufs, cairo surfaces and textures ----
     * GTK 4.12-4.20 deprecated its GdkPixbuf helpers (cairo_set_source_pixbuf, pixbuf_get_from_surface,
     * Texture.for_pixbuf...): BeatBox still loads and scales with GdkPixbuf, and converts here. */

    /** The pixbuf as a cairo surface, made once and kept on the pixbuf (a cover is drawn every frame) */
    public Cairo.ImageSurface pixbuf_surface (Gdk.Pixbuf pix) {
        unowned Cairo.ImageSurface? kept = pix.get_data<Cairo.ImageSurface> ("bb-surface");
        if (kept != null)
            return kept;
        int w = pix.width, h = pix.height, channels = pix.n_channels, in_stride = pix.rowstride;
        bool alpha = pix.has_alpha;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
        surface.flush ();
        unowned uint8[] src = pix.get_pixels_with_length ();
        uint8* dst = surface.get_data ();
        int out_stride = surface.get_stride ();
        for (int y = 0; y < h; y++) {
            uint8* row = dst + y * out_stride;
            int in_row = y * in_stride;
            for (int x = 0; x < w; x++) {
                int i = in_row + x * channels;
                uint a = alpha ? src[i + 3] : 255;
                // cairo: premultiplied, a native-endian 32-bit word (0xAARRGGBB)
                uint32 word = (a << 24) | ((src[i] * a / 255) << 16) | ((src[i + 1] * a / 255) << 8) | (src[i + 2] * a / 255);
                ((uint32*) row)[x] = word;
            }
        }
        surface.mark_dirty ();
        pix.set_data<Cairo.ImageSurface> ("bb-surface", surface);
        return surface;
    }

    /** After drawing into a pixbuf's pixels: the surface kept for it is out of date */
    public void pixbuf_changed (Gdk.Pixbuf pix) {
        pix.set_data<Cairo.ImageSurface?> ("bb-surface", null);
    }

    /** Draws the pixbuf with its top left corner at x, y (what Gdk.cairo_set_source_pixbuf did) */
    public void set_source_pixbuf (Cairo.Context cr, Gdk.Pixbuf pix, double x, double y) {
        cr.set_source_surface (pixbuf_surface (pix), x, y);
    }

    /** A cairo surface (ARGB32 or RGB24) as a pixbuf with alpha */
    public Gdk.Pixbuf pixbuf_from_surface (Cairo.ImageSurface surface) {
        surface.flush ();
        int w = surface.get_width (), h = surface.get_height (), in_stride = surface.get_stride ();
        bool has_alpha = surface.get_format () == Cairo.Format.ARGB32;
        var pix = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, w, h);
        unowned uint8[] dst = pix.get_pixels_with_length ();
        int out_stride = pix.rowstride;
        uint8* src = surface.get_data ();
        for (int y = 0; y < h; y++) {
            uint32* row = (uint32*) (src + y * in_stride);
            for (int x = 0; x < w; x++) {
                uint32 word = row[x];
                uint a = has_alpha ? (word >> 24) & 0xff : 255;
                int o = y * out_stride + x * 4;
                if (a == 0) {
                    dst[o] = dst[o + 1] = dst[o + 2] = dst[o + 3] = 0;
                    continue;
                }
                dst[o] = (uint8) ((((word >> 16) & 0xff) * 255 + a / 2) / a); // undo the premultiplication
                dst[o + 1] = (uint8) ((((word >> 8) & 0xff) * 255 + a / 2) / a);
                dst[o + 2] = (uint8) (((word & 0xff) * 255 + a / 2) / a);
                dst[o + 3] = (uint8) a;
            }
        }
        return pix;
    }

    /** The pixbuf as a texture, for images and pictures */
    public Gdk.Texture texture_from_pixbuf (Gdk.Pixbuf pix) {
        return new Gdk.MemoryTexture (pix.width, pix.height,
                                      pix.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8,
                                      pix.read_pixel_bytes (), pix.rowstride);
    }

    /** A texture's pixels as a pixbuf with alpha */
    public Gdk.Pixbuf pixbuf_from_texture (Gdk.Texture texture) {
        var downloader = new Gdk.TextureDownloader (texture);
        downloader.set_format (Gdk.MemoryFormat.R8G8B8A8);
        size_t stride;
        var bytes = downloader.download_bytes (out stride);
        return new Gdk.Pixbuf.from_bytes (bytes, Gdk.Colorspace.RGB, true, 8, texture.width, texture.height, (int) stride);
    }

    /** Lets a file chooser filter take every picture format GdkPixbuf reads */
    public void add_picture_formats (Gtk.FileFilter filter) {
        foreach (var format in Gdk.Pixbuf.get_formats ())
            foreach (var mime in format.get_mime_types ())
                filter.add_mime_type (mime);
    }

    /**
     * Shows a pixbuf at its real size. GTK4 draws an image at icon size (16 px)
     * unless pixel_size says otherwise.
     */
    public void show_pixbuf (Gtk.Image image, Gdk.Pixbuf? pixbuf) {
        image.set_from_paintable (pixbuf != null ? texture_from_pixbuf (pixbuf) : null);
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
    /** Where a popover can hang for the point x, y of widget: set as a child of a TreeView or
     * an IconView it breaks their CSS nodes (gtk_css_node_insert_after critical, the header nodes
     * are kept apart), so their parent holds it instead, at the same point */
    public Gtk.Widget popover_parent (Gtk.Widget widget, ref double x, ref double y) {
        var parent = widget.get_parent ();
        if (!(widget is Gtk.TreeView || widget is Gtk.IconView) || parent == null)
            return widget;
        Graphene.Point p;
        if (widget.compute_point (parent, Graphene.Point () { x = (float) x, y = (float) y }, out p)) {
            x = p.x;
            y = p.y;
        }
        return parent;
    }

    public Gtk.Popover popup_menu_model (Gtk.Widget relative_to, GLib.MenuModel model, double x, double y, GLib.ActionGroup? actions = null) {
        var popover = new Gtk.PopoverMenu.from_model (model);
        popover.set_parent (popover_parent (relative_to, ref x, ref y));
        popover.pointing_to = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
        popover.position = Gtk.PositionType.BOTTOM;
        if (actions != null)
            popover.insert_action_group ("view", actions);
        popover.closed.connect (() => Idle.add (() => { popover.unparent (); return false; }));
        popover.popup ();
        return popover;
    }

    /** The pixbuf's shape in one color: what GTK3 did to a symbolic icon (GTK4 only recolors paintables) */
    public Gdk.Pixbuf? tint (Gdk.Pixbuf pix, Gdk.RGBA color) {
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pix.width, pix.height);
        var cr = new Cairo.Context (surface);
        set_source_pixbuf (cr, pix, 0, 0);
        var shape = cr.get_source ();
        Gdk.cairo_set_source_rgba (cr, color);
        cr.mask (shape);
        return pixbuf_from_surface (surface);
    }

    /** GTK3's tree view made every row this much taller than its cells (GTK 4 adds nothing) */
    public const int GTK3_ROW_EXTRA = 3;

    static Gtk.CssProvider? full_size_css = null;

    /** GTK 4 draws a CellRendererPixbuf's pixbuf no bigger than the CSS icon size (16 px): covers
     * and rating stars came out tiny. This cell asks for the "large" size, which GTK marks on the
     * view's node while drawing it, and that size is lifted for tree and icon views. */
    public Gtk.CellRendererPixbuf full_size (Gtk.CellRendererPixbuf cell) {
        if (full_size_css == null) {
            full_size_css = new Gtk.CssProvider ();
            full_size_css.load_from_string ("treeview.large-icons, iconview.large-icons { -gtk-icon-size: 512px; }");
            UI.add_css_provider (full_size_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        cell.icon_size = Gtk.IconSize.LARGE;
        return cell;
    }

    /** Redraws widget and everything in it: GTK3's queue_draw did, GTK4's keeps the children's last drawing */
    public void queue_draw_all (Gtk.Widget widget) {
        widget.queue_draw ();
        for (var child = widget.get_first_child (); child != null; child = child.get_next_sibling ())
            queue_draw_all (child);
    }

    /**
     * Makes a Gtk.Window draggable by its content: the content goes into a Gtk.WindowHandle,
     * since GTK4 cannot start a move from a gesture. Call it once the window has its child.
     */
    public void make_window_draggable (Gtk.Window window) {
        // A Gtk.WindowHandle also maximizes on a double click, but GTK only allows that on windows
        // without a transient parent: both users (LcdCover, PopupListView) have one. LcdCover's own
        // double click (close) runs in the capture phase, before the handle claims it.
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

    const string H1_STYLESHEET    = ".bb-h1 { font: bold 24px \"Open Sans\";  }";
    const string H2_STYLESHEET    = ".bb-h2 { font: 300 18px \"Open Sans\"; }";
    const string H3_STYLESHEET    = ".bb-h3 { font: bold 12px \"Open Sans\";  }";
    const string TITLE_STYLESHEET = ".bb-title { font: 36px Raleway; }";

    public void apply_style_to_label (Gtk.Label label, TextStyle text_style) {
        switch (text_style) {
            case TextStyle.TITLE:
                add_css (TITLE_STYLESHEET);
                label.add_css_class ("bb-title");
                break;
            case TextStyle.H1:
                add_css (H1_STYLESHEET);
                label.add_css_class ("bb-h1");
                break;
            case TextStyle.H2:
                add_css (H2_STYLESHEET);
                label.add_css_class ("bb-h2");
                break;
            case TextStyle.H3:
                add_css (H3_STYLESHEET);
                label.add_css_class ("bb-h3");
                break;
        }
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
    public BeatBox.MessageBar experimental_bar(string text) {
        var bar = new BeatBox.MessageBar(Gtk.MessageType.WARNING);
        var label = new Gtk.Label(null);
        label.set_markup("<b>%s</b> %s".printf(Markup.escape_text(_("Experimental:")), Markup.escape_text(text)));
        label.wrap = true;
        label.xalign = 0;
        bar.add_child(label);
        return bar;
    }
}
