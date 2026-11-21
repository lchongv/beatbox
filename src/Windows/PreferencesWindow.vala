/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
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

public class BeatBox.PreferencesWindow : Gtk.Window {
	HashMap<PreferencesSection, SideBarItem?> sections;
	HashMap<Widget, Widget> pages; // a section's widget → the page it is in (its own scroll)
	SideBarItem general_iter;
	SideBarItem libraries_iter;
	
	SideBar side_bar;
	Notebook notebook;
	
	Button saveChanges;
	CheckButton advanced;
	PreferencesSection first_section; // shown when the page on screen is hidden
	
	public PreferencesWindow () {
		sections = new HashMap<PreferencesSection, SideBarItem?>();
		pages = new HashMap<Widget, Widget>();
		
		build_ui();
		add_sections();
		
		present();
		
	}
	
	void build_ui () {
		set_title(_("Preferences"));

		// Window properties
		set_modal(true);
		//resizable = false;
		set_transient_for(App.window);
		set_size_request(-1, 400);
		set_default_size(-1, 400);

		var content = new Box(Orientation.VERTICAL, 10);
		var padding = new Box(Orientation.HORIZONTAL, 0);
		var notebook_padding = new Box(Orientation.HORIZONTAL, 10);
		
		side_bar = new SideBar();
		notebook = new Notebook();
		
		side_bar.width_request = 150;
		
		notebook.show_tabs = false;
		notebook.show_border = false;
		
		notebook.hexpand = notebook.vexpand = true;
		notebook.margin_start = notebook.margin_end = 10;
		notebook_padding.append(notebook);
		notebook_padding.hexpand = notebook_padding.vexpand = true;
		
		var list_to_content = new Box(Orientation.HORIZONTAL, 0);
		var side_scroll = new ScrolledWindow();
		side_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
		side_scroll.set_child(side_bar);
		side_scroll.has_frame = true;
		list_to_content.append(side_scroll);
		list_to_content.append(notebook_padding);
		
		saveChanges = new Button.with_label(_("Done"));
		
		// Basic or advanced: off, the side bar keeps the everyday pages and those hide their
		// advanced rows (SimplePreferences.begin_advanced); on, everything shows
		advanced = new CheckButton.with_label(_("Show advanced settings"));
		App.settings.main.bind_property("show-advanced-preferences", advanced, "active",
			BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
		advanced.hexpand = true;
		advanced.halign = Align.START;
		App.settings.main.notify["show-advanced-preferences"].connect(update_visible_sections);

		// Add save button
		var bottomButtons = new Box(Orientation.HORIZONTAL, 6);
		bottomButtons.append(advanced);
		bottomButtons.append(saveChanges);
		
		list_to_content.vexpand = true;
		content.append(UI.wrap_alignment(list_to_content, 10, 0, 0, 0));
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.append(bottomButtons);
		
		content.hexpand = true;
		padding.append(UI.wrap_alignment(content, 0, 10, 0, 10));
		set_child(padding);
		
		general_iter = side_bar.addItem(null, null, null, null, null, _("General"), null, false, false, false);
		libraries_iter = side_bar.addItem(null, null, null, null, null, _("Libraries"), null, false, false, false);
		
		saveChanges.clicked.connect(saveClicked);
		side_bar.true_selection_change.connect(side_bar_selection_change);
	}
	
	void add_sections() {
		var library_pref = new LibraryPreferences();
		first_section = library_pref;
		add_section(library_pref);
		add_section(new PlaybackPreferences());
		add_section(new RecordingPreferences());
		add_section(new AppearancePreferences());
		add_section(new LcdPreferences());
		add_section(new VisualizerPreferences());
		add_section(new MiniPlayerPreferences());
		add_section(new CoverPreferences());
		add_section(new ShortcutsPreferences());
		add_section(new LastfmPreferences());
		add_section(new PluginsPreferences());
		add_section(new AboutPreferences());
		
		foreach(var library in App.library.all_libraries()) {
			if(library.preferences_section != null) {
				add_section(library.preferences_section);
			}
		}
		
		update_visible_sections();
		side_bar.setSelectedItem(sections.get(library_pref));
	}

	/** The pages shown without "Show advanced settings": about five everyday ones */
	static bool is_basic(PreferencesSection section) {
		return section is LibraryPreferences || section is PlaybackPreferences || section is AppearancePreferences
		    || section is CoverPreferences || section is AboutPreferences;
	}

	void update_visible_sections() {
		bool all = App.settings.main.show_advanced_preferences;
		var on_screen = side_bar.getSelectedWidget();
		bool on_screen_hidden = false;
		bool any_library = false;
		foreach (var section in sections.keys)
			any_library = any_library || ((all || is_basic(section)) && section.category == PreferencesSectionCategory.LIBRARIES);
		side_bar.setVisibility(libraries_iter, any_library); // its heading goes with its pages, and first
		foreach (var e in sections.entries) {
			bool shown = all || is_basic(e.key);
			side_bar.setVisibility(e.value, shown);
			if (!shown && e.key.widget == on_screen)
				on_screen_hidden = true;
		}
		side_bar.expand_all();
		if (on_screen_hidden)
			side_bar.setSelectedItem(sections.get(first_section));
	}
	
	public void add_section(PreferencesSection section) {
		if(sections.get(section) != null) {
			warning("Cannot add section: already added");
			return; // nothing to do but tell them they suck and return
		}
		
		SideBarItem? parent = null;
		if(section.category == PreferencesSectionCategory.LIBRARIES)
			parent = libraries_iter;
		else
			parent = general_iter;
		
		SideBarItem? iter = side_bar.addItem(parent, null, section, section.widget, section.icon, section.title, null, false, false, false);
		sections.set(section, iter);
		// only a page taller than the window scrolls: its own scroll, not the whole notebook's
		var page_scroll = new ScrolledWindow();
		page_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
		page_scroll.propagate_natural_height = true;
		page_scroll.max_content_height = 640;
		page_scroll.set_child(section.widget);
		Widget page = AquaScroll.wrap(page_scroll);
		pages.set(section.widget, page);
		notebook.append_page(page);
		if (first_section != null && !App.settings.main.show_advanced_preferences && !is_basic(section))
			side_bar.setVisibility(iter, false); // a plugin's page, added later
	}
	
	public void remove_section(PreferencesSection section) {
		if(sections.get(section) == null) {
			warning("Cannot remove section: not in preferences");
			return; // nothing to do but tell them they suck and return
		}
		
		side_bar.removeItem(sections.get(section));
		notebook.remove_page(notebook.page_num(pages.get(section.widget)));
		pages.unset(section.widget);
		sections.unset(section);
	}
	
	void side_bar_selection_change() {
		var w = side_bar.getSelectedWidget ();
		notebook.set_current_page(notebook.page_num(pages.get(w)));
	}
		
	void saveClicked() {
		foreach(var section in sections.keys) {
			section.save();
		}
		
		destroy();
	}
}
