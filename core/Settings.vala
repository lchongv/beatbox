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

    string group = "";

    public static string config_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "beatbox", "beatbox.conf");
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

    static void schedule_save () {
        if (save_id == 0)
            save_id = Timeout.add (400, () => { save_id = 0; flush (); return Source.REMOVE; });
    }

    /** Call at the end of the subclass constructor, once the defaults are set */
    protected void init_config (string group, string old_schema) {
        this.group = group;
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
        }

        SettingsSchema? old = null;
        if (first_run && SettingsSchemaSource.get_default () != null)
            old = SettingsSchemaSource.get_default ().lookup (old_schema, true);

        bool missing = false;
        var klass = (ObjectClass) get_type ().class_ref ();
        foreach (var pspec in klass.list_properties ()) {
            try {
                if (file.has_group (group) && file.has_key (group, pspec.name)) {
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

    void read_from_file (ParamSpec pspec) throws Error {
        if (pspec is ParamSpecBoolean)
            set (pspec.name, file.get_boolean (group, pspec.name), null);
        else if (pspec is ParamSpecInt)
            set (pspec.name, file.get_integer (group, pspec.name), null);
        else if (pspec is ParamSpecEnum)
            set (pspec.name, file.get_integer (group, pspec.name), null);
        else if (pspec is ParamSpecString)
            set (pspec.name, file.get_string (group, pspec.name), null);
        else if (pspec.value_type == typeof (string[]))
            set (pspec.name, file.get_string_list (group, pspec.name), null);
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
        if (pspec is ParamSpecBoolean)
            file.set_boolean (group, pspec.name, v.get_boolean ());
        else if (pspec is ParamSpecInt)
            file.set_integer (group, pspec.name, v.get_int ());
        else if (pspec is ParamSpecEnum)
            file.set_integer (group, pspec.name, v.get_enum ());
        else if (pspec is ParamSpecString)
            file.set_string (group, pspec.name, v.get_string () ?? "");
        else if (pspec.value_type == typeof (string[])) {
            string[] list = {};
            char** items = (char**) v.get_boxed ();
            for (int i = 0; items != null && items[i] != null; i++)
                list += ((string) items[i]).dup ();
            file.set_string_list (group, pspec.name, list);
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
        
        public LastFM () {
            session_key = "";
            username = "";
            listenbrainz_token = "";
            listenbrainz_user = "";
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
            init_config ("savedstate", "net.launchpad.beatbox.SavedState");
        }
        
    }

    public class Settings : ConfigSection {

        public string music_mount_name { get; set; }
        public string music_folder { get; set; }
        public bool watch_music_folder { get; set; } // import songs that appear in it (FolderWatcher)
        public string podcast_folder { get; set; }
        public bool update_folder_hierarchy { get; set; }
        public bool write_metadata_to_file { get; set; }
        public bool copy_imported_music { get; set; }
        public bool download_new_podcasts { get; set; }
        public int last_media_playing { get; set; }
        public int last_media_position { get; set; }
        public int shuffle_mode { get; set; }
        public int repeat_mode { get; set; }
        public string search_string { get; set; }

        // Appearance
        public string skin { get; set; }
        public bool lcd_two_lines { get; set; }
        public bool lcd_show_cover { get; set; }
        public bool mini_keep_above { get; set; }    // the mini player stays above other windows
        public bool lcd_lyrics { get; set; }         // synced lyrics from lrclib.net on the second line
        public int lcd_alternate_seconds { get; set; } // artist, then album, then artist...
        public int lcd_transition_ms { get; set; }   // second LCD line sliding up
        public int lcd_track_width { get; set; }     // px, the groove of the position bar
        public int lcd_marker_size { get; set; }     // px, the marker
        public string lcd_marker_shape { get; set; } // diamond, circle or cup (data/<shape>.svg)
        public bool album_grid_inline { get; set; }
        public int album_detail_cover_percent { get; set; }
        public bool download_covers { get; set; }
        
        public Settings ()  {
            music_mount_name = "";
            music_folder = "";
            watch_music_folder = true;
            podcast_folder = "";
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
            init_config ("settings", "net.launchpad.beatbox.Settings");
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
        
        public Equalizer () {
            replaygain = 1;
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

