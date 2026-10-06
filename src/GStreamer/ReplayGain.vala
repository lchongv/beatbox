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
 * A mode change takes effect with the next song. It also applies the song's own
 * volume adjustment (the editor's Options tab) as extra gain.
 */
public class BeatBox.ReplayGain : GLib.Object {
	public const int OFF = 0;
	public const int TRACK = 1;
	public const int ALBUM = 2;
	
	public Gst.Element? element { get; private set; }
	public unowned Gst.Element? playbin = null; // to know which song the stream is (set by Pipeline)
	dynamic Gst.Element rgvolume;
	string adjusted_uri = "";
	
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
		if (element == null)
			return;
		rgvolume.album_mode = App.settings.equalizer.replaygain == ALBUM;
		
		// playbin's current-uri is already the next song when a gapless switch's tags come
		string? uri = (playbin != null) ? (string?)((dynamic Gst.Element)playbin).current_uri : null;
		if (uri == null || uri == adjusted_uri)
			return;
		adjusted_uri = uri;
		var m = App.library.media_from_file (uri);
		double gain = (m != null) ? adjustment_db (m.volume_adjust) : 0.0;
		// pre-amp adds to the tags' gain and to the fallback gain alike (songs without tags,
		// and every song with ReplayGain off); a boost needs headroom, else it is cut back
		// to 0 dB, and rglimiter keeps it from clipping
		rgvolume.pre_amp = gain;
		rgvolume.headroom = double.max (0.0, gain);
	}
	
	/** -100..100 % of the song's loudness as dB: +100 % doubles it (+6 dB), -100 % mutes it (-60 dB) */
	public static double adjustment_db (int percent) {
		double factor = 1.0 + percent.clamp (-100, 100) / 100.0;
		return (factor <= 0.001) ? -60.0 : double.max (-60.0, 20 * Math.log10 (factor));
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
