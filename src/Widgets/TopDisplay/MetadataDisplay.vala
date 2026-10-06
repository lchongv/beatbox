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
	private SyncedLyrics? lyrics = null;
	private int lyric_line = -2;
	private uint lyrics_request = 0; // drops answers for songs no longer playing
	
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
        add(label);
        add(second_line);
        add(station_label);
        add(time_scale);
        
        App.library.medias_updated.connect(medias_updated);
		App.playback.media_played.connect(media_played);
		App.playback.playback_stopped.connect(playback_stopped);
		App.settings.main.notify["lcd-two-lines"].connect(update_metadata);
		App.settings.main.notify["lcd-transition-ms"].connect(apply_transition);
		App.settings.main.notify["lcd-alternate-seconds"].connect(update_metadata);
		App.settings.main.notify["lcd-lyrics"].connect(update_metadata);
		App.playback.current_position_update.connect(position_update);
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
		lyrics = null;
		lyrics_request++;
		
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
					alternate_id = Timeout.add_seconds(App.settings.main.lcd_alternate_seconds.clamp(1, 60), () => { show_next_second_line(); return Source.CONTINUE; });
				if(App.settings.main.lcd_lyrics && m.media_type == MediaType.SONG)
					fetch_lyrics(m);
			}
			
			label.margin_top = 2;
			time_scale.show_all();
			time_scale.set_live(!m.can_seek);
			if(!m.can_seek) {
				station_label.show();
				
				if(m.get_secondary_display_text() != null) {
					station_label.set_markup(m.get_secondary_display_text());
				}
			}
			else {
				station_label.hide();
			}
		}
		else {
			disabled();
		}
	}
	
	void fetch_lyrics(Media m) {
		uint request = lyrics_request;
		try {
			new Thread<void*>.try(null, () => {
				var found = SyncedLyrics.fetch(m);
				Idle.add(() => {
					if(request == lyrics_request && found != null) {
						// the lyrics take over the second line from artist/album
						if(alternate_id != 0)
							Source.remove(alternate_id);
						alternate_id = 0;
						lyrics = found;
						lyric_line = -2;
						second_line.show();
					}
					return false;
				});
				return null;
			});
		} catch (Error err) {
			warning("Could not start the lyrics thread: %s", err.message);
		}
	}
	
	void position_update(int64 position) {
		if(lyrics == null)
			return;
		int line = lyrics.line_at(position / 1000000);
		if(line == lyric_line)
			return;
		lyric_line = line;
		// before the first line, and on instrumental gaps, show the artist
		string text = (line >= 0 && lyrics.texts[line] != "") ? lyrics.texts[line] : (second_texts.length > 0 ? second_texts[0] : "♪");
		show_second_line(text, true);
	}
	
	public bool is_cancellable() {
		return false;
	}
	
	public void cancel() {
		// Do nothing
	}
}
