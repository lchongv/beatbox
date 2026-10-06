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

using Gtk;

public class BeatBox.TimeScale : Box {
	private Label left_time;
	private Label right_time;
	private Scale scale;
	private GestureMultiPress click_gesture; // GTK3 controllers need a reference
	private GestureMultiPress right_click_gesture;
	private EventBox right_box;
	private uint nyan_id = 0;
	private bool live = false;
	
	private const string WIDGET_STYLESHEET = """
        .scale.slider,
        .scale.slider:disabled {
			background-image: none;
			background: none;
			margin: 0px;
			padding: 0px;
		}
		.scale {
			margin: 0px;
			padding: 0px;
			min-width: 6px; min-height: 6px;
		}
    """;
	
	public TimeScale() {
		var style_provider = new CssProvider();

        try  {
            style_provider.load_from_data (WIDGET_STYLESHEET, -1);
        } catch (Error e) {
            warning("Couldn't load style provider.\n");
        }
		
		left_time = new Label("0:00");
		right_time = new Label("0:00");
		scale = new Scale.with_range(Orientation.HORIZONTAL, 0, 1, 1);
		
		left_time.margin_end = 6;
		right_time.margin_start = 6;
		// equal-width digits and a width fixed by the song's length, so the
		// diamond's track doesn't shrink and grow as the seconds tick
		var digits = new Pango.AttrList ();
		digits.insert (new Pango.AttrFontFeatures ("tnum"));
		left_time.attributes = right_time.attributes = digits;
		left_time.xalign = 1;
		right_time.xalign = 0;
		
		//get_style_context().add_class(Gtk.STYLE_CLASS_PRIMARY_TOOLBAR);
		//scale.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		
		scale.set_draw_value(false);
		
		set_orientation(Orientation.HORIZONTAL);
		add(left_time);
		scale.hexpand = true;
		add(scale);
		// clicking the right time switches between the time left and the song's length
		right_box = new EventBox();
		right_box.add(right_time);
		right_box.tooltip_text = _("Click to switch between the time left and the total time");
		add(right_box);
		right_click_gesture = new GestureMultiPress(right_box);
		right_click_gesture.released.connect(() => {
			App.settings.main.lcd_total_time = !App.settings.main.lcd_total_time;
			value_changed();
		});
		
		// pressing and releasing jump there (instead of the scale's own handling, dragging included)
		click_gesture = new GestureMultiPress(scale);
		click_gesture.button = 0;
		click_gesture.propagation_phase = PropagationPhase.CAPTURE;
		click_gesture.pressed.connect((n_press, x, y) => {
			seek_to(x);
			click_gesture.set_state(EventSequenceState.CLAIMED);
		});
		click_gesture.released.connect((n_press, x, y) => seek_to(x));
		scale.value_changed.connect(value_changed);
		scale.change_value.connect(change_value);
		App.playback.current_position_update.connect(player_position_update);
		
		App.library.medias_updated.connect(medias_updated);
		App.playback.media_played.connect(media_played);
		App.playback.playback_played.connect(update_nyan);
		App.playback.playback_paused.connect(update_nyan); // stopping pauses too
		App.settings.main.notify["lcd-marker-shape"].connect(() => update_nyan());
	}
	
	/** The Nyan cat marker runs (its two frames take turns, see App.apply_lcd_style) while the music plays */
	void update_nyan() {
		bool run = App.playback.playing && App.settings.main.lcd_marker_shape == "nyan";
		if(run == (nyan_id != 0))
			return;
		if(run) {
			nyan_id = Timeout.add(120, () => {
				var style = scale.get_style_context();
				if(style.has_class("nyan-b"))
					style.remove_class("nyan-b");
				else
					style.add_class("nyan-b");
				return Source.CONTINUE;
			});
		}
		else {
			Source.remove(nyan_id);
			nyan_id = 0;
		}
	}
	
	/** A radio station has no position: no times, a barber pole (see theme.css) and the marker in its middle */
	public void set_live(bool live) {
		this.live = live;
		left_time.visible = right_box.visible = !live;
		if(live) {
			scale.get_style_context().add_class("live");
			set_scale_range(0, 2);
			set_scale_value(1);
		}
		else {
			scale.get_style_context().remove_class("live");
			value_changed();
		}
	}
	
	/** scale functions **/
	public void set_scale_range(double min, double max) {
		scale.set_range(min, max);
	}
	
	public void set_scale_value(double val) {
		scale.set_value(val);
	}
	
	public double get_scale_value() {
		return scale.get_value();
	}
	
	// the point of the media at x pixels from the scale's left
	void seek_to(double x) {
		if(live)
			return;
		int point_x = (int)x;
		double mediatime = ((double)point_x / (double)scale.get_allocated_width()) * scale.get_adjustment().upper;
		
		change_value(ScrollType.NONE, mediatime);
	}
		
	public bool change_value(ScrollType scroll, double val) {
		App.playback.current_position_update.disconnect(player_position_update);
		scale.set_value(val);
		App.playback.current_position_update.connect(player_position_update);
		App.playback.set_position((int64)(val * 1000000000));
		
		return false;
	}
	
	void player_position_update(int64 position) {
		double sec = 0.0;
		if(App.playback.current_media != null && !live) {
			sec = ((double)position/1000000000);
			set_scale_value(sec);
		}
	}
	
	void value_changed() {
		if(live)
			return;
		string current_time = "";
		string total_time = "";
		
		//make pretty current time
		int minute = 0;
		int seconds = (int)scale.get_value();
		
		while(seconds >= 60) {
			++minute;
			seconds -= 60;
		}
		
		current_time = minute.to_string() + ":" + ((seconds < 10 ) ? "0" + seconds.to_string() : seconds.to_string());
		
		//make pretty remaining time (or the total)
		minute = 0;
		bool total = App.settings.main.lcd_total_time;
		seconds = (int)App.playback.current_media.length - (total ? 0 : (int)scale.get_value());
		
		while(seconds >= 60) {
			++minute;
			seconds -= 60;
		}
		
		total_time = (total ? "" : "-") + minute.to_string() + ":" + ((seconds < 10 ) ? "0" + seconds.to_string() : seconds.to_string());
		
		int length = (int)App.playback.current_media.length;
		left_time.width_chars = right_time.width_chars = "%d:00".printf(length / 60).length + 2; // two spare digits: glyph widths vary
		left_time.set_text(current_time);
		right_time.set_text(total_time);
	}
	
	void medias_updated(Gee.Collection<Media> ids) {
		if(App.playback.current_media != null && !live) {
			set_scale_range(0.0, (double)App.playback.current_media.length);
			value_changed();
		}
	}
	
	void media_played(Media m, Media? old) {
		set_scale_range(0.0, (double)App.playback.current_media.length);
		value_changed();
	}
}

