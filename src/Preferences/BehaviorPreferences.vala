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
		var lcdLines = new ComboBoxText();
		lcdLines.append("two", _("Two lines, artist and album taking turns (iTunes)"));
		lcdLines.append("one", _("One line"));
		lcdLines.active_id = App.settings.main.lcd_two_lines ? "two" : "one";
		lcdLines.changed.connect(() => { App.settings.main.lcd_two_lines = (lcdLines.active_id == "two"); });
		add_row(labelled(_("Song information in the LCD:"), lcdLines));
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
		
		var coverSize = new Scale.with_range(Orientation.HORIZONTAL, 0, 60, 5);
		coverSize.set_value(App.settings.main.album_detail_cover_percent);
		coverSize.width_request = 260;
		coverSize.value_pos = PositionType.RIGHT;
		coverSize.format_value.connect((v) => ((int)v == 0) ? _("hidden") : "%d %%".printf((int)v));
		coverSize.value_changed.connect(() => { App.settings.main.album_detail_cover_percent = (int)coverSize.get_value(); });
		var coverBox = labelled(_("Size of the cover in the unfolded album:"), coverSize);
		var coverHint = new Label(_("Share of the band's width; 0 shows no cover"));
		coverHint.get_style_context().add_class("dim-label");
		coverHint.xalign = 0.0f;
		add_row(coverBox);
		add_row(coverHint);
		
		add_heading(_("Missing Album Art"));
		var download = add_check(_("Download missing album art from the internet (MusicBrainz, Apple Music)"), App.settings.main.download_covers);
		download.toggled.connect(() => {
			App.settings.main.download_covers = download.active;
			if (download.active)
				App.covers.fetch_remaining_album_art();
		});
	}
}

/** Credits, version and the services BeatBox talks to */
public class BeatBox.AboutPreferences : SimplePreferences {
	public override string title { get { return _("About"); } }
	
	public AboutPreferences() {
		var top = new Box(Orientation.HORIZONTAL, 14);
		top.pack_start(new Image.from_pixbuf(App.icons.BEATBOX.render(IconSize.DIALOG, null)), false, false, 0);
		var name = new Label("");
		name.xalign = 0.0f;
		name.set_markup("<span size='x-large' weight='bold'>BeatBox</span>\n" + Markup.escape_text(_("Version %s").printf(Build.VERSION))
		                + "\n" + Markup.escape_text(_("A music player with the look of iTunes 7.")));
		top.pack_start(name, false, false, 0);
		content.pack_start(top, false, false, 0);
		
		add_heading(_("Authors"));
		add_row(text("Scott Ringwelski\nVictor Eduardo M."));
		add_heading(_("Artwork"));
		add_row(text("Scott Ringwelski\nDaniel Foré"));
		add_heading(_("2026 update"));
		add_row(text(_("Ported to GTK 3, GStreamer 1.0 and libsoup 3, with the iTunes look, Cover Flow, the inline cover grid, internet radio and podcast directories, online album art and skins.")));
		
		add_heading(_("Services"));
		add_row(text(_("Internet radio stations: %s").printf(link("https://www.radio-browser.info", "radio-browser.info"))
		             + "\n" + _("Podcasts: %s").printf(link("https://podcasts.apple.com", "Apple Podcasts"))
		             + "\n" + _("Album art: %s, with %s as fallback").printf(link("https://musicbrainz.org", "MusicBrainz") + " / " + link("https://coverartarchive.org", "Cover Art Archive"), link("https://music.apple.com", "Apple Music"))
		             + "\n" + _("Scrobbling: %s").printf(link("https://www.last.fm", "Last.fm")), true));
		
		add_heading(_("License"));
		add_row(text(_("Free software under the %s.").printf(link("https://www.gnu.org/licenses/gpl-3.0.html", _("GNU General Public License, version 3")))
		             + "\n" + link("https://launchpad.net/beat-box", "launchpad.net/beat-box"), true));
	}
	
	static string link(string url, string label) {
		return "<a href=\"%s\">%s</a>".printf(url, Markup.escape_text(label));
	}
	
	static Label text(string s, bool markup = false) {
		var label = new Label("");
		label.xalign = 0.0f;
		label.wrap = true;
		label.max_width_chars = 64;
		if (markup)
			label.set_markup(s);
		else
			label.label = s;
		return label;
	}
}
