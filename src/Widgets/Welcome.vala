/*
 * The page a view shows when it has nothing to list: a title, a subtitle and
 * buttons with an icon, a title and a description.
 * Adapted from Granite's Welcome and WelcomeButton (granite 6.2.0, LGPL-3.0-or-later):
 * Copyright 2011-2019 elementary, Inc.; written by Maxwell Barvian, Victor Eduardo
 * and Corentin Noël. Same widgets and style classes, so it looks the same.
 */

public class BeatBox.Welcome : Gtk.Box {
	public signal void activated (int index);

	GLib.List<Gtk.Button> buttons = new GLib.List<Gtk.Button> ();
	Gtk.Grid options;

	public Welcome (string title, string subtitle) {
		orientation = Gtk.Orientation.VERTICAL;
		spacing = 0;
		add_css_class ("view");
		add_css_class ("welcome");

		var title_label = new Gtk.Label (title);
		title_label.justify = Gtk.Justification.CENTER;
		title_label.hexpand = true;
		title_label.add_css_class("h1");

		var subtitle_label = new Gtk.Label (subtitle);
		subtitle_label.justify = Gtk.Justification.CENTER;
		subtitle_label.hexpand = true;
		subtitle_label.wrap = true;
		subtitle_label.wrap_mode = Pango.WrapMode.WORD;
		subtitle_label.add_css_class("dim-label");
		subtitle_label.add_css_class("h2");

		options = new Gtk.Grid ();
		options.orientation = Gtk.Orientation.VERTICAL;
		options.row_spacing = 12;
		options.halign = Gtk.Align.CENTER;
		options.margin_top = 24;

		var content = new Gtk.Grid ();
		content.hexpand = content.vexpand = true;
		content.margin_top = content.margin_bottom = 12;
		content.margin_start = content.margin_end = 12;
		content.orientation = Gtk.Orientation.VERTICAL;
		content.valign = Gtk.Align.CENTER;
		content.attach (title_label, 0, 0, 1, 1);
		content.attach (subtitle_label, 0, 1, 1, 1);
		content.attach (options, 0, 2, 1, 1);

		// scrolled: the wrapped text would otherwise make the window's minimum height depend on its
		// width, and GTK 4 then measures the window below that minimum ("Trying to measure ...")
		var scrolled = new Gtk.ScrolledWindow ();
		scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
		scrolled.vexpand = true;
		scrolled.child = content;
		base.append (scrolled);
	}

	public new int append (string icon_name, string title, string description) {
		var image = new Gtk.Image.from_icon_name (icon_name);
		image.use_fallback = true;
		return append_with_image (image, title, description);
	}

	public int append_with_pixbuf (Gdk.Pixbuf? pixbuf, string title, string description) {
		var image = new Gtk.Image ();
		UI.show_pixbuf (image, pixbuf);
		return append_with_image (image, title, description);
	}

	public int append_with_image (Gtk.Image? image, string title, string description) {
		var title_label = new Gtk.Label (title);
		title_label.add_css_class("h3");
		title_label.halign = Gtk.Align.START;
		title_label.valign = Gtk.Align.END;

		var description_label = new Gtk.Label (description);
		description_label.halign = Gtk.Align.START;
		description_label.valign = Gtk.Align.START;
		description_label.wrap = true;
		description_label.wrap_mode = Pango.WrapMode.WORD;
		// one fixed width: a centered grid whose height changes with its width makes GTK 4 warn
		description_label.width_chars = description_label.max_width_chars = 40;
		description_label.xalign = 0;
		description_label.add_css_class("dim-label");

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
		button.add_css_class ("flat");
		button.child = grid;
		button.clicked.connect (() => activated (buttons.index (button)));
		buttons.append (button);
		options.attach (button, 0, buttons.index (button), 1, 1);

		return buttons.index (button);
	}

	public void remove_item (uint index) {
		unowned Gtk.Button? button = buttons.nth_data (index);
		if (button != null) {
			options.remove (button);
			buttons.remove (button);
			// keep the remaining buttons in consecutive rows
			for (int i = 0; i < buttons.length (); i++)
				options.attach (buttons.nth_data (i), 0, i, 1, 1);
		}
	}

	public void set_item_sensitivity (uint index, bool sensitive) {
		unowned Gtk.Button? button = buttons.nth_data (index);
		if (button != null)
			button.sensitive = sensitive;
	}
}
