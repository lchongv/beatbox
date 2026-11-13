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
using Gee;

public class BeatBox.PodcastSummarySection : Box {
	Gtk.Image coverArt;
	Label meta_title;
	Label meta_artist;
	Label meta_album;
	Label meta_year;
	RatingWidget rating;
	StyledBox description_holder;
	Label description;
	StyledBox album_songs_holder;
	MusicList album_songs;
	Label summary_text;
	
	static CssProvider style_provider;
	private const string WIDGET_STYLESHEET = """
		.gray {
			background-image: linear-gradient(to bottom, shade(#d5d3d1, 1.00), shade(#d5d3d1, 0.95));
		}
		
		.black {
			background-image: linear-gradient(to bottom, shade(#383838, 1.05), #383838);
		}
		.padding {
			padding: 6px;
		}
		
		.white {
			background-image: linear-gradient(to bottom, shade(#f8f8f8, 1.05), #f8f8f8);
		}
		
		.pure_white {
			background-color: #fff;
			background-image: none;
		}
		
		.white_text {
			color: shade(#f0f0f0, 1.01);
			text-shadow: 1px 1px 0 alpha(#f8f8f8, 0.3);
		}
		""";
	
	public PodcastSummarySection() {
		set_orientation(Orientation.HORIZONTAL);
		
		if(style_provider == null) {
			style_provider = new CssProvider();
			style_provider.load_from_data (WIDGET_STYLESHEET.data);
		}
		
		build_ui();
		
		set_visible(App.playback.current_media != null);
		
		App.playback.media_played.connect(media_played);
		App.playback.playback_stopped.connect(playback_stopped);
		App.library.medias_updated.connect(medias_updated);
		App.info.track_info_updated.connect(update_summary);
		App.info.album_info_updated.connect(update_summary);
		App.info.album_info_updated.connect(update_album_songs);
		App.info.artist_info_updated.connect(update_summary);
	}
	
	void build_ui() {
		// First add the metadata stuff coverart, song, artist, album
		var left_side = new Box(Orientation.VERTICAL, 0);
		var metadata = new Box(Orientation.HORIZONTAL, 0);
		var meta_labels = new Box(Orientation.VERTICAL, 0);
		
		coverArt = new Gtk.Image();
		meta_title = new Label("");
		meta_artist = new Label("");
		meta_album = new Label("");
		Box rate_box = new Box(Orientation.HORIZONTAL, 0);
		rating = new RatingWidget(false, IconSize.NORMAL, false, null);
		meta_year = new Label("");
		summary_text = new Label("");
		description = new Label("");
		
		rate_box.append(rating);
		
		metadata.append(coverArt);
		metadata.append(UI.wrap_alignment(meta_labels, 0, 0, 0, 6));
		meta_labels.append(meta_title);
		meta_labels.append(meta_artist);
		meta_labels.append(meta_album);
		meta_labels.append(meta_year);
		meta_labels.append(rate_box);
		
		coverArt.halign = Gtk.Align.START;
		meta_title.xalign = 0.0f;
		meta_artist.xalign = 0.0f;
		meta_album.xalign = 0.0f;
		meta_year.xalign = 0.0f;
		summary_text.xalign = 0.0f;
		description.xalign = 0.0f;
		coverArt.valign = Gtk.Align.START;
		meta_title.yalign = 0.0f;
		meta_artist.yalign = 0.0f;
		meta_album.yalign = 0.0f;
		meta_year.yalign = 0.0f;
		summary_text.yalign = 0.0f;
		description.yalign = 0.0f;
		meta_title.wrap = true;
		meta_artist.wrap = true;
		meta_album.wrap = true;
		summary_text.wrap = true;
		description.wrap = true;
		coverArt.set_size_request (Icons.ALBUM_VIEW_IMAGE_SIZE, Icons.ALBUM_VIEW_IMAGE_SIZE);
		
		rating.rating_changed.connect(rating_changed);
		
		var dest = new Gtk.DropTarget (GLib.Type.INVALID, Gdk.DragAction.COPY);
		dest.set_gtypes ({ typeof (string), typeof (Gdk.FileList) });
		dest.motion.connect (drag_motion_signal);
		dest.leave.connect (drag_leave_signal);
		dest.on_drop.connect (drag_received);
		add_controller (dest);
		
		// Now the album list on left side under metadata
		album_songs_holder = new StyledBox("Album Songs", "white");
		var tvs = new TreeViewSetup(MusicColumn.TRACK, SortType.ASCENDING, TreeViewSetup.Hint.NOW_PLAYING);
		album_songs = new MusicList(tvs);
		album_songs.is_mixed = true;
		album_songs.set_sort_column_id(tvs.sort_column_id, tvs.sort_direction);
		album_songs.add_css_class("AlbumSongList");
		//album_songs.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		var scroll = new ScrolledWindow();
		scroll.set_child(album_songs);
		scroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		scroll.set_size_request(-1, 160);
		album_songs_holder.set_widget(AquaScroll.wrap(scroll));
		
		// Summaries go under album list
		//summary_holder = new StyledBox("", "gray");
		var summary_scroll = new ScrolledWindow();
		summary_text.add_css_class("pure_white");
		summary_text.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		//summary_scroll.set_child(summary_text);
		summary_scroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		summary_scroll.set_size_request(-1, 130);
		//summary_holder.set_widget(summary_scroll);
		
		// And lastly the lyrics box
		description_holder = new StyledBox("", "black");
		description.get_style_context().add_class("white_text");
		description.get_style_context().add_class("padding");
		description.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		var description_scroll = new ScrolledWindow();
		description_scroll.add_css_class("black");
		description_scroll.get_style_context().add_provider(style_provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
		description_scroll.set_child(description);
		description_scroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		description_holder.set_size_request(300, -1);
		description_holder.set_widget(AquaScroll.wrap(description_scroll));
		
		left_side.append(metadata);
		summary_text.vexpand = album_songs_holder.vexpand = true;
		left_side.append(UI.wrap_alignment(summary_text, 6, 0, 0, 0));
		left_side.append(UI.wrap_alignment(album_songs_holder, 6, 0, 0, 0));
		
		left_side.hexpand = true;
		append(UI.wrap_alignment(left_side, 0, 0, 0, 0));
		append(UI.wrap_alignment(description_holder, 0, 0, 0, 12));
	}
	
	void media_played(Media m, Media? old) {
		update_contents();
		
		set_visible(true);
	}
	
	void playback_stopped(Media? was_playing) {
		set_visible(false);
	}
	
	void medias_updated(Collection<Media> ids) {
		update_contents();
	}
	
	void rating_changed(int new_rating) {
		App.playback.current_media.rating = new_rating;
		App.library.update_media(App.playback.current_media, false, true, true);
	}
	
	bool is_valid_image_type(string type) {
		var typeDown = type.down();
		
		return (typeDown.has_suffix(".jpg") || typeDown.has_suffix(".jpeg") ||
				typeDown.has_suffix(".png"));
	}
	
	Gdk.DragAction drag_motion_signal(double x, double y) {
		coverArt.set_state_flags(Gtk.StateFlags.DROP_ACTIVE, false);
		coverArt.visible = true;
		UI.show_pixbuf(coverArt, App.icons.DROP_ALBUM_PIXBUF);

		return Gdk.DragAction.COPY;
	}

	void drag_leave_signal() {
		coverArt.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);
		update_cover_art();
	}
	
	bool drag_received(Value value, double x, double y) {
		if(App.playback.current_media == null || App.playback.current_media.isTemporary)
			return false;

		bool success = true;

		string[] uris = {};
		if(value.holds(typeof(Gdk.FileList)))
			foreach(unowned File f in ((Gdk.FileList)value.get_boxed()).get_files()) uris += f.get_uri();
		else
			uris = value.get_string().split("\n");

		foreach(string uri in uris) {

			if(is_valid_image_type(uri) && App.playback.current_media != null) {
				message("Saving dragged album art as image\n");
				App.covers.save_album_locally(App.playback.current_media, uri);
			}
			else {
				message("Dragged album art is not valid image\n");
			}

			return success;
		}
		return false;
	}
	
	void update_sensitivities() {
		/*bool media_playing = App.playback.current_media != null;
		bool song_playing = media_playing && App.playback.current_media.mediatype == MediaType.SONG;
		
		set_visible(media_playing);*/
	}
	
	void update_contents() {
		Media m = App.playback.current_media;
		if(m == null || !(m is Podcast)) {
			return;
		}
		
		Podcast p = (Podcast)m;
		
		var title = "<span size=\"xx-large\">" + Markup.escape_text(p.title) + "</span>";
		var artist = ((p.artist != "" && p.artist != _("Unknown Artist")) ? ("<span size=\"x-large\">" + Markup.escape_text(p.artist) + "</span>") : "");
		var album = ((p.album != "" && p.album != _("Unknown Album")) ? ("<span size=\"large\">" + Markup.escape_text(p.album) + "</span>") : "");
		var released = ((p.date_released != 0) ? ("<span size =\"medium\">" + p.pretty_podcast_date() + "</span>") : "");
		
		meta_title.set_markup(title);
		meta_artist.set_markup(artist);
		meta_album.set_markup(album);
		meta_year.set_markup(released);
		
		meta_album.set_visible(m.album != "" && m.album != _("Unknown Album"));
		meta_year.set_visible(p.date_released != 0);
		
		rating.set_rating((int)m.rating);
		
		update_cover_art();
		update_album_songs();
		update_summary();
		update_description();
		
		update_sensitivities();
	}
	
	void update_cover_art() {
		if(App.playback.current_media == null) {
			return;
		}

		var coverart_pixbuf = App.covers.get_album_art_from_key(App.playback.current_media.artist, App.playback.current_media.album);

		if(coverart_pixbuf != null) {
			UI.show_pixbuf(coverArt, coverart_pixbuf);
		}
		else {
			UI.show_pixbuf(coverArt, App.icons.DEFAULT_ALBUM_ART_PIXBUF);
		}
	}
	
	void update_album_songs() {
		if(App.playback.current_media == null)
			return;
		
		Media current_media = App.playback.current_media;
		
		// Don't change the list if still in same album. Otherwise we lose temps.
		//var old = album_songs.get_media_from_index(0);
		//if(old != null && old.album_artist = current_media.album_artist && old.album == current_media.album)
		//	return;
		
		var results = new LinkedList<Media>();
		App.library.do_search (App.library.podcast_library.medias(), out results, null, null, null, null,
	                 album_songs.get_hint(), "", current_media.album_artist, current_media.album);
	    
	    var table = new GLib.HashTable<int, Media>(null, null);
	    foreach(var m in results)
			table.set((int)table.size(), m);
		
		// Try filling in missing songs w/ album info's tracks
		if(App.info.current_album != null) {
			var fillers = new LinkedList<Podcast>();
			
			// TODO: Fixme
			//find_filler_songs(table, App.info.current_album.tracks(), ref fillers);
			foreach(var media in fillers)
				table.set((int)table.size(), media);
		}
		
		album_songs.set_table(table);
		album_songs_holder.set_visible(table.size() > 1);
	}
	
	/*void find_filler_songs(HashTable<int, Media> in_library, Collection<Podcast> tests, ref LinkedList<Media> fillers) {
		foreach(Media test in tests) {
			bool found_match = false;
			
			for(int i = 0; i < in_library.size(); ++i) {
				Media s = in_library.get(i);
				if(test.track == s.track) {
					found_match = true;
					break;
				}
			}
			
			if(!found_match)
				fillers.add(test);
		}
	}*/
	
	public override void size_allocate(int width, int height, int baseline) {
		base.size_allocate(width, height, baseline);
		update_description();
	}
	
	void update_description() {
		Media m = App.playback.current_media;
		if(m == null)
			return;
		
		description.set_label(Markup.escape_text(m.comment));
		bool show_description = m.comment != null && m.comment != "" && get_width() > 800;
		description_holder.set_visible(show_description);
	}
	
	void update_summary() {
		bool have_title_info = 	App.info.current_track != null && !String.is_empty(App.info.current_track.short_desc);
		bool have_album_info = 	App.info.current_album != null && !String.is_empty(App.info.current_album.short_desc);
		bool have_artist_info = App.info.current_artist != null && !String.is_empty(App.info.current_artist.short_desc);
		
		var whole_summary = "";
		if(have_title_info) {
			whole_summary += App.info.current_track.short_desc;
		}
		if(have_album_info) {
			if(have_title_info)
				whole_summary += "\n\n";
			
			whole_summary += App.info.current_album.short_desc;
		}
		if(have_artist_info) {
			if(have_title_info || have_album_info)
				whole_summary += "\n\n";
			
			whole_summary += App.info.current_artist.short_desc;
		}
		
		summary_text.set_visible(have_title_info || have_album_info || have_artist_info);
		summary_text.set_markup(String.remove_html(whole_summary));
	}
}
