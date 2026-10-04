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

using Gst;

// Gstreamer playbin GstPlayFlag enum
private enum Gst.PlayFlag {
	VIDEO         = (1 << 0),
	AUDIO         = (1 << 1),
	TEXT          = (1 << 2),
	VIS           = (1 << 3),
	SOFT_VOLUME   = (1 << 4),
	NATIVE_AUDIO  = (1 << 5),
	NATIVE_VIDEO  = (1 << 6),
	DOWNLOAD      = (1 << 7),
	BUFFERING     = (1 << 8),
	DEINTERLACE   = (1 << 9)
}

public class BeatBox.Pipeline : GLib.Object {
	public Gst.Pipeline pipe;
	public Equalizer eq;
	public CDDA cdda;
	public ReplayGain replaygain;
	public Video video;
	
	public dynamic Gst.Bus bus;
	//Pad teepad;
	Pad pad;
	
	dynamic Element audiosink;
	dynamic Element audiosinkqueue;
	dynamic Element eq_audioconvert;
	dynamic Element eq_audioconvert2; 
	 
	public dynamic Gst.Element playbin;
	dynamic Gst.Element audiotee;
	dynamic Gst.Element audiobin;
	dynamic Gst.Element preamp;
	//dynamic Gst.Element volume;
	//dynamic Gst.Element rgvolume;
	
	public Pipeline() {
		replaygain = new ReplayGain();
		
		pipe = new Gst.Pipeline("pipeline");
		playbin = ElementFactory.make("playbin", null);
		
		audiosink = ElementFactory.make("autoaudiosink", null);
		//audiosink.set("profile", 1); // says we handle music and movies
		
		audiobin = new Gst.Bin("audiobin"); // this holds the real primary sink
		
		audiotee = ElementFactory.make("tee", null);
		audiosinkqueue = ElementFactory.make("queue", null);
		
		eq = new Equalizer();
		if(eq.element != null) {
			eq_audioconvert = ElementFactory.make("audioconvert", null);
			eq_audioconvert2 = ElementFactory.make("audioconvert", null);
			preamp = ElementFactory.make("volume", "preamp");
			
			((Gst.Bin)audiobin).add_many(eq.element, eq_audioconvert, eq_audioconvert2, preamp);
		}
		
		((Gst.Bin)audiobin).add_many(audiotee, audiosinkqueue, audiosink);
		
		// replaygain (when available) sits in front of the tee
		if (replaygain.element != null) {
			((Gst.Bin)audiobin).add(replaygain.element);
			replaygain.element.link(audiotee);
			audiobin.add_pad(new GhostPad("sink", replaygain.element.get_static_pad("sink")));
		}
		else
			audiobin.add_pad(new GhostPad("sink", audiotee.get_static_pad("sink")));
		
		if (eq.element != null)
			audiosinkqueue.link_many(eq_audioconvert, preamp, eq.element, eq_audioconvert2, audiosink);
		else
			audiosinkqueue.link_many(audiosink); // link the queue with the real audio sink
		
		playbin.set("audio-sink", audiobin); 
		bus = playbin.get_bus();
		
		// Link the first tee pad to the primary audio sink queue
		Gst.Pad sinkpad = audiosinkqueue.get_static_pad("sink");
		pad = audiotee.request_pad_simple("src_%u");
		pad.link(sinkpad);
		
		// now add CDDA and Video
		cdda = new CDDA();
		video = new Video();
		if(video.element != null) {
			audiosinkqueue.link_many(video.element);
			//((Gst.Bin)audiobin).add_many(video.element);
			playbin.set("video-sink", video.element);
		}
		
		// Don't enable video for now
		Gst.PlayFlag flags;
		playbin.get("flags", out flags);
		flags = 			(Gst.PlayFlag.AUDIO);
		((Gst.Element)playbin).set("flags", flags);
		
		//bus.add_watch(busCallback);
		/*play.audio_tags_changed.connect(audioTagsChanged);
		play.text_tags_changed.connect(textTagsChanged);
		play.video_tags_changed.connect(videoTagsChanged);*/
	}
	
	/*private void videoTagsChanged(Gst.Element sender, int stream_number) {
		
	}

	private void audioTagsChanged(Gst.Element sender, int stream_number) {
		
	}

	/*private void textTagsChanged(Gst.Element sender, int stream_number) {
		
	}*/
	
	public int videoStreamCount() {
		return playbin.n_video;
	}
	
	// set by Streamer, which listens to this pipeline (two of them during a crossfade)
	public uint bus_watch = 0;
	public ulong about_to_finish_handler = 0;
	
	/** The same equalizer settings as other (the next song in a crossfade) */
	public void copy_equalizer_from(Pipeline other) {
		if(eq.element == null || other.eq.element == null)
			return;
		for(int i = 0; i < 10; i++) {
			double gain;
			((Gst.ChildProxy)other.eq.element).get_child_by_index(i).get("gain", out gain);
			((Gst.ChildProxy)eq.element).get_child_by_index(i).set("gain", gain);
		}
	}
}
