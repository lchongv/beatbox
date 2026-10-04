/*-
 * Keeps the library in step with the music folder while BeatBox runs:
 * songs that appear are imported, songs that disappear are removed and
 * songs that are moved or renamed keep their play counts and ratings.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

public class BeatBox.FolderWatcher : GLib.Object {
	// ponytail: one inotify watch per folder; fine for ordinary collections,
	// fs.inotify.max_user_watches is the ceiling for huge ones
	Gee.HashMap<string, FileMonitor> monitors = new Gee.HashMap<string, FileMonitor> ();
	Gee.HashSet<string> appeared = new Gee.HashSet<string> ();     // uris of files to import
	Gee.HashSet<string> disappeared = new Gee.HashSet<string> ();  // uris of library songs that may be gone
	Gee.HashMap<string, string> renamed = new Gee.HashMap<string, string> (); // old uri -> new uri
	uint flush_id = 0;
	uint retry_id = 0;

	public FolderWatcher () {
		App.settings.main.notify["music-folder"].connect (restart);
		App.settings.main.notify["watch-music-folder"].connect (restart);
		restart ();
	}

	void restart () {
		foreach (var m in monitors.values)
			m.cancel ();
		monitors.clear ();
		appeared.clear ();
		disappeared.clear ();
		renamed.clear ();
		if (retry_id != 0)
			Source.remove (retry_id);
		retry_id = 0;
		if (!App.settings.main.watch_music_folder || App.settings.main.music_folder == "")
			return;
		var root = File.new_for_path (App.settings.main.music_folder);
		if (root.query_exists ()) {
			watch_tree (root, false);
		} else { // a drive that isn't mounted yet: look again in a minute
			debug ("Music folder %s not found; watching it once it appears", root.get_path ());
			retry_id = Timeout.add_seconds (60, () => { retry_id = 0; restart (); return false; });
		}
	}

	/** Watches dir and its subfolders; with collect, also queues the songs already in them (a folder moved in) */
	void watch_tree (File dir, bool collect) {
		if (monitors.has_key (dir.get_path ()))
			return;
		try {
			var monitor = dir.monitor_directory (FileMonitorFlags.WATCH_MOVES, null);
			monitor.changed.connect (changed);
			monitors[dir.get_path ()] = monitor;
			var children = dir.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE, 0);
			FileInfo info;
			while ((info = children.next_file ()) != null) {
				var child = dir.get_child (info.get_name ());
				if (info.get_file_type () == FileType.DIRECTORY)
					watch_tree (child, collect);
				else if (collect)
					file_appeared (child);
			}
		} catch (Error err) {
			warning ("Could not watch %s: %s", dir.get_path (), err.message);
		}
	}

	void changed (File file, File? other, FileMonitorEvent event) {
		switch (event) {
			case FileMonitorEvent.CHANGES_DONE_HINT:
			case FileMonitorEvent.CREATED:
				if (file.query_file_type (0) == FileType.DIRECTORY)
					watch_tree (file, true);
				else if (event != FileMonitorEvent.CREATED) // a copy is done at CHANGES_DONE_HINT
					file_appeared (file);
				break;
			case FileMonitorEvent.RENAMED:
				if (other != null)
					move (file, other);
				else
					gone (file);
				break;
			case FileMonitorEvent.MOVED_OUT: // file left, other is where it went
				if (other != null && inside_root (other))
					move (file, other);
				else
					gone (file);
				break;
			case FileMonitorEvent.MOVED_IN: // file arrived, other is where it came from
				if (other != null && inside_root (other))
					move (other, file);
				else if (file.query_file_type (0) == FileType.DIRECTORY)
					watch_tree (file, true);
				else
					file_appeared (file);
				break;
			case FileMonitorEvent.DELETED:
				gone (file);
				break;
			default:
				break;
		}
	}

	static bool inside_root (File f) {
		var root = File.new_for_path (App.settings.main.music_folder);
		return f.equal (root) || f.has_prefix (root);
	}

	/** A song or folder renamed or moved within the music folder (both MOVED_OUT and MOVED_IN may report it) */
	void move (File from, File to) {
		bool folder = to.query_file_type (0) == FileType.DIRECTORY;
		if (folder) {
			unwatch (from);
			watch_tree (to, false);
			string old_prefix = from.get_uri () + "/";
			foreach (var m in App.library.song_library.medias ())
				if (m.uri.has_prefix (old_prefix))
					renamed[m.uri] = to.get_uri () + "/" + m.uri.substring (old_prefix.length);
		} else if (App.library.media_from_file (from.get_uri ()) != null) {
			renamed[from.get_uri ()] = to.get_uri ();
		} else {
			file_appeared (to); // wasn't a library song: maybe it is now (renamed to .mp3...)
		}
		schedule_flush ();
	}

	void unwatch (File dir) {
		string path = dir.get_path ();
		foreach (var key in monitors.keys.to_array ()) {
			if (key == path || key.has_prefix (path + "/")) {
				monitors[key].cancel ();
				monitors.unset (key);
			}
		}
	}

	void file_appeared (File file) {
		if (!FileOperator.is_valid_file_type (file.get_basename ()))
			return;
		appeared.add (file.get_uri ());
		schedule_flush ();
	}

	/** file (a song or a whole folder) is no longer there */
	void gone (File file) {
		unwatch (file); // a folder that went away, and its subfolders
		string uri = file.get_uri ();
		if (App.library.media_from_file (uri) != null) {
			disappeared.add (uri);
		} else {
			foreach (var m in App.library.song_library.medias ())
				if (m.uri.has_prefix (uri + "/"))
					disappeared.add (m.uri);
		}
		schedule_flush ();
	}

	void schedule_flush () {
		if (flush_id != 0)
			Source.remove (flush_id);
		flush_id = Timeout.add_seconds (3, flush); // wait until copies and moves settle
	}

	bool flush () {
		flush_id = 0;
		if (App.operations.doing_ops) { // BeatBox's own copying, an import...: later
			flush_id = Timeout.add_seconds (5, flush);
			return false;
		}
		var root = File.new_for_path (App.settings.main.music_folder);
		var moved = new Gee.ArrayList<Media> ();

		// renames and moves GLib reported with both ends
		foreach (var entry in renamed.entries) {
			var m = App.library.media_from_file (entry.key);
			if (m != null && File.new_for_uri (entry.value).query_exists () && App.library.media_from_file (entry.value) == null) {
				message ("%s moved to %s", m.uri, entry.value);
				m.uri = entry.value;
				moved.add (m);
			}
			disappeared.remove (entry.key);
			appeared.remove (entry.value);
		}
		renamed.clear ();

		// songs really gone (and never when the whole folder is missing: an unmounted drive)
		var lost = new Gee.ArrayList<Media> ();
		if (root.query_exists ()) {
			foreach (var uri in disappeared) {
				var m = App.library.media_from_file (uri);
				if (m != null && !File.new_for_uri (uri).query_exists ())
					lost.add (m);
			}
		}
		// files not in the library yet
		var found = new Gee.ArrayList<File> ();
		foreach (var uri in appeared) {
			var f = File.new_for_uri (uri);
			if (App.library.media_from_file (uri) == null && f.query_exists ())
				found.add (f);
		}
		disappeared.clear ();
		appeared.clear ();

		// a lost song and a found file with the same name and size: moved, unpaired by GLib
		foreach (var m in lost.to_array ()) {
			string name = File.new_for_uri (m.uri).get_basename ();
			foreach (var f in found) {
				if (f.get_basename () == name && size_of (f) == m.file_size) {
					message ("%s moved to %s", m.uri, f.get_uri ());
					m.uri = f.get_uri ();
					moved.add (m);
					lost.remove (m);
					found.remove (f);
					break;
				}
			}
		}
		if (moved.size > 0)
			App.library.update_medias (moved, false, false, true);
		if (lost.size > 0) {
			message ("Removing %d song(s) whose files are gone from the music folder", lost.size);
			App.library.remove_medias (lost, false);
		}
		if (found.size > 0) {
			message ("Importing %d new file(s) from the music folder", found.size);
			App.library.song_library.add_files (found, false);
		}
		return false;
	}

	static uint64 size_of (File f) {
		try {
			return f.query_info (FileAttribute.STANDARD_SIZE, 0).get_size ();
		} catch (Error err) {
			return 0;
		}
	}
}
