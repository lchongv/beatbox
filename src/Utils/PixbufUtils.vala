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
 * Authored by: Lucas Baudin <xapantu@gmail.com>
 *              Victor Eduardo <victoreduardm@gmail.com>
 * 
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 */

namespace BeatBox.PixbufUtils {

    /**
     * @param pixbuf original image
     * @param stretch whether to strech the image inside the square or keep the original dimensions
     * @return original pixbuf + drop shadow
     **/
    public Gdk.Pixbuf? get_pixbuf_shadow (Gdk.Pixbuf pixbuf, int surface_size = Icons.ALBUM_VIEW_IMAGE_SIZE,
                                          bool stretch = true)
    {
        if (pixbuf == null)
            return null;

        // iTunes-style cover: rounded corners, thin dark frame, soft drop shadow
        const int SHADOW_SIZE = 6;
        const double RADIUS = 4;

        int S_WIDTH = (stretch)? surface_size: pixbuf.width;
        int S_HEIGHT = (stretch)? surface_size : pixbuf.height;

        var buffer_surface = new Granite.Drawing.BufferSurface (S_WIDTH, S_HEIGHT);
        var cr = buffer_surface.context;

        int width = S_WIDTH - 2 * SHADOW_SIZE;
        int height = S_HEIGHT - 2 * SHADOW_SIZE;

        Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, SHADOW_SIZE, SHADOW_SIZE + 2, width, height, RADIUS);
        cr.set_source_rgba (0, 0, 0, 0.45);
        cr.fill ();
        buffer_surface.fast_blur (2, 3);

        var source_pixbuf = pixbuf;
        if (pixbuf.width != width || pixbuf.height != height)
            source_pixbuf = pixbuf.scale_simple (width, height, Gdk.InterpType.BILINEAR);

        cr.save ();
        Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, SHADOW_SIZE, SHADOW_SIZE, width, height, RADIUS);
        cr.clip ();
        Gdk.cairo_set_source_pixbuf (cr, source_pixbuf, SHADOW_SIZE, SHADOW_SIZE);
        cr.paint ();
        cr.restore ();

        Granite.Drawing.Utilities.cairo_rounded_rectangle (cr, SHADOW_SIZE + 0.5, SHADOW_SIZE + 0.5, width - 1, height - 1, RADIUS);
        cr.set_source_rgb (0.416, 0.416, 0.416); // #6a6a6a
        cr.set_line_width (1);
        cr.stroke ();

        return buffer_surface.load_to_pixbuf();
    }

    /**
     * @param surface_size size of the new pixbuf. Set a value of 0 to use the pixbuf's default size.
     **/
    public Gdk.Pixbuf? render_pixbuf_shadow (Gdk.Pixbuf pixbuf, int surface_size = BeatBox.Icons.ALBUM_VIEW_IMAGE_SIZE,
                                             int shadow_size = 5, double alpha = 0.75)
    {
        if (pixbuf == null)
            return null;

        int S_WIDTH = (surface_size > 0)? surface_size : pixbuf.width;
        int S_HEIGHT = (surface_size > 0)? surface_size : pixbuf.height;

        var buffer_surface = new Granite.Drawing.BufferSurface (S_WIDTH, S_HEIGHT);

        S_WIDTH -= 2 * shadow_size;
        S_HEIGHT -= 2 * shadow_size;

        buffer_surface.context.rectangle (shadow_size, shadow_size, S_WIDTH, S_HEIGHT);
        buffer_surface.context.set_source_rgba (0, 0, 0, alpha);
        buffer_surface.context.fill();

        buffer_surface.fast_blur(2, 3);

        Gdk.cairo_set_source_pixbuf (buffer_surface.context, pixbuf.scale_simple (S_WIDTH, S_HEIGHT,
                                     Gdk.InterpType.BILINEAR), shadow_size, shadow_size);
        buffer_surface.context.paint();

        return buffer_surface.load_to_pixbuf();
    }

}
