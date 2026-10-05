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
	HashMap<PreferencesSection, TreeIter?> sections;
	TreeIter general_iter;
	TreeIter libraries_iter;
	
	SideBar side_bar;
	Notebook notebook;
	
	Button saveChanges;
	
	public PreferencesWindow () {
		sections = new HashMap<PreferencesSection, TreeIter?>();
		
		build_ui();
		add_sections();
		
		show_all();
		
	}
	
	void build_ui () {
		set_title(_("Preferences"));

		// Window properties
		window_position = WindowPosition.CENTER;
		type_hint = Gdk.WindowTypeHint.DIALOG;
		set_modal(true);
		//resizable = false;
		set_transient_for(App.window);
		set_size_request(-1, 400);
		set_default_size(-1, 400);

		var content = new Box(Orientation.VERTICAL, 10);
		var padding = new Box(Orientation.HORIZONTAL, 0);
		var notebook_padding = new Box(Orientation.HORIZONTAL, 10);
		var notebook_scroll = new ScrolledWindow(null, null);
		
		side_bar = new SideBar();
		notebook = new Notebook();
		
		side_bar.width_request = 150;
		
		notebook.show_tabs = false;
		notebook.show_border = false;
		notebook_scroll.set_policy(PolicyType.NEVER, PolicyType.NEVER);
		
		notebook.hexpand = true;
		notebook.margin_start = notebook.margin_end = 10;
		notebook_padding.add(notebook);
		notebook_scroll.add(notebook_padding);
		
		var list_to_content = new Box(Orientation.HORIZONTAL, 0);
		list_to_content.add(side_bar);
		notebook_scroll.hexpand = true;
		list_to_content.add(notebook_scroll);
		
		saveChanges = new Button.with_label(_("Done"));
		
		// Add save button
		var bottomButtons = new ButtonBox(Orientation.HORIZONTAL);
		bottomButtons.set_layout(ButtonBoxStyle.END);
		bottomButtons.add(saveChanges);
		
		list_to_content.vexpand = true;
		content.add(UI.wrap_alignment(list_to_content, 10, 0, 0, 0));
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.add(bottomButtons);
		
		content.hexpand = true;
		padding.add(UI.wrap_alignment(content, 0, 10, 0, 10));
		add(padding);
		
		general_iter = side_bar.addItem(null, null, null, null, null, _("General"), null, false, false, false);
		libraries_iter = side_bar.addItem(null, null, null, null, null, _("Libraries"), null, false, false, false);
		
		saveChanges.clicked.connect(saveClicked);
		side_bar.true_selection_change.connect(side_bar_selection_change);
	}
	
	void add_sections() {
		var behavior_pref = new BehaviorPreferences();
		add_section(behavior_pref);
		add_section(new AppearancePreferences());
		add_section(new CoverPreferences());
		add_section(new ShortcutsPreferences());
		add_section(new LastfmPreferences());
		add_section(new AboutPreferences());
		
		foreach(var library in App.library.all_libraries()) {
			if(library.preferences_section != null) {
				add_section(library.preferences_section);
			}
		}
		
		side_bar.setSelectedIter(side_bar.convertToFilter(sections.get(behavior_pref)));
	}
	
	public void add_section(PreferencesSection section) {
		if(sections.get(section) != null) {
			warning("Cannot add section: already added");
			return; // nothing to do but tell them they suck and return
		}
		
		TreeIter? parent = null;
		if(section.category == PreferencesSectionCategory.LIBRARIES)
			parent = libraries_iter;
		else
			parent = general_iter;
		
		TreeIter? iter = side_bar.addItem(parent, null, section, section.widget, section.icon, Markup.escape_text(section.title), null, false, false, false);
		sections.set(section, iter);
		notebook.append_page(section.widget);
	}
	
	public void remove_section(PreferencesSection section) {
		if(sections.get(section) == null) {
			warning("Cannot remove section: not in preferences");
			return; // nothing to do but tell them they suck and return
		}
		
		side_bar.removeItem(sections.get(section));
		notebook.remove_page(notebook.page_num(section.widget));
		sections.unset(section);
	}
	
	void side_bar_selection_change() {
		var w = side_bar.getSelectedWidget ();
		notebook.set_current_page(notebook.page_num(w));
	}
		
	void saveClicked() {
		foreach(var section in sections.keys) {
			section.save();
		}
		
		destroy();
	}
}
