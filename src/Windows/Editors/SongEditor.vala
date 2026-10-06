/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originaly Written by Scott Ringwelski for BeatBox Music Player
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


public class BeatBox.SongEditor : GLib.Object, MediaEditorInterface {
	Media current_media;
	Collection<Media> targets; // what the Artwork tab acts on: the songs being edited
	bool single = true;        // one song (lyrics and Identify are per song)
	
	Box horiz; // Contains textVert and numerVert
	Box textVert; // separates text editors
	Box numerVert; // separates numerical editors
	
	Box lyricsContent;
	Label lyricsStatus;
	TextView lyricsText;
	uint lyrics_request = 0; // drops answers for a song no longer shown
	
	Image artwork;
	Label artworkStatus;
	Button identifyButton;
	
	HashMap<string, FieldEditor> fields;// a hashmap with each property and corresponding editor
	
	public SongEditor() {
		fields = new HashMap<string, FieldEditor>();
	}
	
	public Collection<FieldEditor> get_fields() {
		return fields.values;
	}
	
	public Viewport get_metadata_view(Collection<Media> originals) {
		Viewport rv = new Viewport(null, null);
		fields = new HashMap<string, FieldEditor>();
		targets = originals;
		single = originals.size == 1;
		Media sum = originals.to_array()[0].copy();
		current_media = originals.to_array()[0];
		
		/** find what these medias have what common, and keep those values **/
		foreach(Media s in originals) {
			if(s.track != sum.track)
				sum.track = 0;
			if(s.track_count != sum.track_count)
				sum.track_count = 0;
			if(s.album_number != sum.album_number)
				sum.album_number = 0;
			if(s.album_count != sum.album_count)
				sum.album_count = 0;
			if(s.title != sum.title)
				sum.title = "";
			if(s.artist != sum.artist)
				sum.artist = "";
			if(s.album_artist != sum.album_artist)
				sum.album_artist = "";
			if(s.album != sum.album)
				sum.album = "";
			if(s.genre != sum.genre)
				sum.genre = "";
			if(s.comment != sum.comment)
				sum.comment = "";
			if(s.year != sum.year)
				sum.year = 0;
			if(s.composer != sum.composer)
				sum.composer = "";
			if(s.grouping != sum.grouping)
				sum.grouping = "";
			if(s.bpm != sum.bpm)
				sum.bpm = 0;
			if(s.rating != sum.rating)
				sum.rating = 0;
			if(s.sort_title != sum.sort_title)
				sum.sort_title = "";
			if(s.sort_artist != sum.sort_artist)
				sum.sort_artist = "";
			if(s.sort_album_artist != sum.sort_album_artist)
				sum.sort_album_artist = "";
			if(s.sort_album != sum.sort_album)
				sum.sort_album = "";
			if(s.sort_composer != sum.sort_composer)
				sum.sort_composer = "";
			if(s.compilation != sum.compilation)
				sum.compilation = false;
			if(s.skip_shuffle != sum.skip_shuffle)
				sum.skip_shuffle = false;
			if(s.remember_position != sum.remember_position)
				sum.remember_position = false;
			if(s.volume_adjust != sum.volume_adjust)
				sum.volume_adjust = 0;
		}
		
		fields.set("Title", new FieldEditorImpl.for_string(_("Title"), sum.title));
		fields.set("Artist", new FieldEditorImpl.for_string(_("Artist"), sum.artist));
		fields.set("Album Artist", new FieldEditorImpl.for_string(_("Album Artist"), sum.album_artist));
		fields.set("Album", new FieldEditorImpl.for_string(_("Album"), sum.album));
		fields.set("Genre", new FieldEditorImpl.for_string(_("Genre"), sum.genre));
		fields.set("Composer", new FieldEditorImpl.for_string(_("Composer"), sum.composer));
		fields.set("Grouping", new FieldEditorImpl.for_string(_("Grouping"), sum.grouping));
		fields.set("Comment", new FieldEditorImpl.for_long_string(_("Comment"), sum.comment));
		fields.set("Track", new FieldEditorImpl.for_integer(_("Track"), (int)sum.track, 0, 500));
		fields.set("Tracks", new FieldEditorImpl.for_integer(_("of"), (int)sum.track_count, 0, 500));
		fields.set("Disc", new FieldEditorImpl.for_integer(_("Disc"), (int)sum.album_number, 0, 500));
		fields.set("Discs", new FieldEditorImpl.for_integer(_("of"), (int)sum.album_count, 0, 500));
		fields.set("Year", new FieldEditorImpl.for_integer(_("Year"), (int)sum.year, 0, 9999));
		fields.set("BPM", new FieldEditorImpl.for_integer(_("BPM"), (int)sum.bpm, 0, 999));
		fields.set("Rating", new FieldEditorImpl.for_rating(_("Rating"), (int)sum.rating));
		
		fields.set("Sort Title", new FieldEditorImpl.for_string(_("Sort Title"), sum.sort_title));
		fields.set("Sort Artist", new FieldEditorImpl.for_string(_("Sort Artist"), sum.sort_artist));
		fields.set("Sort Album Artist", new FieldEditorImpl.for_string(_("Sort Album Artist"), sum.sort_album_artist));
		fields.set("Sort Album", new FieldEditorImpl.for_string(_("Sort Album"), sum.sort_album));
		fields.set("Sort Composer", new FieldEditorImpl.for_string(_("Sort Composer"), sum.sort_composer));
		
		fields.set("Volume", new FieldEditorImpl.for_integer(_("Volume Adjustment (%)"), sum.volume_adjust, -100, 100));
		fields.set("Compilation", new FieldEditorImpl.for_bool(_("Compilation"), _("Part of a compilation by various artists"), sum.compilation));
		fields.set("Skip Shuffle", new FieldEditorImpl.for_bool(_("Shuffle"), _("Skip when shuffling"), sum.skip_shuffle));
		fields.set("Remember Position", new FieldEditorImpl.for_bool(_("Playback"), _("Remember the playback position"), sum.remember_position));
		
		horiz = new Box(Orientation.HORIZONTAL, 0);
		textVert = new Box(Orientation.VERTICAL, 0);
		numerVert = new Box(Orientation.VERTICAL, 0);
		
		textVert.add(fields.get("Title"));
		foreach(var name in new string[] { "Artist", "Album Artist", "Composer", "Album", "Comment" }) {
			fields.get(name).margin_top = fields.get(name).margin_bottom = 5;
			textVert.add(fields.get(name));
		}
		foreach(var name in new string[] { "Title", "Artist", "Album Artist", "Composer", "Album", "Comment" })
			fields.get(name).set_width_request(300);
		
		// "Identify": fills the title, artist and album from the song's sound (AcoustID)
		identifyButton = new Button.with_label(_("Identify…"));
		identifyButton.halign = Align.START;
		identifyButton.margin_top = 5;
		identifyButton.tooltip_text = AcoustId.available() ? _("Look the song up by its sound on AcoustID")
		                                                   : _("Needs fpcalc, from Chromaprint (the chromaprint or libchromaprint-tools package)");
		identifyButton.sensitive = single && AcoustId.available();
		identifyButton.clicked.connect(identify);
		textVert.add(identifyButton);
		
		numerVert.add(pair("Track", "Tracks"));
		var disc = pair("Disc", "Discs");
		disc.margin_top = disc.margin_bottom = 5;
		numerVert.add(disc);
		foreach(var name in new string[] { "Genre", "Grouping", "Year", "BPM", "Rating" }) {
			fields.get(name).margin_top = fields.get(name).margin_bottom = 5;
			numerVert.add(fields.get(name));
		}
		
		horiz.set_size_request(300, -1);
		fields.get("Comment").set_size_request(-1, 100);
		
		horiz.add(UI.wrap_alignment(textVert, 0, 30, 0, 0));
		numerVert.hexpand = true;
		numerVert.halign = Align.END; // at the right edge
		horiz.add(numerVert);
		rv.add(horiz);
		
		return rv;
	}
	
	/** Two fields side by side: a number and its total */
	Box pair(string a, string b) {
		var box = new Box(Orientation.HORIZONTAL, 6);
		box.add(fields.get(a));
		box.add(fields.get(b));
		return box;
	}
	
	/** A page of fields one under the other */
	Viewport page(string[] names) {
		var box = new Box(Orientation.VERTICAL, 0);
		box.margin = 10;
		foreach(var name in names) {
			fields.get(name).margin_bottom = 10;
			fields.get(name).set_width_request(380);
			box.add(fields.get(name));
		}
		var rv = new Viewport(null, null);
		rv.add(box);
		return rv;
	}
	
	public HashMap<string, Viewport> get_extra_views() {
		var rv = new HashMap<string, Viewport>();
		
		rv.set(_("Sorting"), page({ "Sort Title", "Sort Artist", "Sort Album Artist", "Sort Album", "Sort Composer" }));
		var options = page({ "Volume", "Compilation", "Skip Shuffle", "Remember Position" });
		var hint = new Label(_("The volume adjustment raises or lowers this song next to the others: +100 % doubles it, −100 % silences it."));
		hint.wrap = true;
		hint.max_width_chars = 50;
		hint.xalign = 0;
		hint.get_style_context().add_class("dim-label");
		((Box)options.get_child()).add(hint);
		rv.set(_("Options"), options);
		rv.set(_("Artwork"), get_artwork_viewport());
		rv.set(_("Lyrics"), get_lyrics_viewport());
		
		return rv;
	}
	
	/* ===== Artwork: the album cover of the songs being edited ===== */
	
	Viewport get_artwork_viewport() {
		var box = new Box(Orientation.VERTICAL, 8);
		box.margin = 10;
		artwork = new Image();
		artwork.set_size_request(240, 240);
		box.add(artwork);
		
		var choose = new Button.with_label(_("Choose Image…"));
		var download = new Button.with_label(_("Download"));
		var embed = new Button.with_label(_("Embed in File"));
		download.tooltip_text = _("Look the cover up on MusicBrainz and the Apple catalogue");
		embed.tooltip_text = CoverEmbedder.available() ? _("Write the cover into the music files")
		                                               : _("This build of BeatBox can't write covers into files (it needs TagLib 2)");
		embed.sensitive = CoverEmbedder.available();
		var buttons = new Box(Orientation.HORIZONTAL, 6);
		buttons.halign = Align.CENTER;
		buttons.add(choose);
		buttons.add(download);
		buttons.add(embed);
		box.add(buttons);
		
		artworkStatus = new Label("");
		artworkStatus.wrap = true;
		artworkStatus.max_width_chars = 50;
		artworkStatus.get_style_context().add_class("dim-label");
		box.add(artworkStatus);
		
		choose.clicked.connect(choose_artwork);
		download.clicked.connect(download_artwork);
		embed.clicked.connect(() => {
			artworkStatus.label = _("Writing…");
			CoverEmbedder.embed(targets, (written, failed) => {
				artworkStatus.label = (failed == 0) ? ngettext("Written into %d file.", "Written into %d files.", written).printf(written)
				                                    : _("Written into %d files; %d failed.").printf(written, failed);
			});
		});
		show_artwork();
		
		var rv = new Viewport(null, null);
		rv.add(box);
		return rv;
	}
	
	void show_artwork() {
		if(artwork == null || current_media == null)
			return;
		Gdk.Pixbuf? pix = null;
		try {
			pix = new Gdk.Pixbuf.from_file_at_scale(App.covers.get_cached_album_art_path(App.covers.get_media_coverart_key(current_media)), 240, 240, true);
		} catch(Error err) {}
		if(pix == null)
			pix = App.covers.get_album_art_from_media(current_media) ?? App.covers.DEFAULT_COVER_SHADOW;
		artwork.pixbuf = pix;
		artworkStatus.label = (targets.size > 1) ? _("Changes here apply to the albums of all the selected songs.") : "";
	}
	
	/** The cover of every album among the songs being edited becomes pix */
	void set_artwork(Gdk.Pixbuf pix) {
		var done = new HashSet<string>();
		foreach(var m in targets) {
			if(done.add(App.covers.get_media_coverart_key(m))) {
				App.covers.save_album_art_in_cache(m, pix);
				App.covers.set_album_art(m, pix, true);
			}
		}
		show_artwork();
	}
	
	void choose_artwork() {
		var chooser = new FileChooserNative(_("Choose Image"), (Gtk.Window)artwork.get_toplevel(), FileChooserAction.OPEN, _("Open"), _("Cancel"));
		var filter = new FileFilter();
		filter.add_pixbuf_formats();
		chooser.filter = filter;
		if(chooser.run() == ResponseType.ACCEPT) {
			try {
				set_artwork(new Gdk.Pixbuf.from_file(chooser.get_filename()));
			} catch(Error err) {
				artworkStatus.label = _("Could not open the image: %s").printf(err.message);
			}
		}
	}
	
	void download_artwork() {
		var m = current_media;
		artworkStatus.label = _("Searching…");
		new Thread<void*>("cover-download", () => {
			var pix = ((CoverManager)App.covers).download_cover(m.album_artist != "" ? m.album_artist : m.artist, m.album);
			Idle.add(() => {
				if(pix != null)
					set_artwork(pix);
				else
					artworkStatus.label = _("No cover found for “%s”.").printf(m.album);
				return false;
			});
			return null;
		});
	}
	
	/* ===== Identify ===== */
	
	void identify() {
		if(App.settings.lastfm.acoustid_key == "") {
			var dialog = new MessageDialog((Gtk.Window)identifyButton.get_toplevel(), DialogFlags.MODAL, MessageType.INFO, ButtonsType.CLOSE,
			                               _("Identifying songs needs an AcoustID application key"));
			dialog.secondary_text = _("Register a free application at acoustid.org/new-application and paste its key in Preferences › Last.fm.");
			dialog.run();
			dialog.destroy();
			return;
		}
		var path = File.new_for_uri(current_media.uri).get_path();
		if(path == null)
			return;
		identifyButton.sensitive = false;
		identifyButton.label = _("Identifying…");
		new Thread<void*>("identify", () => {
			string? error;
			var matches = AcoustId.identify(path, out error);
			Idle.add(() => {
				identifyButton.sensitive = true;
				identifyButton.label = _("Identify…");
				if(identifyButton.get_toplevel() is Gtk.Window && identifyButton.get_toplevel().visible)
					show_matches(matches, error);
				return false;
			});
			return null;
		});
	}
	
	void show_matches(Gee.List<AcoustId.Match> matches, string? error) {
		var parent = (Gtk.Window)identifyButton.get_toplevel();
		if(matches.size == 0) {
			var dialog = new MessageDialog(parent, DialogFlags.MODAL, MessageType.INFO, ButtonsType.CLOSE,
			                               error != null ? _("Identification failed") : _("No matches found"));
			dialog.secondary_text = error ?? _("AcoustID doesn't know this recording.");
			dialog.run();
			dialog.destroy();
			return;
		}
		var dialog = new Dialog.with_buttons(_("Identification results"), parent, DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
		                                     _("Cancel"), ResponseType.CANCEL, _("Apply"), ResponseType.OK);
		var store = new Gtk.ListStore(4, typeof(string), typeof(string), typeof(string), typeof(string));
		foreach(var m in matches) {
			TreeIter iter;
			store.append(out iter);
			store.set(iter, 0, "%d %%".printf(m.score), 1, m.title, 2, m.artist, 3, m.album);
		}
		var view = new TreeView.with_model(store);
		string[] titles = { _("Score"), _("Title"), _("Artist"), _("Album") };
		for(int i = 0; i < 4; i++)
			view.insert_column_with_attributes(-1, titles[i], new CellRendererText() { ellipsize = Pango.EllipsizeMode.END, width_chars = i == 0 ? 6 : 18 }, "text", i);
		view.get_selection().select_path(new TreePath.first());
		view.row_activated.connect(() => dialog.response(ResponseType.OK));
		var scroll = new ScrolledWindow(null, null);
		scroll.set_size_request(620, 260);
		scroll.add(view);
		var label = new Label(_("Select a result to apply its title, artist and album to this song:"));
		label.xalign = 0;
		var box = dialog.get_content_area();
		box.spacing = 8;
		box.margin = 10;
		box.add(label);
		box.add(scroll);
		dialog.set_default_response(ResponseType.OK);
		dialog.show_all();
		bool apply = dialog.run() == ResponseType.OK;
		var chosen = view.get_selection().get_selected_rows(null);
		if(apply && chosen.length() > 0) {
			var m = matches[chosen.data.get_indices()[0]];
			fields.get("Title").set_value(m.title);
			fields.get("Artist").set_value(m.artist);
			if(m.album != "")
				fields.get("Album").set_value(m.album);
		}
		dialog.destroy();
	}
	
	/* ===== Lyrics ===== */
	
	Viewport get_lyrics_viewport() {
		Viewport rv = new Viewport(null, null);
		
		var padding = new Box(Orientation.VERTICAL, 10);
		lyricsContent = new Box(Orientation.VERTICAL, 10);
		
		var download = new Button.with_label(_("Download Lyrics"));
		download.tooltip_text = _("Look the lyrics up on lrclib.net (they replace the ones here)");
		download.clicked.connect(() => fetch_lyrics(true));
		lyricsStatus = new Label("");
		lyricsStatus.ellipsize = Pango.EllipsizeMode.END;
		lyricsStatus.xalign = 0;
		lyricsStatus.get_style_context().add_class("dim-label");
		var row = new Box(Orientation.HORIZONTAL, 8);
		row.add(download);
		row.add(lyricsStatus);
		
		lyricsText = new TextView();
		lyricsText.set_wrap_mode(WrapMode.WORD_CHAR);
		if(current_media != null)	lyricsText.get_buffer().text = current_media.lyrics;
		
		ScrolledWindow scroll = new ScrolledWindow(null, null);
		Viewport viewport = new Viewport(null, null);
		
		viewport.set_shadow_type(ShadowType.ETCHED_IN);
		scroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		
		viewport.add(lyricsText);
		scroll.add(viewport);
		
		lyricsContent.add(row);
		scroll.vexpand = true;
		lyricsContent.add(scroll);
		
		lyricsText.set_size_request(400, -1);
		scroll.set_size_request(400, -1);
		viewport.set_size_request(400, -1);
		
		lyricsContent.vexpand = true;
		lyricsContent.sensitive = single; // one song's lyrics
		padding.add(lyricsContent);
		rv.add(padding);
		
		if(single)
			fetch_lyrics(false);
		return rv;
	}
	
	public void change_media(Media sum) {
		current_media = sum;
		var list = new LinkedList<Media>();
		list.add(sum);
		targets = list;
		single = true;
		
		fields.get("Title").set_value(sum.title);
		fields.get("Artist").set_value(sum.artist);
		fields.get("Album Artist").set_value(sum.album_artist);
		fields.get("Album").set_value(sum.album);
		fields.get("Genre").set_value(sum.genre);
		fields.get("Comment").set_value(sum.comment);
		fields.get("Track").set_value((int)sum.track);
		fields.get("Tracks").set_value((int)sum.track_count);
		fields.get("Disc").set_value((int)sum.album_number);
		fields.get("Discs").set_value((int)sum.album_count);
		fields.get("Year").set_value((int)sum.year);
		fields.get("BPM").set_value((int)sum.bpm);
		fields.get("Rating").set_value((int)sum.rating);
		fields.get("Composer").set_value(sum.composer);
		fields.get("Grouping").set_value(sum.grouping);
		fields.get("Sort Title").set_value(sum.sort_title);
		fields.get("Sort Artist").set_value(sum.sort_artist);
		fields.get("Sort Album Artist").set_value(sum.sort_album_artist);
		fields.get("Sort Album").set_value(sum.sort_album);
		fields.get("Sort Composer").set_value(sum.sort_composer);
		fields.get("Volume").set_value(sum.volume_adjust);
		fields.get("Compilation").set_value(sum.compilation);
		fields.get("Skip Shuffle").set_value(sum.skip_shuffle);
		fields.get("Remember Position").set_value(sum.remember_position);
		
		identifyButton.sensitive = AcoustId.available();
		show_artwork();
		if(lyricsText != null) {
			lyricsContent.sensitive = true;
			lyricsText.get_buffer().text = current_media.lyrics;
			fetch_lyrics(false);
		}
	}
	
	public void save_medias(Collection<Media> medias) {
		foreach(Media s in medias) {
			if(fields.get("Title").checked())
				s.title = fields.get("Title").get_value().get_string();
			if(fields.get("Artist").checked())
				s.artist = fields.get("Artist").get_value().get_string();
			if(fields.get("Album Artist").checked())
				s.album_artist = fields.get("Album Artist").get_value().get_string();
			if(fields.get("Album").checked())
				s.album = fields.get("Album").get_value().get_string();
			if(fields.get("Genre").checked())
				s.genre = fields.get("Genre").get_value().get_string();
			if(fields.get("Composer").checked())
				s.composer = fields.get("Composer").get_value().get_string();
			if(fields.get("Grouping").checked())
				s.grouping = fields.get("Grouping").get_value().get_string();
			if(fields.get("Comment").checked())
				s.comment = fields.get("Comment").get_value().get_string();
				
			if(fields.get("Track").checked())
				s.track = fields.get("Track").get_value().get_int();
			if(fields.get("Tracks").checked())
				s.track_count = fields.get("Tracks").get_value().get_int();
			if(fields.get("Disc").checked())
				s.album_number = fields.get("Disc").get_value().get_int();
			if(fields.get("Discs").checked())
				s.album_count = fields.get("Discs").get_value().get_int();
			if(fields.get("Year").checked())
				s.year = fields.get("Year").get_value().get_int();
			if(fields.get("BPM").checked())
				s.bpm = fields.get("BPM").get_value().get_int();
			if(fields.get("Rating").checked())
				s.rating = fields.get("Rating").get_value().get_int();
			
			if(fields.get("Sort Title").checked())
				s.sort_title = fields.get("Sort Title").get_value().get_string();
			if(fields.get("Sort Artist").checked())
				s.sort_artist = fields.get("Sort Artist").get_value().get_string();
			if(fields.get("Sort Album Artist").checked())
				s.sort_album_artist = fields.get("Sort Album Artist").get_value().get_string();
			if(fields.get("Sort Album").checked())
				s.sort_album = fields.get("Sort Album").get_value().get_string();
			if(fields.get("Sort Composer").checked())
				s.sort_composer = fields.get("Sort Composer").get_value().get_string();
			
			if(fields.get("Volume").checked())
				s.volume_adjust = fields.get("Volume").get_value().get_int();
			if(fields.get("Compilation").checked())
				s.compilation = fields.get("Compilation").get_value().get_boolean();
			if(fields.get("Skip Shuffle").checked())
				s.skip_shuffle = fields.get("Skip Shuffle").get_value().get_boolean();
			if(fields.get("Remember Position").checked())
				s.remember_position = fields.get("Remember Position").get_value().get_boolean();
				
			// the lyrics belong to one song
			if(single && lyricsText != null)
				s.lyrics = lyricsText.get_buffer().text;
		}
		
		App.library.song_library.update_medias(medias, true, true, true);
	}
	
	/** From lrclib.net; without overwrite, only when the song has none yet */
	void fetch_lyrics(bool overwrite) {
		if(current_media == null || lyricsText == null || (!overwrite && current_media.lyrics.strip() != ""))
			return;
		
		var m = current_media;
		uint request = ++lyrics_request;
		lyricsStatus.label = _("Searching…");
		new Thread<void*>("lyrics", () => {
			string found = SyncedLyrics.fetch_plain(m);
			Idle.add(() => {
				if(request != lyrics_request)
					return false;
				if(found != "") {
					lyricsText.get_buffer().text = found;
					lyricsStatus.label = _("From lrclib.net");
				}
				else
					lyricsStatus.label = _("No lyrics found for “%s”.").printf(m.title);
				return false;
			});
			return null;
		});
	}
}
