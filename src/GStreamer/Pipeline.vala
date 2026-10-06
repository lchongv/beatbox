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
	Pad? spectrum_in = null;  // the spectrum branch's way in
	ulong spectrum_drop = 0;  // the probe dropping its buffers while the LCD doesn't show it
	
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
		replaygain.playbin = playbin;
		
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
		
		/* The spectrum on a branch of its own, ending in a sink that keeps the clock: its
		 * messages come as the sound is heard (in line, before the audio sink's buffer, they
		 * came ~0.2 s early), and its buffers are dropped before the FFT while not wanted. */
		dynamic Element? spectrum = ElementFactory.make("spectrum", null);
		if (spectrum != null) {
			dynamic Element spectrumqueue = ElementFactory.make("queue", null);
			dynamic Element spectrumsink = ElementFactory.make("fakesink", null);
			spectrum.bands = 512; // linear: ~43 Hz each, fine enough for the bass bars
			spectrum.interval = 40 * Gst.MSECOND;
			spectrum.threshold = -80;
			// the decoder runs up to ~1.2 s ahead (the audio queue's second and the sink's buffer):
			// room for that, or the queue drops buffers and the spectrum starts over at each gap
			spectrumqueue.max_size_time = 3 * Gst.SECOND;
			spectrumqueue.max_size_buffers = 0;
			spectrumqueue.max_size_bytes = 0;
			spectrumqueue.leaky = 2; // downstream: a stuck branch never holds the music up
			spectrumsink.sync = true;
			spectrumsink.async = false; // nothing to preroll while its buffers are dropped
			((Gst.Bin)audiobin).add_many(spectrumqueue, spectrum, spectrumsink);
			spectrumqueue.link_many(spectrum, spectrumsink);
			spectrum_in = spectrumqueue.get_static_pad("sink");
			audiotee.request_pad_simple("src_%u").link(spectrum_in);
			// a serialized query (allocation, drain: a new song's format) waits for the queue to
			// empty, which waits for the clock, which stops with the music: answer it here (on the
			// queue's pad: the tee sends the allocation query straight to it)
			spectrum_in.add_probe(PadProbeType.QUERY_DOWNSTREAM, (pad, info) =>
				(info.get_query().type.get_flags() & QueryTypeFlags.SERIALIZED) != 0 ? PadProbeReturn.HANDLED : PadProbeReturn.OK);
			want_spectrum(false);
		}
		
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
	
	/** The probes capture nothing, so the pipeline isn't kept alive by its own pad */
	public void want_spectrum(bool wanted) {
		if(spectrum_in == null || wanted == (spectrum_drop == 0))
			return;
		if(wanted) {
			spectrum_in.remove_probe(spectrum_drop);
			spectrum_drop = 0;
		}
		else
			spectrum_drop = spectrum_in.add_probe(PadProbeType.BUFFER, (pad, info) => PadProbeReturn.DROP);
	}
	
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
