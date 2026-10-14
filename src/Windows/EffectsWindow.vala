/*
 * The effects after the equalizer (Settings equalizer): one slider each, 0 leaves the sound as it is.
 * Opened from the equalizer window.
 */
using Gtk;

public class BeatBox.EffectsWindow : Gtk.Window {
	delegate void Setter (int value);

	public EffectsWindow () {
		title = _("Effects");
		set_transient_for (App.window);
		destroy_with_parent = true;
		resizable = false;
		window_position = WindowPosition.CENTER_ON_PARENT;
		type_hint = Gdk.WindowTypeHint.DIALOG;

		var eq = App.settings.equalizer;
		var grid = new Grid () { row_spacing = 10, column_spacing = 14, margin = 16 };
		int row = 0;
		add_slider (grid, ref row, _("Preamp"), -12, 0, eq.preamp_db, _("Lowers the level before the effects and the equalizer, so boosts don't distort"), "%+d dB", (v) => { eq.preamp_db = v; });
		add_slider (grid, ref row, _("Echo"), 0, 100, eq.echo, _("Repeats of the sound, fading"), "%d%%", (v) => { eq.echo = v; });
		add_slider (grid, ref row, _("Vocal reduction"), 0, 100, eq.vocal_reduction, _("Takes out what is in the middle of the stereo image, usually the voice; it also thins the sound"), "%d%%", (v) => { eq.vocal_reduction = v; });
		add_slider (grid, ref row, _("Bass enhancer"), 0, 100, eq.bass, _("Adds harmonics, so the bass is heard on small speakers and headphones"), "%d%%", (v) => { eq.bass = v; });
		add_slider (grid, ref row, _("Exciter"), 0, 100, eq.exciter, _("Adds brightness to the high frequencies"), "%d%%", (v) => { eq.exciter = v; });
		add_slider (grid, ref row, _("Stereo width"), 0, 100, eq.stereo_width, _("Spreads the stereo image"), "%d%%", (v) => { eq.stereo_width = v; });
		add_slider (grid, ref row, _("Saturation"), 0, 100, eq.saturation, _("Warmth, with a little distortion"), "%d%%", (v) => { eq.saturation = v; });
		add_slider (grid, ref row, _("Limiter"), 0, 100, eq.limiter, _("A ceiling for the peaks, so loud parts don't clip"), "%d%%", (v) => { eq.limiter = v; });
		add_slider (grid, ref row, _("Compressor"), 0, 100, eq.compressor, _("Holds down the loudest parts, for an even level"), "%d%%", (v) => { eq.compressor = v; });
		add_slider (grid, ref row, _("Reverb"), 0, 100, eq.reverb, _("Adds the sound of a room"), "%d%%", (v) => { eq.reverb = v; });

		var crossfeed = new CheckButton.with_label (_("Crossfeed"));
		crossfeed.tooltip_text = _("For headphones: each ear hears a little of the other channel, as with speakers");
		crossfeed.active = eq.crossfeed;
		crossfeed.toggled.connect (() => { eq.crossfeed = crossfeed.active; App.playback.apply_effects (); });
		grid.attach (crossfeed, 0, row, 3, 1);

		add (grid);
		show_all ();
	}

	void add_slider (Grid grid, ref int row, string title, int min, int max, int value, string tip, string format, Setter set) {
		var label = new Label (title) { xalign = 1 };
		var slider = new Scale.with_range (Orientation.HORIZONTAL, min, max, 1) { draw_value = false, hexpand = true };
		slider.set_size_request (220, -1);
		slider.set_value (value);
		var readout = new Label (format.printf (value)) { width_chars = 6, xalign = 1 };
		slider.tooltip_text = tip;
		label.tooltip_text = tip;
		slider.value_changed.connect (() => {
			int v = (int) slider.get_value ();
			readout.label = format.printf (v);
			set (v);
			App.playback.apply_effects ();
		});
		grid.attach (label, 0, row, 1, 1);
		grid.attach (slider, 1, row, 1, 1);
		grid.attach (readout, 2, row, 1, 1);
		row++;
	}
}
