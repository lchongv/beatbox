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

        // cover: rounded corners, thin dark frame, soft drop shadow
        const int SHADOW_SIZE = 6;
        const double RADIUS = 4;

        int S_WIDTH = (stretch)? surface_size: pixbuf.width;
        int S_HEIGHT = (stretch)? surface_size : pixbuf.height;

        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, S_WIDTH, S_HEIGHT);
        var cr = new Cairo.Context (surface);

        int width = S_WIDTH - 2 * SHADOW_SIZE;
        int height = S_HEIGHT - 2 * SHADOW_SIZE;

        rounded_rectangle (cr, SHADOW_SIZE, SHADOW_SIZE + 2, width, height, RADIUS);
        cr.set_source_rgba (0, 0, 0, 0.45);
        cr.fill ();
        fast_blur (surface, 2, 3);

        var source_pixbuf = pixbuf;
        if (pixbuf.width != width || pixbuf.height != height)
            source_pixbuf = pixbuf.scale_simple (width, height, Gdk.InterpType.BILINEAR);

        cr.save ();
        rounded_rectangle (cr, SHADOW_SIZE, SHADOW_SIZE, width, height, RADIUS);
        cr.clip ();
        Gdk.cairo_set_source_pixbuf (cr, source_pixbuf, SHADOW_SIZE, SHADOW_SIZE);
        cr.paint ();
        cr.restore ();

        rounded_rectangle (cr, SHADOW_SIZE + 0.5, SHADOW_SIZE + 0.5, width - 1, height - 1, RADIUS);
        cr.set_source_rgb (0.416, 0.416, 0.416); // #6a6a6a
        cr.set_line_width (1);
        cr.stroke ();

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, S_WIDTH, S_HEIGHT);
    }

    void rounded_rectangle (Cairo.Context cr, double x, double y, double width, double height, double radius) {
        cr.move_to (x + radius, y);
        cr.arc (x + width - radius, y + radius, radius, Math.PI * 1.5, Math.PI * 2);
        cr.arc (x + width - radius, y + height - radius, radius, 0, Math.PI * 0.5);
        cr.arc (x + radius, y + height - radius, radius, Math.PI * 0.5, Math.PI);
        cr.arc (x + radius, y + radius, radius, Math.PI, Math.PI * 1.5);
        cr.close_path ();
    }

    /*
     * Box blur repeated `passes` times, in place (the "superfastblur" algorithm,
     * http://incubator.quasimondo.com/processing/superfastblur.pde).
     * From Granite's BufferSurface.fast_blur (granite 6.2.0, LGPL-3.0-or-later):
     * Copyright 2011-2013 Robert Dyer, Rico Tzschichholz; 2019 elementary, Inc.
     */
    void fast_blur (Cairo.ImageSurface surface, int radius, int passes) {
        var w = surface.get_width ();
        var h = surface.get_height ();
        var channels = 4;

        if (radius < 1 || passes < 1 || radius > w - 1 || radius > h - 1)
            return;

        surface.flush ();
        uint8 *pixels = surface.get_data ();
        var buffer = new uint8[w * h * channels];

        var v_min = new int[int.max (w, h)];
        var v_max = new int[int.max (w, h)];

        var div = 2 * radius + 1;
        var dv = new uint8[256 * div];

        for (var i = 0; i < dv.length; i++)
            dv[i] = (uint8) (i / div);

        while (passes-- > 0) {
            for (var x = 0; x < w; x++) {
                v_min[x] = int.min (x + radius + 1, w - 1);
                v_max[x] = int.max (x - radius, 0);
            }

            for (var y = 0; y < h; y++) {
                var a_sum = 0, r_sum = 0, g_sum = 0, b_sum = 0;

                uint32 cur_pixel = y * w * channels;

                a_sum += radius * pixels[cur_pixel + 0];
                r_sum += radius * pixels[cur_pixel + 1];
                g_sum += radius * pixels[cur_pixel + 2];
                b_sum += radius * pixels[cur_pixel + 3];

                for (var i = 0; i <= radius; i++) {
                    a_sum += pixels[cur_pixel + 0];
                    r_sum += pixels[cur_pixel + 1];
                    g_sum += pixels[cur_pixel + 2];
                    b_sum += pixels[cur_pixel + 3];

                    cur_pixel += channels;
                }

                cur_pixel = y * w * channels;

                for (var x = 0; x < w; x++) {
                    uint32 p1 = (y * w + v_min[x]) * channels;
                    uint32 p2 = (y * w + v_max[x]) * channels;

                    buffer[cur_pixel + 0] = dv[a_sum];
                    buffer[cur_pixel + 1] = dv[r_sum];
                    buffer[cur_pixel + 2] = dv[g_sum];
                    buffer[cur_pixel + 3] = dv[b_sum];

                    a_sum += pixels[p1 + 0] - pixels[p2 + 0];
                    r_sum += pixels[p1 + 1] - pixels[p2 + 1];
                    g_sum += pixels[p1 + 2] - pixels[p2 + 2];
                    b_sum += pixels[p1 + 3] - pixels[p2 + 3];

                    cur_pixel += channels;
                }
            }

            for (var y = 0; y < h; y++) {
                v_min[y] = int.min (y + radius + 1, h - 1) * w;
                v_max[y] = int.max (y - radius, 0) * w;
            }

            for (var x = 0; x < w; x++) {
                var a_sum = 0, r_sum = 0, g_sum = 0, b_sum = 0;

                uint32 cur_pixel = x * channels;

                a_sum += radius * buffer[cur_pixel + 0];
                r_sum += radius * buffer[cur_pixel + 1];
                g_sum += radius * buffer[cur_pixel + 2];
                b_sum += radius * buffer[cur_pixel + 3];

                for (var i = 0; i <= radius; i++) {
                    a_sum += buffer[cur_pixel + 0];
                    r_sum += buffer[cur_pixel + 1];
                    g_sum += buffer[cur_pixel + 2];
                    b_sum += buffer[cur_pixel + 3];

                    cur_pixel += w * channels;
                }

                cur_pixel = x * channels;

                for (var y = 0; y < h; y++) {
                    uint32 p1 = (x + v_min[y]) * channels;
                    uint32 p2 = (x + v_max[y]) * channels;

                    pixels[cur_pixel + 0] = dv[a_sum];
                    pixels[cur_pixel + 1] = dv[r_sum];
                    pixels[cur_pixel + 2] = dv[g_sum];
                    pixels[cur_pixel + 3] = dv[b_sum];

                    a_sum += buffer[p1 + 0] - buffer[p2 + 0];
                    r_sum += buffer[p1 + 1] - buffer[p2 + 1];
                    g_sum += buffer[p1 + 2] - buffer[p2 + 2];
                    b_sum += buffer[p1 + 3] - buffer[p2 + 3];

                    cur_pixel += w * channels;
                }
            }
        }

        surface.mark_dirty ();
    }
}
