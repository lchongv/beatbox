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

/** Base for the simple General pages: a column of bold headings and indented rows */
public abstract class BeatBox.SimplePreferences : GLib.Object, PreferencesSection {
	public PreferencesSectionCategory category { get { return PreferencesSectionCategory.GENERAL; } }
	public abstract string title { get; }
	public Gdk.Pixbuf? icon { get { return null; } }
	public Widget widget { get { return content; } }
	
	protected Box content = new Box(Orientation.VERTICAL, 10);
	
	protected void add_heading(string text) {
		var label = new Label("");
		label.xalign = 0.0f;
		label.set_markup("<b>" + Markup.escape_text(text) + "</b>");
		content.pack_start(label, false, true, 0);
	}
	
	protected void add_row(Widget row) {
		content.pack_start(UI.wrap_alignment(row, 0, 0, 0, 10), false, true, 0);
	}
	
	protected CheckButton add_check(string text, bool active) {
		var check = new CheckButton.with_label(text);
		check.active = active;
		add_row(check);
		return check;
	}
	
	protected static Box labelled(string text, Widget w, string? after = null) {
		var box = new Box(Orientation.HORIZONTAL, 8);
		box.pack_start(new Label(text), false, false, 0);
		box.pack_start(w, false, false, 0);
		if (after != null)
			box.pack_start(new Label(after), false, false, 0);
		return box;
	}
	
	public void save() {
	}
	
	public void cancel() {
	}
}

/** How the library folder is managed */
public class BeatBox.BehaviorPreferences : SimplePreferences {
	public override string title { get { return _("Behavior"); } }
	
	public BehaviorPreferences() {
		add_heading(_("Library Management"));
		var organize = add_check(_("Keep media folders organized"), App.settings.main.update_folder_hierarchy);
		var write = add_check(_("Write metadata to file"), App.settings.main.write_metadata_to_file);
		var copy = add_check(_("Copy files to library folder when imported"), App.settings.main.copy_imported_music);
		organize.toggled.connect(() => { App.settings.main.update_folder_hierarchy = organize.active; });
		write.toggled.connect(() => { App.settings.main.write_metadata_to_file = write.active; });
		copy.toggled.connect(() => { App.settings.main.copy_imported_music = copy.active; });
	}
}

/** Skins and the LCD position marker */
public class BeatBox.AppearancePreferences : SimplePreferences {
	public override string title { get { return _("Appearance"); } }
	
	public AppearancePreferences() {
		// Skins (plugins: folders in ~/.local/share/beatbox/skins)
		add_heading(_("Skin"));
		var skinChooser = new ComboBoxText();
		var skinInfo = new Label("");
		skinInfo.xalign = 0.0f;
		skinInfo.wrap = true;
		skinInfo.max_width_chars = 60;
		skinInfo.get_style_context().add_class("dim-label");
		var skins = Skins.available();
		skinChooser.append("", _("None (iTunes)"));
		foreach (var skin in skins)
			skinChooser.append(skin.id, skin.name);
		if (!skinChooser.set_active_id(App.settings.main.skin))
			skinChooser.active_id = "";
		var openSkins = new Button.with_label(_("Open Skins Folder"));
		openSkins.clicked.connect(() => {
			DirUtils.create_with_parents(Skins.user_dir(), 0755);
			try {
				AppInfo.launch_default_for_uri(File.new_for_path(Skins.user_dir()).get_uri(), null);
			} catch (Error err) {
				warning("Could not open %s: %s", Skins.user_dir(), err.message);
			}
		});
		var skinBox = labelled(_("Skin:"), skinChooser);
		skinBox.pack_start(openSkins, false, false, 0);
		add_row(skinBox);
		add_row(skinInfo);
		skinChooser.changed.connect(() => {
			string id = skinChooser.active_id ?? "";
			App.settings.main.skin = id;
			Skins.apply(id); // live preview
			skinInfo.label = _("Add more skins by copying them into %s").printf(Skins.user_dir());
			foreach (var skin in skins)
				if (skin.id == id)
					skinInfo.label = skin.description + (skin.author != "" ? "  —  " + skin.author : "");
		});
		skinChooser.changed();
		
		add_heading(_("Display"));
		var markerSize = new SpinButton.with_range(6, 28, 1);
		markerSize.value = App.settings.main.lcd_marker_size;
		add_row(labelled(_("Size of the position marker (diamond):"), markerSize, _("pixels")));
		markerSize.value_changed.connect(() => {
			App.settings.main.lcd_marker_size = (int)markerSize.value;
			App.apply_lcd_marker_size((int)markerSize.value); // live preview
		});
	}
}

/** The cover grid and where album art comes from */
public class BeatBox.CoverPreferences : SimplePreferences {
	public override string title { get { return _("Album Art"); } }
	
	public CoverPreferences() {
		add_heading(_("Cover Grid"));
		var clickMode = new ComboBoxText();
		clickMode.append("inline", _("Unfold it inline, under its row (iTunes 11)"));
		clickMode.append("popup", _("Open it in a popup window"));
		clickMode.active_id = App.settings.main.album_grid_inline ? "inline" : "popup";
		clickMode.changed.connect(() => { App.settings.main.album_grid_inline = (clickMode.active_id == "inline"); });
		add_row(labelled(_("Clicking an album in the cover grid:"), clickMode));
		
		add_heading(_("Missing Album Art"));
		var download = add_check(_("Download missing album art from the internet (MusicBrainz, Apple Music)"), App.settings.main.download_covers);
		download.toggled.connect(() => {
			App.settings.main.download_covers = download.active;
			if (download.active)
				App.covers.fetch_remaining_album_art();
		});
	}
}
