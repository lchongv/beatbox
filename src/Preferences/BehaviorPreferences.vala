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

public class BeatBox.BehaviorPreferences : GLib.Object, PreferencesSection {
	public PreferencesSectionCategory category { get { return PreferencesSectionCategory.GENERAL; } }
	public string title { get { return _("Behavior"); } }
	public Gdk.Pixbuf? icon { get { return null; } }
	public Widget widget { get { return content; } }
	
	Box content;
	CheckButton organizeFolders;
	CheckButton writeMetadataToFile;
	CheckButton copyImportedMusic;
	CheckButton downloadCovers;
	
	public BehaviorPreferences() {
		content = new Box(Orientation.VERTICAL, 0);
		content.spacing = 10;
		
		var managementLabel = new Label(_("Library Management"));
		organizeFolders = new CheckButton.with_label(_("Keep media folders organized"));
		writeMetadataToFile = new CheckButton.with_label(_("Write metadata to file"));
		copyImportedMusic = new CheckButton.with_label(_("Copy files to library folder when imported"));
		downloadCovers = new CheckButton.with_label(_("Download missing album art from the internet (MusicBrainz, Apple Music)"));
		
		managementLabel.xalign = 0.0f;
		managementLabel.set_markup("<b>" + _("Library Management") + "</b>");
		
		organizeFolders.set_active(App.settings.main.update_folder_hierarchy);
		writeMetadataToFile.set_active(App.settings.main.write_metadata_to_file);
		copyImportedMusic.set_active(App.settings.main.copy_imported_music);
		downloadCovers.set_active(App.settings.main.download_covers);
		
		content.pack_start(managementLabel, false, true, 0);
		content.pack_start(UI.wrap_alignment(organizeFolders, 0, 0, 0, 10), false, true, 0);
		content.pack_start(UI.wrap_alignment(writeMetadataToFile, 0, 0, 0, 10), false, true, 0);
		content.pack_start(UI.wrap_alignment(copyImportedMusic, 0, 0, 0, 10), false, true, 0);
		content.pack_start(UI.wrap_alignment(downloadCovers, 0, 0, 0, 10), false, true, 0);
		downloadCovers.toggled.connect(() => {
			App.settings.main.download_covers = downloadCovers.active;
			if (downloadCovers.active)
				App.covers.fetch_remaining_album_art();
		});
		
		// Appearance
		var appearanceLabel = new Label("");
		appearanceLabel.xalign = 0.0f;
		appearanceLabel.set_markup("<b>" + _("Appearance") + "</b>");
		var markerBox = new Box(Orientation.HORIZONTAL, 8);
		var markerSize = new SpinButton.with_range(6, 28, 1);
		markerSize.value = App.settings.main.lcd_marker_size;
		markerBox.pack_start(new Label(_("Size of the position marker (diamond):")), false, false, 0);
		markerBox.pack_start(markerSize, false, false, 0);
		markerBox.pack_start(new Label(_("pixels")), false, false, 0);
		content.pack_start(appearanceLabel, false, true, 0);
		content.pack_start(UI.wrap_alignment(markerBox, 0, 0, 0, 10), false, true, 0);
		markerSize.value_changed.connect(() => {
			App.settings.main.lcd_marker_size = (int)markerSize.value;
			App.apply_lcd_marker_size((int)markerSize.value); // live preview
		});
		
		// Album grid: iTunes 11 inline band, or the popup window
		var clickBox = new Box(Orientation.HORIZONTAL, 8);
		var clickMode = new ComboBoxText();
		clickMode.append("inline", _("Unfold it inline, under its row (iTunes 11)"));
		clickMode.append("popup", _("Open it in a popup window"));
		clickMode.active_id = App.settings.main.album_grid_inline ? "inline" : "popup";
		clickMode.changed.connect(() => { App.settings.main.album_grid_inline = (clickMode.active_id == "inline"); });
		clickBox.pack_start(new Label(_("Clicking an album in the cover grid:")), false, false, 0);
		clickBox.pack_start(clickMode, false, false, 0);
		content.pack_start(UI.wrap_alignment(clickBox, 0, 0, 0, 10), false, true, 0);
		
		// Skins (plugins: folders in ~/.local/share/beatbox/skins)
		var skinBox = new Box(Orientation.HORIZONTAL, 8);
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
		skinBox.pack_start(new Label(_("Skin:")), false, false, 0);
		skinBox.pack_start(skinChooser, false, false, 0);
		skinBox.pack_start(openSkins, false, false, 0);
		content.pack_start(UI.wrap_alignment(skinBox, 0, 0, 0, 10), false, true, 0);
		content.pack_start(UI.wrap_alignment(skinInfo, 0, 0, 0, 10), false, true, 0);
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
		
		organizeFolders.toggled.connect(organize_folders_toggled);
		writeMetadataToFile.toggled.connect(write_metadata_to_file_toggled);
		copyImportedMusic.toggled.connect(copy_imported_music_toggled);
	}
	
	void organize_folders_toggled() {
		App.settings.main.update_folder_hierarchy = organizeFolders.get_active();
	}
	
	void write_metadata_to_file_toggled() {
		App.settings.main.write_metadata_to_file = writeMetadataToFile.get_active();
	}
	
	void copy_imported_music_toggled() {
		App.settings.main.copy_imported_music = copyImportedMusic.get_active();
	}
	
	public void save() {
		
	}
	
	public void cancel() {
		
	}
}
