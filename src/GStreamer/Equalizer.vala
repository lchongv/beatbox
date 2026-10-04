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

public class BeatBox.Equalizer : GLib.Object {
	public dynamic Gst.Element element;
	
	public Equalizer() {
		element = ElementFactory.make("equalizer-10bands", "equalizer");
		
		if (element == null)
			return;
		
		// the octave bands the equalizer window labels (32 Hz ... 16 kHz), each an
		// octave wide (an octave around f spans f/sqrt(2) .. f*sqrt(2), i.e. 0.707 f)
		int[] freqs = {32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
		for (int index = 0; index < 10; index++) {
			GLib.Object band = ((Gst.ChildProxy)element).get_child_by_index(index);
			band.set("freq", (double)freqs[index],
			         "bandwidth", freqs[index] * 0.707,
			         "gain", 0.0);
		}
	}
	
	public void setGain(int index, double gain) {
		GLib.Object band = ((Gst.ChildProxy)element).get_child_by_index(index);
		
		if (gain < 0)
			gain *= 0.24f;
		else
			gain *= 0.12f;
		
		band.set("gain", gain);
	}
}
