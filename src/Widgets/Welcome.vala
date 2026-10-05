/*
 * The page a view shows when it has nothing to list: a title, a subtitle and
 * buttons with an icon, a title and a description.
 * Adapted from Granite's Welcome and WelcomeButton (granite 6.2.0, LGPL-3.0-or-later):
 * Copyright 2011-2019 elementary, Inc.; written by Maxwell Barvian, Victor Eduardo
 * and Corentin Noël. Same widgets and style classes, so it looks the same.
 */

public class BeatBox.Welcome : Gtk.EventBox {
	public signal void activated (int index);

	GLib.List<Gtk.Button> buttons = new GLib.List<Gtk.Button> ();
	Gtk.Grid options;

	public Welcome (string title, string subtitle) {
		get_style_context ().add_class (Gtk.STYLE_CLASS_VIEW);
		get_style_context ().add_class ("welcome");

		var title_label = new Gtk.Label (title);
		title_label.justify = Gtk.Justification.CENTER;
		title_label.hexpand = true;
		title_label.get_style_context ().add_class ("h1");

		var subtitle_label = new Gtk.Label (subtitle);
		subtitle_label.justify = Gtk.Justification.CENTER;
		subtitle_label.hexpand = true;
		subtitle_label.wrap = true;
		subtitle_label.wrap_mode = Pango.WrapMode.WORD;
		subtitle_label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
		subtitle_label.get_style_context ().add_class ("h2");

		options = new Gtk.Grid ();
		options.orientation = Gtk.Orientation.VERTICAL;
		options.row_spacing = 12;
		options.halign = Gtk.Align.CENTER;
		options.margin_top = 24;

		var content = new Gtk.Grid ();
		content.expand = true;
		content.margin = 12;
		content.orientation = Gtk.Orientation.VERTICAL;
		content.valign = Gtk.Align.CENTER;
		content.add (title_label);
		content.add (subtitle_label);
		content.add (options);

		add (content);
	}

	public int append (string icon_name, string title, string description) {
		var image = new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.DIALOG);
		image.use_fallback = true;
		return append_with_image (image, title, description);
	}

	public int append_with_pixbuf (Gdk.Pixbuf? pixbuf, string title, string description) {
		return append_with_image (new Gtk.Image.from_pixbuf (pixbuf), title, description);
	}

	public int append_with_image (Gtk.Image? image, string title, string description) {
		var title_label = new Gtk.Label (title);
		title_label.get_style_context ().add_class ("h3");
		title_label.halign = Gtk.Align.START;
		title_label.valign = Gtk.Align.END;

		var description_label = new Gtk.Label (description);
		description_label.halign = Gtk.Align.START;
		description_label.valign = Gtk.Align.START;
		description_label.wrap = true;
		description_label.wrap_mode = Pango.WrapMode.WORD;
		description_label.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);

		var grid = new Gtk.Grid ();
		grid.column_spacing = 12;
		grid.attach (title_label, 1, 0, 1, 1);
		grid.attach (description_label, 1, 1, 1, 1);
		if (image != null) {
			image.pixel_size = 48;
			image.halign = Gtk.Align.CENTER;
			image.valign = Gtk.Align.CENTER;
			grid.attach (image, 0, 0, 1, 2);
		}

		var button = new Gtk.Button ();
		button.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
		button.add (grid);
		button.clicked.connect (() => activated (buttons.index (button)));
		buttons.append (button);
		options.add (button);

		return buttons.index (button);
	}

	public void remove_item (uint index) {
		unowned Gtk.Button? button = buttons.nth_data (index);
		if (button != null) {
			button.destroy (); // the list's reference keeps it alive until it leaves the list
			buttons.remove (button);
		}
	}

	public void set_item_sensitivity (uint index, bool sensitive) {
		unowned Gtk.Button? button = buttons.nth_data (index);
		if (button != null)
			button.sensitive = sensitive;
	}
}
