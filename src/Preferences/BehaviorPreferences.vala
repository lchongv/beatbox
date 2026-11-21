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
	protected Box? target = null; // where add_heading and add_row put things: content when null

	Box rows { get { return target ?? content; } }

	protected void add_heading(string text) {
		var label = new Label("");
		label.xalign = 0.0f;
		label.set_markup("<b>" + Markup.escape_text(text) + "</b>");
		rows.append(label);
	}

	protected void add_row(Widget row) {
		rows.append(UI.wrap_alignment(row, 0, 0, 0, 10));
	}

	/** What add_heading and add_row put from here to end_advanced shows only with
	 *  "Show advanced settings" on (the check at the bottom of the Preferences window) */
	protected void begin_advanced() {
		var box = new Box(Orientation.VERTICAL, 10);
		App.settings.main.bind_property("show-advanced-preferences", box, "visible", BindingFlags.SYNC_CREATE);
		content.append(box);
		target = box;
	}

	protected void end_advanced() {
		target = null;
	}

	protected CheckButton add_check(string text, bool active) {
		var check = new CheckButton.with_label(text);
		check.active = active;
		add_row(check);
		return check;
	}

	protected static Box labelled(string text, Widget w, string? after = null) {
		var box = new Box(Orientation.HORIZONTAL, 8);
		box.append(new Label(text));
		box.append(w);
		if (after != null)
			box.append(new Label(after));
		return box;
	}

	public void save() {
	}

	public void cancel() {
	}
}

/** How the library folder is managed */
public class BeatBox.LibraryPreferences : SimplePreferences {
	public override string title { get { return _("Library"); } }
	Box libraries = new Box(Orientation.VERTICAL, 6);

	public LibraryPreferences() {
		add_heading(_("Libraries"));
		add_row(libraries);
		fill_libraries();
		add_heading(_("Library Management"));
		var watch = add_check(_("Import songs that appear in the music folder"), App.settings.main.watch_music_folder);
		watch.toggled.connect(() => { App.settings.main.watch_music_folder = watch.active; });
		var copy = add_check(_("Copy files to library folder when imported"), App.settings.main.copy_imported_music);
		begin_advanced();
		var organize = add_check(_("Keep media folders organized"), App.settings.main.update_folder_hierarchy);
		var write = add_check(_("Write metadata to file"), App.settings.main.write_metadata_to_file);
		end_advanced();
		organize.toggled.connect(() => { App.settings.main.update_folder_hierarchy = organize.active; });
		write.toggled.connect(() => { App.settings.main.write_metadata_to_file = write.active; });
		copy.toggled.connect(() => { App.settings.main.copy_imported_music = copy.active; });
	}

	void fill_libraries() {
		UI.clear(libraries);
		foreach (var id in LibrarySwitcher.all_ids()) {
			var row = new Box(Orientation.HORIZONTAL, 8);
			var name = new Label("");
			string text = Markup.escape_text(LibrarySwitcher.name_of(id));
			name.set_markup(id == App.settings.main.library ? "<b>%s</b> %s".printf(text, Markup.escape_text(_("(open)"))) : text);
			var folder = new Label(Libraries.option(id, "music-folder"));
			folder.add_css_class("dim-label");
			folder.ellipsize = Pango.EllipsizeMode.START;
			folder.xalign = 0;
			folder.hexpand = true;
			row.append(name);
			row.append(folder);
			var rename = new Button.with_label(_("Rename…"));
			rename.clicked.connect(() => ask_rename.begin(id));
			row.append(rename);
			if (id != "" && id != App.settings.main.library) { // never the main or the open one
				var remove = new Button.with_label(_("Remove…"));
				remove.clicked.connect(() => ask_remove.begin(id));
				row.append(remove);
			}
			libraries.append(row);
		}
	}

	async void ask_rename(string id) {
		var dialog = new ButtonDialog(_("Rename Library"), UI.window_of(libraries));
		dialog.add_button(_("Cancel"), ButtonDialog.CANCEL);
		dialog.add_button(_("Rename"), ButtonDialog.OK);
		var entry = new Entry() { text = LibrarySwitcher.name_of(id), activates_default = true,
		                          margin_top = 12, margin_bottom = 12, margin_start = 12, margin_end = 12 };
		dialog.content_area.append(entry);
		dialog.set_default_response(ButtonDialog.OK);
		var answer = yield dialog.run();
		bool rename = answer == ButtonDialog.OK && entry.text.strip() != "";
		string name = entry.text.strip();
		dialog.destroy();
		if (rename) {
			App.libraries.rename(id, name);
			fill_libraries();
		}
	}

	async void ask_remove(string id) {
		bool remove = yield UI.confirm(UI.window_of(libraries), _("Remove the library “%s”?").printf(LibrarySwitcher.name_of(id)),
		                               _("Its songs, play counts and playlists are removed from BeatBox; the music files stay where they are."),
		                               _("Remove"));
		if (remove) {
			App.libraries.remove(id);
			fill_libraries();
		}
	}
}

/** ReplayGain and crossfade */
public class BeatBox.PlaybackPreferences : SimplePreferences {
	public override string title { get { return _("Playback"); } }

	public PlaybackPreferences() {
		add_heading(_("Playback"));
		var crossfade = new SpinButton.with_range(0, 12, 1);
		crossfade.value = App.settings.main.crossfade_seconds;
		crossfade.value_changed.connect(() => { App.settings.main.crossfade_seconds = (int)crossfade.value; });
		add_row(labelled(_("Crossfade between songs:"), crossfade, _("seconds (0: none, songs follow without a gap)")));

		begin_advanced();
		var rg = new ChoiceBox();
		rg.append("0", _("Off"));
		rg.append("1", _("Per song"));
		rg.append("2", _("Per album"));
		rg.active_id = App.settings.equalizer.replaygain.to_string();
		rg.changed.connect(() => { App.settings.equalizer.replaygain = int.parse(rg.active_id); });
		add_row(labelled(_("Volume normalization (ReplayGain):"), rg, _("from the next song")));
		end_advanced();
	}
}

/** Recording radio stations (StreamRecorder) */
public class BeatBox.RecordingPreferences : SimplePreferences {
	public override string title { get { return _("Recording"); } }
	Button recordings; // GTK4: shows the folder; a click opens a folder chooser

	public RecordingPreferences() {
		add_heading(_("Recording"));
		recordings = new Button();
		var folder = App.settings.main.recordings_path();
		DirUtils.create_with_parents(folder, 0755); // the chooser can only show a folder that exists
		show_folder(folder);
		recordings.clicked.connect(() => choose_folder.begin());
		add_row(labelled(_("Save recordings of radio stations in:"), recordings));
		var minutes = new SpinButton.with_range(1, 1440, 1);
		minutes.value = App.settings.main.recording_minutes;
		minutes.value_changed.connect(() => { App.settings.main.recording_minutes = (int)minutes.value; });
		add_row(labelled(_("Start a new file every:"), minutes, _("minutes")));
		var hint = new Label(_("Right click a station in the radio grid to record it. Needs streamripper."));
		hint.xalign = 0.0f;
		hint.add_css_class("dim-label");
		add_row(hint);
	}

	void show_folder(string path) {
		recordings.label = GLib.Path.get_basename(path);
	}

	async void choose_folder() {
		var folder = yield UI.choose_folder(UI.window_of(recordings), _("Recordings Folder"),
		                                    File.new_for_path(App.settings.main.recordings_path()));
		if (folder != null) {
			string chosen = folder.get_path();
			App.settings.main.recordings_folder = chosen;
			show_folder(chosen);
		}
	}
}

/** Skins */
public class BeatBox.AppearancePreferences : SimplePreferences {
	public override string title { get { return _("Appearance"); } }

	public AppearancePreferences() {
		// Skins (plugins: folders in ~/.local/share/beatbox/skins)
		add_heading(_("Skin"));
		var skinChooser = new ChoiceBox();
		var preview = new Image();
		preview.halign = Align.START;
		var skins = Skins.available();
		foreach (var skin in skins)
			skinChooser.append(skin.id, skin.name);
		if (!skinChooser.select_id(App.settings.main.skin))
			skinChooser.active_id = Skins.DEFAULT;
		var editCss = new Button.with_label(_("Edit CSS…"));
		editCss.clicked.connect(() => {
			foreach (var skin in skins) {
				if (skin.id != skinChooser.active_id)
					continue;
				var editor = new SkinEditor(UI.window_of(editCss), skin);
				skinChooser.sensitive = editCss.sensitive = false; // the preview goes over this skin
				editor.saved.connect((id) => {
					if (id == skinChooser.active_id)
						return;
					skins = Skins.available(); // a new copy
					skinChooser.remove_all();
					foreach (var s in skins)
						skinChooser.append(s.id, s.name);
					skinChooser.active_id = id;
				});
				editor.close_request.connect(() => { skinChooser.sensitive = editCss.sensitive = true; return false; });
				editor.present();
			}
		});
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
		skinBox.append(editCss);
		skinBox.append(openSkins);
		add_row(skinBox);
		add_row(preview);
		skinChooser.changed.connect(() => {
			string id = skinChooser.active_id ?? Skins.DEFAULT;
			App.settings.main.skin = id;
			Skins.apply(id); // live preview
			preview.clear();
			foreach (var skin in skins) {
				if (skin.id != id || skin.preview == null)
					continue;
				try {
					UI.show_pixbuf(preview, new Gdk.Pixbuf.from_stream_at_scale(skin.preview.read(), 440, -1, true));
				} catch (Error err) {
					warning("Could not load the preview of %s: %s", id, err.message);
				}
			}
		});
		skinChooser.changed();

		begin_advanced();
		var aqua = add_check(_("Mac OS X Tiger scrollbars (applies on restart)"), App.settings.main.aqua_scrollbars);
		aqua.toggled.connect(() => { App.settings.main.aqua_scrollbars = aqua.active; });
		end_advanced();
	}
}

/** What the LCD shows and its position bar */
public class BeatBox.LcdPreferences : SimplePreferences {
	public override string title { get { return _("LCD"); } }

	public LcdPreferences() {
		add_heading(_("Display"));
		var lcdLines = new ChoiceBox();
		lcdLines.append("two", _("Two lines, artist and album taking turns"));
		lcdLines.append("three", _("Three lines, synced lyrics on the third"));
		lcdLines.append("one", _("One line"));
		lcdLines.active_id = !App.settings.main.lcd_two_lines ? "one" : App.settings.main.lcd_three_lines ? "three" : "two";
		lcdLines.changed.connect(() => {
			App.settings.main.lcd_three_lines = (lcdLines.active_id == "three");
			App.settings.main.lcd_two_lines = (lcdLines.active_id != "one");
		});
		add_row(labelled(_("Song information in the LCD:"), lcdLines));

		var lyrics = add_check(_("Show synced lyrics when available (lrclib.net)"), App.settings.main.lcd_lyrics);
		lyrics.toggled.connect(() => { App.settings.main.lcd_lyrics = lyrics.active; });

		var lcdCover = add_check(_("Show the album cover at the left edge of the LCD"), App.settings.main.lcd_show_cover);
		lcdCover.toggled.connect(() => { App.settings.main.lcd_show_cover = lcdCover.active; });

		var interval = new SpinButton.with_range(1, 60, 1);
		interval.value = App.settings.main.lcd_alternate_seconds;
		add_row(labelled(_("Switch between artist and album every:"), interval, _("seconds")));
		interval.value_changed.connect(() => { App.settings.main.lcd_alternate_seconds = (int)interval.value; });

		var transition = new SpinButton.with_range(0, 3000, 100);
		transition.value = App.settings.main.lcd_transition_ms;
		add_row(labelled(_("Duration of the slide:"), transition, _("milliseconds")));
		transition.value_changed.connect(() => { App.settings.main.lcd_transition_ms = (int)transition.value; });

		add_heading(_("Position bar"));
		var trackWidth = new SpinButton.with_range(2, 16, 1);
		trackWidth.value = App.settings.main.lcd_track_width;
		add_row(labelled(_("Width of the track:"), trackWidth, _("pixels")));
		var markerShape = new ChoiceBox();
		markerShape.append("diamond", _("Diamond"));
		markerShape.append("circle", _("Circle"));
		markerShape.append("cup", _("Cup"));
		markerShape.append("nyan", _("Nyan cat"));
		if (!markerShape.select_id(App.settings.main.lcd_marker_shape))
			markerShape.active_id = "diamond";
		add_row(labelled(_("Shape of the position marker:"), markerShape));
		markerShape.changed.connect(() => {
			App.settings.main.lcd_marker_shape = markerShape.active_id;
			App.apply_lcd_style(); // live preview
		});
		var markerSize = new SpinButton.with_range(6, 28, 1);
		markerSize.value = App.settings.main.lcd_marker_size;
		add_row(labelled(_("Size of the position marker:"), markerSize, _("pixels")));
		trackWidth.value_changed.connect(() => {
			App.settings.main.lcd_track_width = (int)trackWidth.value;
			App.apply_lcd_style(); // live preview
		});
		markerSize.value_changed.connect(() => {
			App.settings.main.lcd_marker_size = (int)markerSize.value;
			App.apply_lcd_style();
		});
	}
}

/** The compact window */
public class BeatBox.MiniPlayerPreferences : SimplePreferences {
	public override string title { get { return _("Mini Player"); } }

	public MiniPlayerPreferences() {
		add_heading(_("Mini Player"));
		// GTK 4 cannot keep a window above the others (GTK3 could, on X11 only): the window
		// menu offers it. (The text, kept for its translations, still says Wayland.)
		var hint = new Label(_("On Wayland the desktop keeps windows on top: right-click the toolbar and choose “Always on Top”."));
		hint.add_css_class("dim-label");
		hint.xalign = 0.0f;
		hint.wrap = true;
		hint.max_width_chars = 60;
		add_row(hint);
	}
}

/** Turning the plugins found on disk on and off, and installing more (see docs/plugins.md) */
public class BeatBox.PluginsPreferences : SimplePreferences {
	public override string title { get { return _("Plugins"); } }

	Box list = new Box(Orientation.VERTICAL, 10);
	Label none = new Label(_("No plugins are installed."));

	public PluginsPreferences() {
		add_heading(_("Plugins"));
		none.add_css_class("dim-label");
		none.xalign = 0.0f;
		list.append(none);
		add_row(list);
		foreach(var p in App.plugins.plugins)
			add_plugin(p);
		none.visible = App.plugins.plugins.size == 0;

		var install = new Button.with_label(_("Install Plugin…"));
		install.clicked.connect(choose_plugin);
		var row = new Box(Orientation.HORIZONTAL, 0); // add_row stretches what it gets
		row.append(install);
		add_row(row);
	}

	void add_plugin(PluginInfo p) {
		var check = new CheckButton.with_label(p.name);
		check.active = p.active;
		check.toggled.connect(() => {
			App.plugins.set_enabled(p, check.active);
			if(check.active != p.active) // it couldn't be loaded
				check.active = p.active;
		});
		list.append(check);
		if(p.description != "") {
			var text = new Label(p.description);
			text.add_css_class("dim-label");
			text.xalign = 0.0f;
			text.wrap = true;
			text.max_width_chars = 60;
			text.margin_start = 24;
			list.append(text);
		}
		none.hide();
	}

	void choose_plugin() {
		install_plugin.begin();
	}

	async void install_plugin() {
		var filter = new FileFilter();
		filter.set_filter_name(_("BeatBox plugins (*.plugin)"));
		filter.add_pattern("*.plugin");
		var file = yield UI.open_file(UI.window_of(list), _("Install Plugin"), { filter });
		if (file != null) {
			try {
				var p = App.plugins.install(file);
				if(p != null)
					add_plugin(p);
				else
					App.window.doAlert(_("Plugin updated"), _("A plugin with the same name is in use: restart BeatBox to use the one just installed."));
			} catch (Error err) {
				App.window.doAlert(_("Could not install the plugin"), err.message);
			}
		}
	}
}

/** The cover grid and where album art comes from */
public class BeatBox.CoverPreferences : SimplePreferences {
	public override string title { get { return _("Album Art"); } }

	/** One chooser per column (the first is always there, the others can be "none"): a criterion is used once */
	void add_browser_column_choosers() {
		var chosen = new string[4];
		int n = 0;
		foreach(var c in BrowserCriterion.parse(App.settings.main.column_browser_columns))
			chosen[n++] = c.id;
		for(int i = n; i < 4; i++)
			chosen[i] = "";
		var combos = new ChoiceBox[4];
		bool updating = false;
		
		for(int i = 0; i < 4; i++) {
			int index = i;
			var combo = new ChoiceBox();
			if(i > 0)
				combo.append("", _("(none)"));
			foreach(var c in BrowserCriterion.all())
				combo.append(c.id, c.label);
			combo.active_id = chosen[i];
			combos[i] = combo;
			combo.changed.connect(() => {
				if(updating)
					return;
				updating = true;
				string old = chosen[index];
				string picked = combo.active_id ?? "";
				// a criterion already in another column goes there in exchange
				for(int j = 0; j < 4; j++) {
					if(j != index && picked != "" && chosen[j] == picked) {
						if(old == "" && j == 0)
							old = chosen[0]; // the first column can't be left empty
						chosen[j] = old;
						combos[j].active_id = old;
					}
				}
				chosen[index] = picked;
				// no gaps: the columns are the filled choosers in order
				var ids = new string[0];
				foreach(var id in chosen) {
					if(id != "")
						ids += id;
				}
				App.settings.main.column_browser_columns = string.joinv(",", ids);
				updating = false;
			});
			string[] names = { _("First column:"), _("Second column:"), _("Third column:"), _("Fourth column:") };
			add_row(labelled(names[i], combo));
		}
	}

	public CoverPreferences() {
		add_heading(_("Column Browser"));
		var browser = add_check(_("Show the Genre, Artist and Album boxes above the song list"), App.settings.main.show_column_browser);
		browser.toggled.connect(() => { App.settings.main.show_column_browser = browser.active; });
		begin_advanced();
		add_browser_column_choosers();
		end_advanced();

		add_heading(_("Cover Grid"));
		var clickMode = new ChoiceBox();
		clickMode.append("inline", _("Unfold it inline, under its row"));
		clickMode.append("popup", _("Open it in a popup window"));
		clickMode.active_id = App.settings.main.album_grid_inline ? "inline" : "popup";
		clickMode.changed.connect(() => { App.settings.main.album_grid_inline = (clickMode.active_id == "inline"); });
		add_row(labelled(_("Clicking an album in the cover grid:"), clickMode));

		var coverSize = new Scale.with_range(Orientation.HORIZONTAL, 0, 60, 5);
		coverSize.set_value(App.settings.main.album_detail_cover_percent);
		coverSize.width_request = 260;
		coverSize.value_pos = PositionType.RIGHT;
		coverSize.set_format_value_func((s, v) => ((int)v == 0) ? _("hidden") : "%d %%".printf((int)v));
		coverSize.value_changed.connect(() => { App.settings.main.album_detail_cover_percent = (int)coverSize.get_value(); });
		var coverBox = labelled(_("Size of the cover in the unfolded album:"), coverSize);
		var coverHint = new Label(_("Share of the band's width; 0 shows no cover"));
		coverHint.add_css_class("dim-label");
		coverHint.xalign = 0.0f;
		begin_advanced();
		add_row(coverBox);
		add_row(coverHint);
		end_advanced();

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
		var logo = new Image();
		UI.show_pixbuf(logo, App.icons.BEATBOX.render(null, null, 112));
		top.append(logo);
		var name = new Label("");
		name.xalign = 0.0f;
		name.set_markup("<span size='x-large' weight='bold'>BeatBox</span>\n" + Markup.escape_text(_("Version %s").printf(Build.VERSION))
		                + "\n" + Markup.escape_text(_("A music player for your collection, podcasts and internet radio.")));
		top.append(name);
		content.append(top);

		add_heading(_("License"));
		add_row(text(_("Free software under the %s.").printf(link("https://www.gnu.org/licenses/gpl-3.0.html", _("GNU General Public License, version 3")))
		             + "\n" + link("https://launchpad.net/beat-box", "launchpad.net/beat-box"), true));

		add_heading(_("Credits"));
		content.append(new Credits());
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
