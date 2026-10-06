/*-
 * Copyright (c) 2011-2012 BeatBox Developers
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
 *
 * Authored by: Scott Ringwelski <sgringwe@mtu.edu>
 *              Victor Eduardo <victoreduardm@gmail.com>
 */


public static int main (string[] args) {
	// The desktop shell matches windows to <application id>.desktop through this name
	Environment.set_prgname ("net.launchpad.beatbox");
	var context = new OptionContext ("- BeatBox help page.");
	//context.add_main_entries (Beatbox.get_option_group (), "beatbox");
	context.add_group (Gtk.get_option_group (true));
	context.add_group (Gst.init_get_option_group ());

	try {
		context.parse (ref args);
	}
	catch (Error err) {
		warning ("Error parsing arguments: %s", err.message);
	}

	Gtk.init(ref args);

	try {
		Gst.init_check (ref args);
	}
	catch (Error err) {
		error ("Could not init GStreamer: %s", err.message);
	}
  
    // Init internationalization support before anything else
    string package_name = Build.GETTEXT_PACKAGE;
    string langpack_dir = Path.build_filename (Build.DATADIR, "locale");
    // Started from the build tree: use the translations built next to the program
    // (build/po/<language>/LC_MESSAGES), which may be newer than the installed ones
    try {
        var exe_dir = Path.get_dirname (FileUtils.read_link ("/proc/self/exe"));
        if (FileUtils.test (Path.build_filename (exe_dir, "build.ninja"), FileTest.EXISTS))
            langpack_dir = Path.build_filename (exe_dir, "po");
        // portable bundle (the release tarball): translations in ./locale
        else if (FileUtils.test (Path.build_filename (exe_dir, "locale"), FileTest.IS_DIR))
            langpack_dir = Path.build_filename (exe_dir, "locale");
        // installed anywhere (an AppImage, another prefix): <prefix>/bin and <prefix>/share/locale
        else if (FileUtils.test (Path.build_filename (exe_dir, "..", "share", "locale", "es", "LC_MESSAGES", package_name + ".mo"), FileTest.EXISTS))
            langpack_dir = Path.build_filename (Path.get_dirname (exe_dir), "share", "locale");
    } catch (FileError err) {}
    Intl.setlocale (LocaleCategory.ALL, "");
    BeatBox.App.locale_dir = langpack_dir;
    Intl.bindtextdomain (package_name, langpack_dir);
    Intl.bind_textdomain_codeset (package_name, "UTF-8");
    Intl.textdomain (package_name);
  
	var app = new BeatBox.App ();
	return app.run (args);
}


/**
 * Application class
 */

public class BeatBox.App : Gtk.Application {
	public static BeatBox.LibraryInterface library { get; private set; }
	public static BeatBox.PlaylistInterface playlists { get; private set; }
	public static BeatBox.PodcastInterface podcasts { get; private set; }
	public static BeatBox.DatabaseInterface database { get; private set; }
	public static BeatBox.LibraryWindowInterface window { get; private set; }
	public static BeatBox.FileInterface files { get; private set; }
	public static BeatBox.OperationsInterface operations { get; private set; }
	public static BeatBox.PlaybackInterface playback { get; private set; }
	public static BeatBox.CoverInterface covers { get; private set; }
	public static BeatBox.ActionsInterface actions { get; private set; }
	public static BeatBox.IconsInterface icons { get; private set; }
	public static BeatBox.InfoInterface info { get; private set; }
	public static BeatBox.Settings settings { get; private set; }
	public static BeatBox.DeviceInterface devices { get; private set; }
	public static BeatBox.PluginManager plugins { get; private set; }
	static FolderWatcher folder_watcher;

	/*private const OptionEntry[] app_options = {
		{ "debug", 'd', 0, OptionArg.NONE, ref Options.debug, N_("Enable debug logging"), null },
		{ "no-plugins", 'n', 0, OptionArg.NONE, ref Options.disable_plugins, N_("Disable plugins"), null},
		{ null }
	};*/

	construct {
		// This allows opening files. See the open() method below.
		flags |= ApplicationFlags.HANDLES_OPEN;

		application_id = "net.launchpad.beatbox";
	}

	/** Where the translations are read from (see main) */
	public static string locale_dir;
	
	static Gtk.CssProvider marker_css = new Gtk.CssProvider ();
	
	/** Applies the shape and size of the position marker and the width of its track (Preferences › Appearance) */
	public static void apply_lcd_style () {
		int size = settings.main.lcd_marker_size.clamp (6, 28);
		string shape = settings.main.lcd_marker_shape;
		if (!(shape in new string[] { "diamond", "circle", "cup", "nyan" }))
			shape = "diamond";
		int track = settings.main.lcd_track_width.clamp (2, 16);
		try {
			if (shape == "nyan") {
				// whole pixels of the 23×13 cat and its 6×7 rainbow (data/nyan.svg, rainbow.svg), so they stay
				// crisp; the trail sets the track's width, and TimeScale swaps the frames (class nyan-b)
				int k = size < 20 ? 1 : 2;
				marker_css.load_from_data (
					(".lcd scale trough, .lcd scale highlight { min-height: %dpx; border-radius: 0; }" +
					 ".lcd scale highlight, .lcd scale slider { transition: none; }" + // the theme's would slide between frames
					 ".lcd scale highlight { background-color: transparent; background-size: auto 100%%; background-repeat: repeat-x;" +
					 " background-image: url(\"resource:///net/launchpad/beatbox/rainbow.svg\"); }" +
					 ".lcd scale.nyan-b highlight { background-position: %dpx 0; }" +
					 ".lcd scale slider { min-width: %dpx; min-height: %dpx; margin: %dpx %dpx %dpx;" +
					 " background-image: url(\"resource:///net/launchpad/beatbox/nyan.svg\"); background-size: 200%% 100%%; background-position: 0 0; }" +
					 ".lcd scale.nyan-b slider { background-position: 100%% 0; }")
					.printf (7 * k, 3 * k, 23 * k, 13 * k, -2 * k, -(23 * k - 8) / 2, -4 * k)); // the trail leaves the body's middle
				return;
			}
			marker_css.load_from_data (
				(".lcd scale trough, .lcd scale highlight { min-height: %dpx; }" +
				 ".lcd scale slider { min-width: %dpx; min-height: %dpx; margin: %dpx %dpx;" +
				 " background-image: url(\"resource:///net/launchpad/beatbox/%s.svg\"); }")
				.printf (track, size, size, -(size - track + 2) / 2, -(size - 8) / 2, shape));
		} catch (Error err) {
			warning ("Could not restyle the position bar: %s", err.message);
		}
	}
	
	public App () {
		// Create settings
		settings = new BeatBox.Settings ();
	}

	/*public static OptionEntry[] get_option_group () {
		return app_options;
	}*/

	public override void open (File[] files, string hint) {
		if(files == null || files.length == 0) {
			return;
		}
		
		// Activate, then play files: new ones are imported (the import plays the
		// first); a song already in the library is played right away
		this.activate ();
		var to_add = new Gee.LinkedList<File> ();
		Media? known = null;
		for (int i = 0; i < files.length; i++) {
			var file = files[i];
			if (file == null)
				continue;
			var m = library.media_from_file (file.get_uri ());
			if (m != null) {
				if (known == null)
					known = m;
			} else {
				to_add.add (file);
				message ("Adding file %s", file.get_uri());
			}
		}
		
		if(to_add.size > 0) {
			library.song_library.add_files(to_add, true);
		} else if (known != null) {
			playback.play_media (known, false);
			if (!playback.playing)
				playback.play ();
		}
	}

	protected override void activate () {
		if (window != null) {
			window.present ();
			return;
		}
		
		Logger.initialize (); // the [INFO hh:mm:ss] log format
		
		Skins.apply (settings.main.skin); // base look at APPLICATION + 1, optional skin at + 2
		Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), marker_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 3);
		apply_lcd_style ();
		
		Gtk.IconTheme.get_default ().add_resource_path ("/net/launchpad/beatbox/icons");
		icons = new Icons();
		database = new DataBaseManager();
		operations = new OperationsManager();
		playback = new PlaybackManager();
		info = new Info();
		actions = new Actions();
		devices = new DeviceManager();
		files = new FileOperator();
		covers = new CoverManager();
		library = new LibraryManager();
		playlists = new PlaylistManager();
		((LibraryManager)library).init_default_libraries();
		folder_watcher = new FolderWatcher();
		((PlaylistManager)playlists).load_playlists_from_db();
		((LibraryManager)library).add_default_smart_playlists();
		window = new LibraryWindow(this);
		podcasts = new PodcastManager();
		
		window.set_application(this); // before the window shows, so it carries the application id
		((LibraryWindow)window).build_ui ();
		Launcher.ensure ();
		
		((CoverManager)covers).setup_signals();
		plugins = new PluginManager(new PluginHost(playback, library, window, settings));
		
		// Quit cleanly (saving state) on logout/kill as well
		foreach (int sig in new int[] { Posix.Signal.TERM, Posix.Signal.INT }) {
			Unix.signal_add (sig, () => { ((Gtk.Window)window).destroy (); return false; });
		}
		
		// Start playing the last playing song. By waiting 1 second, we
		// give everything time to finish initializing and avoid sending
		// out media_updated signals during startup.
		Timeout.add(500, () => {
			((PlaybackManager)playback).load_and_play_last_playing(); return false;
		});
		
		// After everything settles down, load the covers that have been saved.
		Idle.add(() => {
			covers.fetch_image_cache_async.begin (); return false;
		});
		
		// After 10 seconds, check for new podcasts
		Timeout.add(10000, () => {
			podcasts.find_new_podcasts();

			return false;
		});
	}
}

