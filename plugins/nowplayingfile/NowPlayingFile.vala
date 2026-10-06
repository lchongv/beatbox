/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/** Keeps "Artist - Title" of the playing song in a text file; empty when nothing plays */
public class BeatBox.NowPlayingFile : Object, Plugin {
	PlaybackInterface? playback;
	string path = Path.build_filename(Environment.get_user_cache_dir(), "beatbox", "now-playing.txt");
	
	public void activate(PluginHost host) {
		playback = host.playback;
		playback.media_played.connect(media_played);
		playback.playback_stopped.connect(playback_stopped);
		write(playback.media_active ? text_of(playback.current_media) : "");
	}
	
	public void deactivate() {
		playback.media_played.disconnect(media_played);
		playback.playback_stopped.disconnect(playback_stopped);
		playback = null;
		FileUtils.remove(path);
	}
	
	void media_played(Media m, Media? old) {
		write(text_of(m));
	}
	
	void playback_stopped(Media? was_playing) {
		write("");
	}
	
	static string text_of(Media m) {
		return m.artist != "" ? "%s - %s\n".printf(m.artist, m.title) : m.title + "\n";
	}
	
	void write(string text) {
		try {
			DirUtils.create_with_parents(Path.get_dirname(path), 0755);
			FileUtils.set_contents(path, text);
		} catch (FileError err) {
			warning("Could not write %s: %s", path, err.message);
		}
	}
}

public BeatBox.Plugin beatbox_plugin_create() {
	return new BeatBox.NowPlayingFile();
}
