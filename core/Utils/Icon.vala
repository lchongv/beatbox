/*-
 * Copyright (c) 2011-2012		Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski and Victor Eduardo for
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

public class BeatBox.Icon : GLib.Object {
	public string name { get; private set; }

	public bool has_backup {
		get {
			return (this.backup != null);
		}
	}

	public string backup_filename {
		get {
			if (backup == null)
				return "";

			return backup;
		}
	}

	private string? backup;
	private int? size;
	private IconsInterface.Type? type;
	private IconsInterface.FileType? file_type;
	
	protected const string MIMETYPES_FOLDER = "mimetypes";
    protected const string ACTIONS_FOLDER = "actions";
    protected const string STATUS_FOLDER = "status";
    protected const string APPS_FOLDER = "apps";
    protected const string OTHER_FOLDER = "other";

    protected const string PNG_EXT = ".png";
    protected const string SVG_EXT = ".svg";
    protected const string RESOURCE_DIR = "/net/launchpad/beatbox/icons";

	/**
	 * @param name icon name
	 *
	 * The following parameters are only necessary if has_backup is true.
	 * @param size pixel-size of the backup icon
	 * @param type Icon category
	 * @param file_type Icon type (SVG or PNG)
	 * FIXME deprecate has_backup
	 * @param has_backup whether a backup exists or not. It will be deprecated in the future since it's redundant
	 */
	public Icon (string name, int? size = 16, IconsInterface.Type? type = IconsInterface.Type.ACTION, IconsInterface.FileType? file_type = IconsInterface.FileType.SVG, bool has_backup = false) {

		this.name = name;
		this.size = size;
		this.type = type;
		this.file_type = file_type;

		/**
		 * The following code creates a backup path for the icon.
		 * This ensures consistency in the way we store icons in the
		 * 'images' folder.
		 **/
		if (has_backup && type != null && size != null) {
			string size_folder, type_folder, actual_icon_name;

			if (size != null)
				size_folder = size.to_string() + "x" + size.to_string();
			else
				size_folder = "";

			switch (type)
			{
				case IconsInterface.Type.MIMETYPE:
					type_folder = MIMETYPES_FOLDER;
					break;
				case IconsInterface.Type.ACTION:
					type_folder = ACTIONS_FOLDER;
					break;
				case IconsInterface.Type.STATUS:
					type_folder = STATUS_FOLDER;
					break;
				case IconsInterface.Type.APP:
					type_folder = APPS_FOLDER;
					break;
				default:
					type_folder = OTHER_FOLDER;
					break;
			}

			if (file_type != null) {
				switch (file_type)
				{
					case IconsInterface.FileType.SVG:
						actual_icon_name = this.name + SVG_EXT;
						break;
					case IconsInterface.FileType.PNG:
						actual_icon_name = this.name + PNG_EXT;
						break;
					default:
						actual_icon_name = this.name + SVG_EXT;
						break;
				}
			}
			else {
				actual_icon_name = name + SVG_EXT;
			}

			// Bundled icons live in the binary (GResource), so they work wherever
			// BeatBox is installed or run from.
			this.backup = GLib.Path.build_filename(RESOURCE_DIR, size_folder, type_folder, actual_icon_name);
		}
		else {
			this.backup = null;
		}
	}

	public GLib.Icon get_gicon () {
		return new GLib.ThemedIcon.with_default_fallbacks (this.name);
	}

	// GTK4 has no icon_size_lookup () and its IconSize only says "normal" or "large"; the theme
	// sizes them in CSS, and by default they are 16 and 32 px
	static void size_lookup (Gtk.IconSize size, out int width, out int height) {
		width = size == Gtk.IconSize.LARGE ? 32 : 16;
		height = width;
	}

	// Bundled icons decoded once per size: each SVG takes milliseconds, and every list's
	// rating stars asked for the same ones. Covers load in a thread too, hence the lock.
	static Gee.HashMap<string, Gdk.Pixbuf>? decoded = null;
	static Mutex decoded_lock;

	static Gdk.Pixbuf? bundled (string path, int width, int height) {
		string key = "%s@%dx%d".printf (path, width, height);
		decoded_lock.lock ();
		if (decoded == null)
			decoded = new Gee.HashMap<string, Gdk.Pixbuf> ();
		Gdk.Pixbuf? rv = decoded[key];
		if (rv == null) {
			try {
				rv = new Gdk.Pixbuf.from_resource_at_scale (path, width, height, true);
				decoded[key] = rv;
			}
			catch (Error err) {
				warning ("Couldn't load bundled icon: %s", err.message);
			}
		}
		decoded_lock.unlock ();
		return rv;
	}

	public Gdk.Pixbuf? render (Gtk.IconSize? size, Gtk.Widget? context = null, int px_size = 0) {
		Gdk.Pixbuf? rv = null;
		int width = 16, height = 16;

		// Don't load image as a regular icon if it's a PNG and belongs
		// to the project's folder.
		if (file_type == IconsInterface.FileType.PNG && has_backup && size == null) {
			try {
				rv = new Gdk.Pixbuf.from_resource(backup);
			}
			catch (Error err) {
				warning ("Could not load PNG image: %s\n", err.message);
			}

			return rv;
		}

		// If a null size was passed, use original size
		if (size != null) {
			size_lookup (size, out width, out height);
		}
		else if (px_size > 0) {
			width = px_size;
			height = px_size;
		}
		else if (this.size != null) {
			width = this.size;
			height = width;
		}

		// Prefer our own icon: theme lookups with generic fallback can return
		// an unrelated (grey, symbolic) icon for BeatBox's custom names
		if (has_backup) {
			rv = bundled (this.backup, width, height);
		}
		
		// Otherwise load it from the theme
		var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
		if (rv == null && theme.has_icon(this.name)) {
			try {
				// the ThemedIcon already carries the generic fallbacks
				var icon = theme.lookup_by_gicon (get_gicon (), height, 1, Gtk.TextDirection.NONE, 0);
				var file = icon.get_file ();
				if (file != null && file.get_path () != null)
					rv = new Gdk.Pixbuf.from_file_at_size (file.get_path (), height, height);
			}
			catch (Error err) {
				message ("%s, falling back to default.", err.message);
			}
		}

		// a symbolic icon takes the widget's color, as GTK3's load_symbolic_for_context did
		// (ponytail: in one color; the few two-color symbolic icons lose their accent)
		if (rv != null && context != null && this.name.has_suffix ("-symbolic"))
			rv = UI.tint (rv, context.get_color ());

		return rv;
	}

	/**
	 * Use this method for loading symbolic icons. They will follow every state.
	 **/
	public Gtk.Image? render_image (Gtk.IconSize? size, Gtk.Widget? ctx = null, int px_size = 0) {
		Gtk.Image? rv = null;
		int width = 16, height = 16;

		// If a null size was passed, use original size
		if (size != null) {
			size_lookup (size, out width, out height);
		}
		else if (px_size > 0) {
			width = px_size;
			height = px_size;
		}
		else if (this.size != null) {
			width = this.size;
			height = width;
		}

		if (has_backup) {
			rv = new Image.from_resource (this.backup);
		} else if (Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).has_icon (this.name) && size != null) {
			rv = new Image.from_icon_name (this.name);
			rv.pixel_size = width;
		} else {
			// And if there was no backup, use the default method
			message ("Loading %s using default method", this.name);
			rv = new Image ();
			UI.show_pixbuf (rv, this.render (size, ctx));
		}

		return rv;
	}

}

