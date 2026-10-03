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

public class BeatBox.MetadataDisplay : BeatBox.Display, Box {
	bool _is_enabled;
	public bool is_enabled { get { return _is_enabled; } }
	
	private Label label;
	private Stack second_line;    // two-line mode: artist and album, sliding up in turn
	private Label[] second_labels;
	private bool second_shows_b = false;
	private Label station_label;
	private string[] second_texts = {};
	private int second_index = 0;
	private uint alternate_id = 0;
	private TimeScale time_scale;
	
	public MetadataDisplay() {
		label = new Label("");
		station_label = new Label("");
        time_scale = new TimeScale();
		
		label.xalign = 0.5f;
		label.set_justify(Justification.LEFT);
		label.ellipsize = Pango.EllipsizeMode.END;
		
		station_label.xalign = 0.5f;
		station_label.set_justify(Justification.LEFT);
		station_label.ellipsize = Pango.EllipsizeMode.END;
		
		station_label.set_no_show_all(true);
        
		second_line = new Stack();
		second_line.vhomogeneous = true;
		second_labels = { new Label(""), new Label("") };
		foreach(var l in second_labels) {
			l.ellipsize = Pango.EllipsizeMode.END;
			l.show();
		}
		second_line.add_named(second_labels[0], "a");
		second_line.add_named(second_labels[1], "b");
		second_line.set_no_show_all(true);
		
        this.set_orientation(Orientation.VERTICAL);
        pack_start(label, false, false, 0);
        pack_start(second_line, false, false, 0);
        pack_start(time_scale, false, false, 0);
        pack_start(station_label, true, true, 0);
        
        App.library.medias_updated.connect(medias_updated);
		App.playback.media_played.connect(media_played);
		App.playback.playback_stopped.connect(playback_stopped);
		App.settings.main.notify["lcd-two-lines"].connect(update_metadata);
		App.settings.main.notify["lcd-transition-ms"].connect(apply_transition);
		apply_transition();
		
		show_all();
		set_no_show_all(true);
	}
	
	void medias_updated(Gee.Collection<Media> ids) {
		update_metadata();
	}
	
	void media_played(Media m, Media ?old) {
		update_metadata();
		enabled();
	}
	
	void playback_stopped(Media? was_playing) {
		disabled();
	}
	
	void apply_transition() {
		second_line.transition_duration = App.settings.main.lcd_transition_ms.clamp(0, 5000);
	}
	
	/* The title on top, and under it the artist and the album take turns:
	 * each new line pushes the previous one up and out of the LCD. */
	void show_second_line(string text, bool animate) {
		var next = second_shows_b ? second_labels[0] : second_labels[1];
		next.label = text;
		second_line.transition_type = animate ? StackTransitionType.SLIDE_UP : StackTransitionType.NONE;
		second_shows_b = !second_shows_b;
		second_line.visible_child_name = second_shows_b ? "b" : "a";
	}
	
	void show_next_second_line() {
		if(second_texts.length < 2)
			return;
		second_index = (second_index + 1) % second_texts.length;
		show_second_line(second_texts[second_index], true);
	}
	
	void update_metadata() {
		if(alternate_id != 0)
			Source.remove(alternate_id);
		alternate_id = 0;
		second_line.hide();
		
		if(App.playback.media_active) {
			var m = App.playback.current_media;
			label.set_markup(m.get_primary_display_text());
			
			if(App.settings.main.lcd_two_lines && m.can_seek) {
				label.set_markup("<b>" + Markup.escape_text(m.title) + "</b>");
				second_texts = {};
				if(m.artist != "" && m.artist != _("Unknown Artist"))
					second_texts += m.artist;
				if(m.album != "" && m.album != _("Unknown Album"))
					second_texts += m.album;
				second_index = 0;
				if(second_texts.length > 0) {
					show_second_line(second_texts[0], false);
					second_line.show();
				}
				if(second_texts.length > 1)
					alternate_id = Timeout.add_seconds(3, () => { show_next_second_line(); return Source.CONTINUE; });
			}
			
			if(!App.playback.current_media.can_seek) {
				label.margin_top = 2;
				time_scale.hide();
				station_label.show();
				
				if(App.playback.current_media.get_secondary_display_text() != null) {
					station_label.set_markup(App.playback.current_media.get_secondary_display_text());
				}
			}
			else {
				label.margin_top = 2;
				station_label.hide();
				time_scale.show_all();
			}
		}
		else {
			disabled();
		}
	}
	
	public bool is_cancellable() {
		return false;
	}
	
	public void cancel() {
		// Do nothing
	}
}
