/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originaly Written by Scott Ringwelski for BeatBox Music Player
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
using Gee;
/**
 * The "Get Info" window: the editor's pages under a row of capsule tabs
 * centred on a rounded panel, a check box for writing to the files, and
 * Previous / Next / Cancel / OK. Previous and Next save, then show the
 * neighbouring song (Alt+Left / Alt+Right).
 */
public class BeatBox.MediaEditor : Window {
	LinkedList<Media> entire_media_list;
	LinkedList<Media> current_medias;
	
	MediaEditorInterface editor;
	Stack pages;
	StackSwitcher tabs;
	Box panel;
	CheckButton write_to_file;
	
	public MediaEditor(LinkedList<Media> entire_media_list, LinkedList<Media> medias) {
		if(medias.size == 0)
			return;
		
		this.entire_media_list = entire_media_list;
		this.current_medias = medias;
		
		window_position = WindowPosition.CENTER_ON_PARENT;
		type_hint = Gdk.WindowTypeHint.DIALOG;
		modal = true;
		transient_for = App.window;
		destroy_with_parent = true;
		set_default_size(640, 560);
		get_style_context().add_class("song-info");
		
		var root = new Box(Orientation.VERTICAL, 10);
		root.margin = 14;
		
		// the tabs float centred over the panel's top edge
		pages = new Stack();
		pages.transition_type = StackTransitionType.CROSSFADE;
		pages.vexpand = true;
		var panel = new Box(Orientation.VERTICAL, 0);
		panel.get_style_context().add_class("tiger-panel");
		panel.margin_top = 13; // half the tabs' height
		panel.add(pages);
		var tabs = new StackSwitcher();
		tabs.stack = pages;
		tabs.halign = Align.CENTER;
		tabs.valign = Align.START;
		tabs.get_style_context().add_class("tiger-tabs");
		this.tabs = tabs;
		this.panel = panel;
		var frame = new Overlay();
		frame.add(panel);
		frame.add_overlay(tabs);
		frame.vexpand = true;
		root.add(frame);
		
		write_to_file = new CheckButton.with_label(_("Also write changes to the file"));
		write_to_file.active = App.settings.main.write_metadata_to_file;
		write_to_file.tooltip_text = _("Otherwise the changes stay in BeatBox's library and the tags in the files are left as they are (the same option as in Preferences)");
		root.add(write_to_file);
		
		var buttons = new Box(Orientation.HORIZONTAL, 8);
		buttons.halign = Align.END;
		var previous = new Button.with_label(_("Previous"));
		var next = new Button.with_label(_("Next"));
		var cancel = new Button.with_label(_("Cancel"));
		var ok = new Button.with_label(_("OK"));
		previous.tooltip_text = _("Save the changes and show the previous song (Alt+Left)");
		next.tooltip_text = _("Save the changes and show the next song (Alt+Right)");
		previous.sensitive = next.sensitive = entire_media_list.size > 1;
		foreach(var b in new Button[] { previous, next, cancel, ok }) {
			b.width_request = 96;
			buttons.add(b);
		}
		ok.can_default = true;
		root.add(buttons);
		add(root);
		
		previous.clicked.connect(() => move_by(-1));
		next.clicked.connect(() => move_by(1));
		cancel.clicked.connect(() => destroy());
		ok.clicked.connect(() => {
			save();
			destroy();
		});
		var keys = new EventControllerKey(this);
		keys.key_pressed.connect((keyval, keycode, state) => {
			if((state & Gdk.ModifierType.MOD1_MASK) != 0 && previous.sensitive && (keyval == Gdk.Key.Left || keyval == Gdk.Key.Right)) {
				move_by(keyval == Gdk.Key.Left ? -1 : 1);
				return true;
			}
			if(keyval == Gdk.Key.Escape) {
				destroy();
				return true;
			}
			return false;
		});
		set_data("key-controller", keys); // GTK3 controllers need a reference
		
		build_pages(null);
		show_all();
		ok.grab_default();
	}
	
	/** The editor's pages for current_medias, showing the one titled like the page that was shown */
	void build_pages(string? shown) {
		pages.foreach((w) => w.destroy());
		
		// Assume all medias are of same type
		editor = current_medias.get(0).get_editor_widget();
		bool single = current_medias.size == 1;
		var metadata = editor.get_metadata_view(current_medias);
		var views = editor.get_extra_views();
		views.set(_("Info"), metadata);
		if(single && !views.has_key(_("Summary")))
			views.set(_("Details"), new InfoViewport(current_medias.get(0)));
		
		// the editor's pages in this order, any others after them
		var names = new ArrayList<string>.wrap({ _("Summary"), _("Info"), _("Comments"), _("Sorting"), _("Options"),
		                                         _("Lyrics"), _("Pictures"), _("Artwork"), _("Details") });
		foreach(var name in views.keys)
			if(!(name in names))
				names.add(name);
		foreach(var name in names) {
			if(!views.has_key(name))
				continue;
			var page = views[name];
			page.show_all();
			pages.add_titled(page, name, name);
		}
		pages.visible_child_name = (shown != null && views.has_key(shown)) ? shown : (views.has_key(_("Summary")) ? _("Summary") : _("Info"));
		
		foreach(FieldEditor fe in editor.get_fields())
			fe.set_check_visible(!single);
		
		// the overlay doesn't measure the tabs: the panel is made at least as wide as they are
		int tabs_width;
		tabs.show_all();
		tabs.get_preferred_width(null, out tabs_width);
		panel.width_request = tabs_width + 40;
		
		title = single ? _("Song Info") : _("Info for %d Songs").printf(current_medias.size);
	}
	
	void save() {
		App.settings.main.write_metadata_to_file = write_to_file.active;
		editor.save_medias(current_medias);
	}
	
	/** Saves, then edits the song before (-1) or after (1) the ones edited, going round the list */
	void move_by(int step) {
		int i = entire_media_list.index_of(step < 0 ? current_medias.first() : current_medias.last());
		int n = entire_media_list.size;
		var m = entire_media_list.get(((i + step) % n + n) % n);
		
		save();
		current_medias = new LinkedList<Media>();
		current_medias.add(m);
		build_pages(pages.visible_child_name);
		pages.show_all();
	}
}
