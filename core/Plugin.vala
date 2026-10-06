/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/** What a plugin gets to work with, filled in by the application */
public class BeatBox.PluginHost : Object {
	public PlaybackInterface playback { get; construct; }
	public LibraryInterface library { get; construct; }
	public LibraryWindowInterface window { get; construct; }
	public Settings settings { get; construct; }

	public PluginHost(PlaybackInterface playback, LibraryInterface library, LibraryWindowInterface window, Settings settings) {
		Object(playback: playback, library: library, window: window, settings: settings);
	}
}

/**
 * A plugin lives in a folder of its own inside a plugins folder
 * (~/.local/share/beatbox/plugins, or the one installed with BeatBox) with:
 *
 *   <id>.plugin   a key file:  [Plugin]
 *                              Module=<id>
 *                              Name=…          (Name[es]=… for translations)
 *                              Description=…
 *   lib<id>.so    built against libbeatbox-core, exporting
 *                 BeatBox.Plugin beatbox_plugin_create ()
 *
 * It's activated when the user turns it on in Preferences › Plugins and
 * deactivated when turned off; deactivate() must undo what activate() did.
 */
public interface BeatBox.Plugin : Object {
	public abstract void activate(PluginHost host);
	public abstract void deactivate();
}
