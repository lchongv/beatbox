/*-
 * The live audio level in the LCD: bars of LCD segments mirrored around the
 * middle, the bass in the middle and the treble at the edges.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

using Gtk;

/** The arrow at the LCD's left switches to it while something plays (see TopDisplay) */
public class BeatBox.SpectrumDisplay : BeatBox.Display, Box {
	bool _is_enabled = false;
	public bool is_enabled { get { return _is_enabled; } }

	// px
	const int BAR = 11;
	const int BAR_GAP = 4;
	const int MIDDLE_GAP = 8;
	const int SEGMENT = 2;
	const int SEGMENT_GAP = 2;
	// dB: an empty bar, a full one (pop sits around the middle, quiet jazz in the lowest segments)
	const double FLOOR = -64;
	const double CEILING = -20;
	const double TILT = 3;    // dB per octave from 1 kHz, up for the treble and down for the bass: music has more bass
	const double FALL = 0.04; // of a bar per update (25 a second), so the bars drop smoothly

	DrawingArea area;
	double[] levels = {}; // each bar, 0–1, from the middle outwards
	int[] lit = {};       // segments lit in each bar: any sound lights one

	public SpectrumDisplay() {
		area = new DrawingArea();
		area.hexpand = area.vexpand = true;
		add(area);
		area.draw.connect(draw_bars);
		area.map.connect(() => App.playback.want_spectrum(true));
		area.unmap.connect(() => App.playback.want_spectrum(false));

		App.playback.spectrum_update.connect(spectrum_update);
		App.playback.media_played.connect((m, old) => {
			if(!_is_enabled) {
				_is_enabled = true;
				enabled();
			}
		});
		App.playback.playback_paused.connect(clear);
		App.playback.playback_stopped.connect((m) => {
			_is_enabled = false;
			disabled();
		});
	}

	int bars_per_side() {
		return ((area.get_allocated_width() - MIDDLE_GAP) / 2 + BAR_GAP) / (BAR + BAR_GAP);
	}

	int rows() {
		return (area.get_allocated_height() + SEGMENT_GAP) / (SEGMENT + SEGMENT_GAP);
	}

	void clear() {
		levels = {};
		lit = {};
		area.queue_draw();
	}

	void spectrum_update(float[] magnitudes) {
		if(!App.playback.playing) // the last message after a pause
			return;
		int n = bars_per_side(), rows = rows();
		if(levels.length != n) {
			levels = new double[n];
			lit = new int[n];
		}
		bool changed = false;
		double band_hz = 22050.0 / magnitudes.length; // ponytail: assumes 44.1 kHz; at 48 kHz the bars sit 9 % low
		for(int i = 0; i < n; i++) {
			// bar i spans 50 Hz × 320^(i/n) to 50 Hz × 320^((i+1)/n): even steps up to 16 kHz
			double from = 50 * Math.pow(320, (double)i / n), to = 50 * Math.pow(320, (double)(i + 1) / n);
			int first = (int)(from / band_hz), last = int.max(first, (int)(to / band_hz) - 1);
			double db = FLOOR;
			for(int b = first; b <= last && b < magnitudes.length; b++)
				db = double.max(db, magnitudes[b]);
			if(db > FLOOR)
				db += TILT * Math.log2(Math.sqrt(from * to) / 1000);
			levels[i] = double.max(((db - FLOOR) / (CEILING - FLOOR)).clamp(0, 1), levels[i] - FALL);
			int l = (int)Math.ceil(levels[i] * rows);
			changed |= l != lit[i];
			lit[i] = l;
		}
		if(changed) // a redraw repaints the LCD behind too: most of the cost
			area.queue_draw();
	}

	bool draw_bars(Cairo.Context cr) {
		int n = bars_per_side(), rows = rows();
		int middle = area.get_allocated_width() / 2;
		int bottom = (area.get_allocated_height() + rows * (SEGMENT + SEGMENT_GAP) - SEGMENT_GAP) / 2;
		var color = get_style_context().get_color(get_state_flags()); // the LCD's text

		// the unlit segments, the lit ones and the top lit one of each bar (the darkest), one fill each
		double[] alphas = { 0.09, 0.7, 1.0 };
		for(int kind = 0; kind < 3; kind++) {
			for(int i = 0; i < n; i++) {
				int on = i < lit.length ? lit[i] : 0;
				foreach(int x in new int[] { middle - MIDDLE_GAP / 2 - (i + 1) * (BAR + BAR_GAP) + BAR_GAP, middle + MIDDLE_GAP / 2 + i * (BAR + BAR_GAP) }) {
					for(int r = 0; r < rows; r++) {
						if((r >= on ? 0 : (r == on - 1 ? 2 : 1)) == kind)
							cr.rectangle(x, bottom - r * (SEGMENT + SEGMENT_GAP) - SEGMENT, BAR, SEGMENT);
					}
				}
			}
			cr.set_source_rgba(color.red, color.green, color.blue, color.alpha * alphas[kind]);
			cr.fill();
		}
		return false;
	}

	public bool is_cancellable() {
		return false;
	}

	public void cancel() {
		// Do nothing
	}
}
