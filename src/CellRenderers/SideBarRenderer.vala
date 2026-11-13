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
using Gdk;

public class BeatBox.SideBarRenderer : CellRenderer {
	public TreeModel model;
	public TreeIter iter;
	public bool expanded;
	public bool highlight;
	public static int EXPANDER_SIZE = 8;
	public static int DEPTH_INDENT_SIZE = 8;
	public static int PIXBUF_SIZE = 18;
	
	public SideBarRenderer() {
		expanded = false;
	}
	
	static HashTable<Pixbuf, bool> monochrome = new HashTable<Pixbuf, bool>(direct_hash, direct_equal);
	
	/** True for symbolic icons: every visible pixel is a shade of grey */
	static bool is_monochrome(Pixbuf pix) {
		if(monochrome.contains(pix))
			return monochrome[pix];
		bool result = pix.has_alpha && pix.n_channels == 4;
		unowned uint8[] px = pix.get_pixels_with_length();
		for(int y = 0; result && y < pix.height; y++) {
			for(int x = 0; x < pix.width; x++) {
				int i = y * pix.rowstride + x * 4;
				if(px[i + 3] > 64 && (((int)px[i] - px[i + 1]).abs() > 12 || ((int)px[i + 1] - px[i + 2]).abs() > 12)) {
					result = false;
					break;
				}
			}
		}
		monochrome[pix] = result;
		return result;
	}
	
	static string heading_color(Widget widget) {
		RGBA c;
		if(!widget.get_style_context().lookup_color("bb_sidebar_heading", out c))
			return "#4a586d";
		return "#%02x%02x%02x".printf((int)(c.red * 255), (int)(c.green * 255), (int)(c.blue * 255));
	}
	
	public override void get_preferred_width(Widget widget, out int minimum_size, out int natural_size) {
		minimum_size = 1; // GTK3 ignores the height of a renderer that reports no width
		natural_size = 1;
	}

	public override void get_preferred_height(Widget widget, out int minimum_size, out int natural_size) {
		int dumby;
		widget.create_pango_layout("Test").get_pixel_size(out dumby, out minimum_size);
		minimum_size += 6; // 3 px extra on each side for the text
		natural_size = minimum_size;
	}

	public override void snapshot(Gtk.Snapshot s, Widget widget, Gdk.Rectangle background_area, Gdk.Rectangle cell_area, CellRendererState flags) {
		// the cairo node covers the background, as the old clip did
		var r = Graphene.Rect();
		r.init(background_area.x, background_area.y, background_area.width, background_area.height);
		var context = s.append_cairo(r);
		context.rectangle(background_area.x, background_area.y, background_area.width, background_area.height);
		context.clip();

		StateFlags state;
		RGBA rgba;
		Pango.Layout layout; // for text to draw
		Pixbuf pix;
		string text;
		int children;
		int depth;
		Pixbuf clickable;
		bool rtl; // right to left

		model.get(iter, SideBarColumn.COLUMN_PIXBUF, out pix, SideBarColumn.COLUMN_TEXT, out text, SideBarColumn.COLUMN_CLICKABLE, out clickable);
		TreePath path = model.get_path(iter);
		depth = path.get_depth();
		layout = widget.create_pango_layout(text);
		children = model.iter_n_children(iter);

		int flag = flags & Gtk.CellRendererState.SELECTED;
		state = (flag != 0 && depth != 1) ? StateFlags.SELECTED : StateFlags.NORMAL;

		// GTK4 colors take no state argument: the selected text color is looked up by name
		rgba = widget.get_style_context().get_color();
		if(state == StateFlags.SELECTED) {
			RGBA selected;
			if(widget.get_style_context().lookup_color("theme_selected_fg_color", out selected))
				rgba = selected;
		}
		rtl = widget.get_direction() == Gtk.TextDirection.RTL;
		
		// Draw a blank space for each level of indent
		double start_x = depth * DEPTH_INDENT_SIZE;
		double start_y = cell_area.y + 3;
		if(rtl)
			start_x = cell_area.width - start_x;
		
		// Draw picture if it is not level 1
		if(depth != 1 && pix != null) {
			context.move_to(start_x, start_y);
			int image_y = (cell_area.height - pix.height > 0) ? ((cell_area.height - pix.height)/2) : 0;
			Gdk.cairo_set_source_pixbuf(context, pix, (int)start_x, cell_area.y + image_y);
			if(is_monochrome(pix)) {
				// symbolic icon: paint it in the text color (white when selected, light on dark skins)
				var icon = context.get_source();
				context.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha);
				context.mask(icon);
			}
			else {
				context.paint();
			}
			
			start_x += rtl ? -20.0 : 20.0; // for rtl, move to the left. otherwise move to right
		}
		
		// Draw text
		context.set_source_rgba (rgba.red, rgba.green, rgba.blue, rgba.alpha);
		
		if(depth > 1)
			layout.set_text(text, text.length);
		else
			layout.set_markup("<span size='small' weight='bold' foreground='%s'>".printf(heading_color(widget)) + Markup.escape_text(text.up()) + "</span>", -1);
			
		if(rtl)
			layout.set_alignment(Pango.Alignment.RIGHT);
		
		Pango.Rectangle ink;
		Pango.Rectangle extents;
		layout.get_extents(out ink, out extents);
		Pango.extents_to_pixels(ink, extents);
		
		context.move_to(rtl ? (start_x - extents.width + 10) : start_x, start_y);
		Pango.cairo_show_layout(context, layout);
		context.fill();
		
		// If it is supposed to be highlighted, draw the highlight
		if(highlight) {
			draw_highlight(context, background_area.x, background_area.y, 
							background_area.width, background_area.height);
		}
		
		// Draw the expander: a small triangle in the heading's color, pointing down when expanded
		// and to the side when collapsed (GTK 4's render_arrow draws nothing without a CSS icon)
		if(depth == 1 && children > 0) {
			double size = 7, x = rtl ? cell_area.x : cell_area.x + cell_area.width - EXPANDER_SIZE;
			double y = cell_area.y + (cell_area.height - size) / 2;
			var color = Gdk.RGBA();
			color.parse(heading_color(widget));
			Gdk.cairo_set_source_rgba(context, color);
			if(expanded) {
				context.move_to(x, y + 1);
				context.line_to(x + size, y + 1);
				context.line_to(x + size / 2, y + size - 1);
			}
			else {
				double tip = rtl ? x : x + size, back = rtl ? x + size - 1 : x + 1;
				context.move_to(back, y);
				context.line_to(back, y + size);
				context.line_to(tip - (rtl ? -1 : 1), y + size / 2);
			}
			context.close_path();
			context.fill();
		}
		                         
		                         
		context.fill();
	}
	
	void draw_highlight(Cairo.Context context, double x, double y, double width, double height) {
		double aspect        = 1.0;     /* aspect ratio */
		double corner_radius = (height * 2) / 10.0;   /* and corner curvature radius */

		double radius = corner_radius / aspect;
		double degrees = 3.14 / 180.0;

		context.new_sub_path();
		context.arc (x + width - radius, y + radius, radius, -90 * degrees, 0 * degrees);
		context.arc (x + width - radius, y + height - radius, radius, 0 * degrees, 90 * degrees);
		context.arc (x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees);
		context.arc (x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
		context.close_path();
		
		context.set_source_rgba (0.0, 0.3, 1.0, 0.1);
		context.fill_preserve ();
		context.set_source_rgb (0.0, 0.0, 1);
		context.set_line_width (3.0);
		context.stroke ();
	}
}
