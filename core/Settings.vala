/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
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

/**
 * Options live in ~/.config/beatbox/beatbox.conf (an ini file), so they don't
 * depend on where the program was installed or started from.
 *
 * Every property of a ConfigSection is an option: it is read from the file when
 * the section is created and written back, a moment later, when it changes. The
 * property name is the key, with dashes (window_width is window-width).
 */
public abstract class BeatBox.ConfigSection : Object {
    static KeyFile? file = null;
    static string path = "";
    static bool first_run = false;  // no file yet: import what older versions kept in GSettings
    static uint save_id = 0;
    static string library_group = ""; // "library <id>" while a library besides the main one is open

    string group = "";
    string[] library_keys = {};       // the options that belong to the open library

    public static string config_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "beatbox", "beatbox.conf");
    }

    /** The options file, read the first time it is needed (also by Libraries) */
    public static unowned KeyFile keyfile () {
        if (file == null) {
            path = config_path ();
            file = new KeyFile ();
            first_run = !FileUtils.test (path, FileTest.EXISTS);
            try {
                file.load_from_file (path, KeyFileFlags.NONE);
            } catch (Error err) {
                if (!first_run)
                    warning ("Could not read %s, using the defaults: %s", path, err.message);
            }
            string id = "";
            try {
                id = file.get_string ("settings", "library");
            } catch (Error err) {} // the main library
            if (id != "" && !file.has_group (Libraries.group (id))) {
                warning ("The library %s has no options in %s: opening the main library", id, path);
                id = "";
            }
            library_group = (id != "") ? Libraries.group (id) : "";
        }
        return file;
    }

    /** Id of the open library: "" for the main one */
    public static string open_library () {
        keyfile ();
        return (library_group != "") ? library_group.substring (Libraries.group ("").length) : "";
    }

    /** Write pending changes now (called before exiting) */
    public static void flush () {
        if (save_id != 0) {
            Source.remove (save_id);
            save_id = 0;
        }
        if (file == null)
            return;
        try {
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
            FileUtils.set_contents (path, file.to_data ()); // atomic: written aside, then renamed
        } catch (Error err) {
            warning ("Could not save the options to %s: %s", path, err.message);
        }
    }

    public static void schedule_save () {
        if (save_id == 0)
            save_id = Timeout.add (400, () => { save_id = 0; flush (); return Source.REMOVE; });
    }

    /** Call at the end of the subclass constructor, once the defaults are set. The options named in
     *  library_keys (with dashes) belong to the open library: another library than the main one
     *  keeps them in its own group */
    protected void init_config (string group, string old_schema, string[] library_keys = {}) {
        this.group = group;
        this.library_keys = library_keys;
        keyfile ();

        SettingsSchema? old = null;
        if (first_run && SettingsSchemaSource.get_default () != null)
            old = SettingsSchemaSource.get_default ().lookup (old_schema, true);

        bool missing = false;
        var klass = (ObjectClass) get_type ().class_ref ();
        foreach (var pspec in klass.list_properties ()) {
            try {
                var g = group_of (pspec.name);
                if (file.has_group (g) && file.has_key (g, pspec.name)) {
                    read_from_file (pspec);
                } else {
                    missing = true;
                    if (old != null && old.has_key (pspec.name))
                        import_old_value (old, pspec);
                }
            } catch (Error err) {
                warning ("Ignoring option %s/%s: %s", group, pspec.name, err.message);
            }
            store (pspec); // the file lists every option, with its current value
        }

        notify.connect ((pspec) => {
            store (pspec);
            schedule_save ();
        });
        if (missing)
            schedule_save (); // first run, or options added by an update
    }

    /** The group an option is kept in */
    string group_of (string key) {
        return (library_group != "" && key in library_keys) ? library_group : group;
    }

    void read_from_file (ParamSpec pspec) throws Error {
        var g = group_of (pspec.name);
        if (pspec is ParamSpecBoolean)
            set (pspec.name, file.get_boolean (g, pspec.name), null);
        else if (pspec is ParamSpecInt)
            set (pspec.name, file.get_integer (g, pspec.name), null);
        else if (pspec is ParamSpecEnum)
            set (pspec.name, file.get_integer (g, pspec.name), null);
        else if (pspec is ParamSpecString)
            set (pspec.name, file.get_string (g, pspec.name), null);
        else if (pspec.value_type == typeof (string[]))
            set (pspec.name, file.get_string_list (g, pspec.name), null);
    }

    /** Values the user had set in the GSettings of older versions */
    void import_old_value (SettingsSchema schema, ParamSpec pspec) {
        var settings = new GLib.Settings.full (schema, null, null);
        if (settings.get_user_value (pspec.name) == null)
            return; // still the default
        if (pspec is ParamSpecBoolean)
            set (pspec.name, settings.get_boolean (pspec.name), null);
        else if (pspec is ParamSpecInt)
            set (pspec.name, settings.get_int (pspec.name), null);
        else if (pspec is ParamSpecEnum)
            set (pspec.name, settings.get_enum (pspec.name), null);
        else if (pspec is ParamSpecString)
            set (pspec.name, settings.get_string (pspec.name), null);
        else if (pspec.value_type == typeof (string[]))
            set (pspec.name, settings.get_strv (pspec.name), null);
    }

    void store (ParamSpec pspec) {
        var v = Value (pspec.value_type);
        get_property (pspec.name, ref v);
        var g = group_of (pspec.name);
        if (pspec is ParamSpecBoolean)
            file.set_boolean (g, pspec.name, v.get_boolean ());
        else if (pspec is ParamSpecInt)
            file.set_integer (g, pspec.name, v.get_int ());
        else if (pspec is ParamSpecEnum)
            file.set_integer (g, pspec.name, v.get_enum ());
        else if (pspec is ParamSpecString)
            file.set_string (g, pspec.name, v.get_string () ?? "");
        else if (pspec.value_type == typeof (string[])) {
            string[] list = {};
            char** items = (char**) v.get_boxed ();
            for (int i = 0; items != null && items[i] != null; i++)
                list += ((string) items[i]).dup ();
            file.set_string_list (g, pspec.name, list);
        }
    }
}

public class BeatBox.Settings {

    public LastFM lastfm { get; set; }
    public SavedState saved_state { get; set; }
    public Settings main { get; set; }
    public Equalizer equalizer { get; set; }

    public Settings () {
        lastfm = new LastFM ();
        saved_state = new SavedState ();
        main = new Settings ();
        equalizer = new Equalizer ();
    }

    public string get_album_art_cache_dir () {
        return GLib.Path.build_path ("/", get_cache_dir (), "album-art");
    }

    public string get_cache_dir () {
        return GLib.Path.build_path ("/", Environment.get_user_cache_dir(), "beatbox");
    }

    public enum Position {
        AUTOMATIC = 0,
        LEFT      = 2,
        TOP       = 1
    }

    public enum WindowState {
        NORMAL = 0,
        MAXIMIZED = 1,
        FULLSCREEN = 2
    }
    
    public class LastFM : ConfigSection {

        public string session_key { get; set; }
        public bool is_subscriber { get; set; }
        public string username { get; set; }
        public string listenbrainz_token { get; set; }
        public string listenbrainz_user { get; set; }
        public string acoustid_key { get; set; }     // an application key from acoustid.org, for the editor's Identify
        
        public LastFM () {
            session_key = "";
            username = "";
            listenbrainz_token = "";
            listenbrainz_user = "";
            acoustid_key = "";
            init_config ("lastfm", "net.launchpad.beatbox.LastFM");
        }
    }
    
    public class SavedState : ConfigSection {

        public int window_width { get; set; }
        public int window_height { get; set; }
        public WindowState window_state { get; set; }
        public int sidebar_width { get; set; }
        public int more_width { get; set; }
        public bool more_visible { get; set; }
        public int view_mode { get; set; }
        public int miller_width { get; set; }
        public int miller_height { get; set; }
        public bool miller_columns_enabled { get; set; }
        public string[] music_miller_visible_columns { get; set; }
        public string[] generic_miller_visible_columns { get; set; }
        public Position miller_columns_position { get; set; }
        public string[] queue { get; set; }  // media ids, restored at startup
        public bool mini_player { get; set; } // the window was in mini player mode

        public SavedState () {
            window_width = 1100;
            window_height = 600;
            window_state = WindowState.NORMAL;
            sidebar_width = 200;
            more_width = 150;
            view_mode = 1;
            miller_width = 200;
            miller_height = 200;
            music_miller_visible_columns = { "2", "3", "4" };
            generic_miller_visible_columns = { "2" };
            miller_columns_position = Position.AUTOMATIC;
            queue = {};
            init_config ("savedstate", "net.launchpad.beatbox.SavedState", { "queue" });
        }
        
    }

    public class Settings : ConfigSection {

        public string music_mount_name { get; set; }
        public string music_folder { get; set; }
        public string library { get; set; }          // id of the open library, "" the main one (Libraries)
        public string library_name { get; set; }     // the open library's name ("" shows "Music")
        public int last_rowid { get; set; }          // highest media id given in any library (LibraryManager)
        public bool watch_music_folder { get; set; } // import songs that appear in it (FolderWatcher)
        public string[] shortcuts { get; set; }      // "id=accelerator" (Shortcuts), only once changed
        public string[] enabled_plugins { get; set; } // ids of the plugins turned on (Preferences › Plugins)
        public int crossfade_seconds { get; set; }   // 0: no crossfade (gapless)
        public string podcast_folder { get; set; }
        public bool update_folder_hierarchy { get; set; }
        public bool write_metadata_to_file { get; set; }
        public bool copy_imported_music { get; set; }
        public bool itunes7_sync { get; set; }       // share plays, ratings and options with itunes7 (ItunesSync)
        public bool download_new_podcasts { get; set; }
        public string recordings_folder { get; set; } // "": Recordings in the user's music folder (StreamRecorder)
        public int recording_minutes { get; set; }   // how long each recorded file is
        public int last_media_playing { get; set; }
        public int last_media_position { get; set; }
        public int shuffle_mode { get; set; }
        public int repeat_mode { get; set; }
        public string search_string { get; set; }

        // Appearance
        public string skin { get; set; }
        public bool lcd_two_lines { get; set; }
        public bool lcd_three_lines { get; set; }    // with lcd_two_lines: the synced lyrics get a third line
        public bool lcd_show_cover { get; set; }
        public bool mini_keep_above { get; set; }    // the mini player stays above other windows
        public bool lcd_lyrics { get; set; }         // synced lyrics from lrclib.net on the second (or third) line
        public int lcd_alternate_seconds { get; set; } // artist, then album, then artist...
        public int lcd_transition_ms { get; set; }   // second LCD line sliding up
        public int lcd_track_width { get; set; }     // px, the groove of the position bar
        public int lcd_marker_size { get; set; }     // px, the marker
        public string lcd_marker_shape { get; set; } // diamond, circle, cup or nyan (data/<shape>.svg)
        public bool lcd_total_time { get; set; }     // the right time shows the length instead of what remains (click it)
        public bool album_grid_inline { get; set; }
        public int album_detail_cover_percent { get; set; }
        public bool download_covers { get; set; }
        
        /** Where recordings go: the folder chosen, or Recordings in the user's music folder */
        public string recordings_path () {
            if (recordings_folder != "")
                return recordings_folder;
            return Path.build_filename (Environment.get_user_special_dir (UserDirectory.MUSIC) ?? Environment.get_home_dir (), "Recordings");
        }

        public Settings ()  {
            music_mount_name = "";
            music_folder = "";
            library = "";
            library_name = "";
            watch_music_folder = true;
            shortcuts = {};
            enabled_plugins = {};
            podcast_folder = "";
            recordings_folder = "";
            recording_minutes = 60;
            search_string = "";
            skin = "";
            lcd_two_lines = true;
            lcd_lyrics = true;
            lcd_alternate_seconds = 3;
            lcd_transition_ms = 600;
            lcd_track_width = 6;
            lcd_marker_size = 14;
            lcd_marker_shape = "diamond";
            album_grid_inline = true;
            album_detail_cover_percent = 25;
            download_covers = true;
            init_config ("settings", "net.launchpad.beatbox.Settings", {
                "library-name", "music-folder", "music-mount-name", "watch-music-folder",
                "last-media-playing", "last-media-position" });
            if (library != ConfigSection.open_library ())
                library = ConfigSection.open_library (); // it named a library that is gone
        }
    }

    public class Equalizer : ConfigSection {

        public bool equalizer_enabled { get; set; }
        public bool auto_switch_preset { get; set; }
        public string selected_preset { get; set; }
        public string[] custom_presets { get; set;}
        public string[] default_presets { get; set;}
        public int volume { get; set;}
        public int replaygain { get; set; } // 0 off, 1 track, 2 album (BeatBox.ReplayGain)
        public int preamp_db { get; set; }  // -12..0: lowered before the equalizer, so boosts don't clip
        public int compressor { get; set; } // 0..100: how much the loud parts are held down
        public int reverb { get; set; }     // 0..100: how much room there is around the sound
        public bool crossfeed { get; set; } // headphones: each ear hears a little of the other channel
        public int echo { get; set; }             // 0..100: repeats of the sound
        public int vocal_reduction { get; set; }  // 0..100: takes out what is in the middle (usually the voice)
        public int bass { get; set; }             // 0..100: harmonics that make the bass heard on small speakers
        public int exciter { get; set; }          // 0..100: adds brightness to the high frequencies
        public int stereo_width { get; set; }     // 0..100: spreads the stereo image
        public int saturation { get; set; }       // 0..100: warmth, a little distortion
        public int limiter { get; set; }          // 0..100: a ceiling for the peaks
        public int chorus { get; set; }           // 0..100: copies of the sound, slightly detuned
        public int flanger { get; set; }          // 0..100: a short sweeping delay, a jet-plane whoosh
        public int phaser { get; set; }           // 0..100: a sweeping notch filter
        public int echo_delay { get; set; }       // 50..1000 ms: time between repeats
        public int echo_feedback { get; set; }    // 0..100: how many repeats are heard, fading
        public int reverb_room { get; set; }      // 0..100: size of the simulated room
        public int reverb_damping { get; set; }   // 0..100: how much the highs fade in the room

        /** The neutral value of every effect: a preset is written over these */
        const string[] EFFECT_DEFAULTS = {
            "preamp_db=0", "compressor=0", "reverb=0", "crossfeed=0", "echo=0", "vocal_reduction=0",
            "bass=0", "exciter=0", "stereo_width=0", "saturation=0", "limiter=0", "chorus=0", "flanger=0",
            "phaser=0", "echo_delay=350", "echo_feedback=40", "reverb_room=50", "reverb_damping=20"
        };

        /** Effect presets: the name, then the effects that differ from EFFECT_DEFAULTS. The names are the
         *  keys; the window shows them translated */
        const string[] EFFECT_PRESETS = {
            "Concert hall|reverb=45,reverb_room=80,reverb_damping=35,echo=8,echo_delay=180,echo_feedback=25",
            "Headphones|crossfeed=1,bass=25,stereo_width=20",
            "Podcast|compressor=60,limiter=50,preamp_db=-3",
            "Warm|saturation=35,bass=20,compressor=15,reverb=10",
            "Space|flanger=35,phaser=20,echo=25,echo_delay=500,echo_feedback=55,reverb=30,reverb_room=90",
            "Vocal cut|vocal_reduction=70"
        };

        public string[] effect_preset_names () {
            string[] names = {};
            foreach (var preset in EFFECT_PRESETS)
                names += preset.split ("|", 2)[0];
            return names;
        }

        /** Sets every effect to its neutral value, then the preset's; an unknown name just resets them */
        public void apply_effect_preset (string name) {
            foreach (var pair in EFFECT_DEFAULTS)
                set_effect (pair);
            foreach (var preset in EFFECT_PRESETS) {
                var parts = preset.split ("|", 2);
                if (parts[0] == name)
                    foreach (var pair in parts[1].split (","))
                        set_effect (pair);
            }
        }

        void set_effect (string pair) {
            var kv = pair.split ("=", 2);
            int value = int.parse (kv[1]);
            if (kv[0] == "crossfeed")
                crossfeed = value == 1;
            else
                this.set (kv[0], value, null);
        }

        public Equalizer () {
            replaygain = 1;
            chorus = 0;
            flanger = 0;
            phaser = 0;
            echo_delay = 350;
            echo_feedback = 40;
            reverb_room = 50;
            reverb_damping = 20;
            preamp_db = 0;
            compressor = 0;
            reverb = 0;
            crossfeed = false;
            echo = 0;
            vocal_reduction = 0;
            bass = 0;
            exciter = 0;
            stereo_width = 0;
            saturation = 0;
            limiter = 0;
            auto_switch_preset = true;
            selected_preset = "";
            custom_presets = {};
            default_presets = {
                "Flat/0/0/0/0/0/0/0/0/0/0", "Classical/0/0/0/0/0/0/-40/-40/-40/-50",
                "Club/0/0/20/30/30/30/20/0/0/0", "Dance/50/35/10/0/0/-30/-40/-40/0/0",
                "Full Bass/70/70/70/40/20/-45/-50/-55/-55/-55", "Full Treble/-50/-50/-50/-25/15/55/80/80/80/80",
                "Full Bass + Treble/35/30/0/-40/-25/10/45/55/60/60", "Headphones/25/50/25/-20/0/-30/-40/-40/0/0",
                "Large Hall/50/50/30/30/0/-25/-25/-25/0/0", "Live/-25/0/20/25/30/30/20/15/15/10",
                "Party/35/35/0/0/0/0/0/0/35/35", "Pop/-10/25/35/40/25/-5/-15/-15/-10/-10",
                "Reggae/0/0/-5/-30/0/-35/-35/0/0/0", "Rock/40/25/-30/-40/-20/20/45/55/55/55",
                "Soft/25/10/-5/-15/-5/20/45/50/55/60", "Ska/-15/-25/-25/-5/20/30/45/50/55/50",
                "Soft Rock/20/20/10/-5/-25/-30/-20/-5/15/45", "Techno/40/30/0/-30/-25/0/40/50/50/45"
            };
            volume = 100;
            init_config ("equalizer", "net.launchpad.beatbox.Equalizer");
        }
        
        public Gee.Collection<BeatBox.EqualizerPreset> getCustomPresets () {

            var presets_data = new Gee.LinkedList<string> ();
            
            if (custom_presets != null) {
                for (int i = 0; i < custom_presets.length; i++) {
                    presets_data.add (custom_presets[i]);
                }
            }
            
            var rv = new Gee.LinkedList<BeatBox.EqualizerPreset>();
            
            foreach (var preset_str in presets_data) {
                var equalizer_preset = new BeatBox.EqualizerPreset.from_string (preset_str);
                if (equalizer_preset != null)
                    rv.add (equalizer_preset);
            }
            
            return rv;
        }
        
        public Gee.Collection<BeatBox.EqualizerPreset> getDefaultPresets () {

            var presets_data = new Gee.LinkedList<string> ();
            
            if (default_presets != null) {
                for (int i = 0; i < default_presets.length; i++) {
                    presets_data.add (default_presets[i]);
                }
            }
            
            var rv = new Gee.LinkedList<BeatBox.EqualizerPreset>();
            
            foreach (var preset_str in presets_data) {
                var equalizer_preset = new BeatBox.EqualizerPreset.from_string (preset_str);
                if (equalizer_preset != null)
                    rv.add (equalizer_preset);
            }
            
            return rv;
        }
        
        public string[] getPresetsArray (Gee.Collection<BeatBox.EqualizerPreset> presets) {
            string[] vals = new string[presets.size];
            vals.resize (presets.size);
            
            int index = 0;
            foreach (var p in presets) {
                string preset = p.name;

                for(int i = 0; i < 10; ++i) {
                    preset += "/" + p.getGain(i).to_string();
                }

                vals[index] = preset;
                index++;
            }

            return vals;
        }
    }
}

