/*-
 * Imports the songs that appear in the music folder while BeatBox runs.
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
	Gee.HashSet<string> pending = new Gee.HashSet<string> ();
	uint flush_id = 0;

	public FolderWatcher () {
		App.settings.main.notify["music-folder"].connect (restart);
		App.settings.main.notify["watch-music-folder"].connect (restart);
		restart ();
	}

	void restart () {
		foreach (var m in monitors.values)
			m.cancel ();
		monitors.clear ();
		pending.clear ();
		if (App.settings.main.watch_music_folder && App.settings.main.music_folder != "")
			watch_tree (File.new_for_path (App.settings.main.music_folder), false);
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
					consider (child);
			}
		} catch (Error err) {
			warning ("Could not watch %s: %s", dir.get_path (), err.message);
		}
	}

	void changed (File file, File? other, FileMonitorEvent event) {
		switch (event) {
			case FileMonitorEvent.CHANGES_DONE_HINT:
			case FileMonitorEvent.MOVED_IN:
				if (file.query_file_type (0) == FileType.DIRECTORY)
					watch_tree (file, true);
				else
					consider (file);
				break;
			case FileMonitorEvent.RENAMED:
				if (other != null)
					consider (other);
				break;
			case FileMonitorEvent.CREATED:
				if (file.query_file_type (0) == FileType.DIRECTORY)
					watch_tree (file, true);
				break;
			default:
				break;
		}
	}

	void consider (File file) {
		if (!FileOperator.is_valid_file_type (file.get_basename ()))
			return;
		pending.add (file.get_uri ());
		if (flush_id != 0)
			Source.remove (flush_id);
		flush_id = Timeout.add_seconds (3, flush); // wait until the copy settles
	}

	bool flush () {
		flush_id = 0;
		if (App.operations.doing_ops) { // BeatBox's own copying, an import...: later
			flush_id = Timeout.add_seconds (5, flush);
			return false;
		}
		var files = new Gee.LinkedList<File> ();
		foreach (var uri in pending)
			if (App.library.media_from_file (uri) == null && File.new_for_uri (uri).query_exists ())
				files.add (File.new_for_uri (uri));
		pending.clear ();
		if (files.size > 0) {
			message ("Importing %d new file(s) from the music folder", files.size);
			App.library.song_library.add_files (files, false);
		}
		return false;
	}
}
