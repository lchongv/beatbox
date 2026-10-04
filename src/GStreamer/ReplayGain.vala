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

/**
 * Volume normalization from the files' ReplayGain tags (rgvolume ! rglimiter).
 * Off = the ReplayGain tags are stripped before rgvolume, so it applies no gain.
 * A mode change takes effect with the next song.
 */
public class BeatBox.ReplayGain : GLib.Object {
	public const int OFF = 0;
	public const int TRACK = 1;
	public const int ALBUM = 2;
	
	public Gst.Element? element { get; private set; }
	dynamic Gst.Element rgvolume;
	
	public ReplayGain () {
		var convert = Gst.ElementFactory.make ("audioconvert", null);
		rgvolume = Gst.ElementFactory.make ("rgvolume", null);
		var limiter = Gst.ElementFactory.make ("rglimiter", null);
		var convert2 = Gst.ElementFactory.make ("audioconvert", null);
		if (rgvolume == null || limiter == null) {
			warning ("rgvolume/rglimiter missing (gst-plugins-good): no ReplayGain");
			return;
		}
		
		var bin = new Gst.Bin ("replaygain");
		bin.add_many (convert, rgvolume, limiter, convert2);
		convert.link_many (rgvolume, limiter, convert2);
		bin.add_pad (new Gst.GhostPad ("sink", convert.get_static_pad ("sink")));
		bin.add_pad (new Gst.GhostPad ("src", convert2.get_static_pad ("src")));
		rgvolume.get_static_pad ("sink").add_probe (Gst.PadProbeType.EVENT_DOWNSTREAM, strip_tags);
		element = bin;
		apply ();
	}
	
	/** Reads the mode from the settings */
	public void apply () {
		if (element != null)
			rgvolume.album_mode = App.settings.equalizer.replaygain == ALBUM;
	}
	
	const string[] RG_TAGS = { Gst.Tags.TRACK_GAIN, Gst.Tags.TRACK_PEAK, Gst.Tags.ALBUM_GAIN, Gst.Tags.ALBUM_PEAK, Gst.Tags.REFERENCE_LEVEL };
	
	Gst.PadProbeReturn strip_tags (Gst.Pad pad, Gst.PadProbeInfo info) {
		var event = (Gst.Event) info.data;
		if (event.type != Gst.EventType.TAG)
			return Gst.PadProbeReturn.OK;
		apply (); // settings are re-read per song: no plumbing to the preferences
		if (App.settings.equalizer.replaygain != OFF)
			return Gst.PadProbeReturn.OK;
		
		Gst.TagList tags;
		event.parse_tag (out tags);
		bool found = false;
		foreach (var tag in RG_TAGS)
			found |= tags.get_tag_size (tag) > 0;
		if (!found)
			return Gst.PadProbeReturn.OK;
		
		// resend without the gains; it passes this probe untouched the second time
		var stripped = tags.copy ();
		foreach (var tag in RG_TAGS)
			stripped.remove_tag (tag);
		pad.send_event (new Gst.Event.tag ((owned) stripped));
		return Gst.PadProbeReturn.DROP;
	}
}
