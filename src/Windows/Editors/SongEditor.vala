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


/**
 * The song pages of the "Get Info" window: Summary (one song), Info, Comments,
 * Sorting, Options, Lyrics and Pictures (one song), Artwork (several songs).
 */
public class BeatBox.SongEditor : GLib.Object, MediaEditorInterface {
	Media current_media;
	Collection<Media> targets; // the songs being edited
	bool single = true;        // one song (lyrics, pictures and Identify are per song)
	
	TextView lyricsText;
	Label lyricsStatus;
	uint lyrics_request = 0; // drops answers for a song no longer shown
	
	Image artwork;
	int artwork_size = 120;
	Label artworkStatus;
	Button identifyButton;
	Label identifyStatus;
	
	// filled when the file has been read (Summary and Pictures)
	Label formatValue;
	Label channelsValue;
	Label encoderValue;
	Label bitrateValue;
	Box picturesBox;
	
	HashMap<string, FieldEditor> fields;// a hashmap with each property and corresponding editor
	
	public SongEditor() {
		fields = new HashMap<string, FieldEditor>();
	}
	
	public Collection<FieldEditor> get_fields() {
		return fields.values;
	}
	
	/** A page: its rows one under the other, with the window's margins */
	static Box page_box(int spacing = 8) {
		var box = new Box(Orientation.VERTICAL, spacing);
		box.margin_start = box.margin_end = 14;
		box.margin_top = 16;
		box.margin_bottom = 12;
		return box;
	}
	
	static Viewport wrap(Widget content) {
		var rv = new Viewport(null, null);
		rv.shadow_type = ShadowType.NONE;
		rv.add(content);
		return rv;
	}
	
	/** Fields side by side on one row; the ones after the first with a short label */
	Box row(string[] names, int[] label_widths) {
		var box = new Box(Orientation.HORIZONTAL, 14);
		for(int i = 0; i < names.length; i++) {
			var field = (FieldEditorImpl)fields.get(names[i]);
			if(i < label_widths.length)
				field.set_label_width(label_widths[i]);
			box.add(field);
		}
		return box;
	}
	
	public Viewport get_metadata_view(Collection<Media> originals) {
		fields = new HashMap<string, FieldEditor>();
		targets = originals;
		single = originals.size == 1;
		current_media = originals.to_array()[0];
		Media sum = current_media.copy();
		
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
		
		fields.set("Title", new FieldEditorImpl.for_string(_("Name:"), sum.title));
		fields.set("Artist", new FieldEditorImpl.for_string(_("Artist:"), sum.artist));
		fields.set("Album Artist", new FieldEditorImpl.for_string(_("Album artist:"), sum.album_artist));
		fields.set("Album", new FieldEditorImpl.for_string(_("Album:"), sum.album));
		fields.set("Genre", new FieldEditorImpl.for_string(_("Genre:"), sum.genre));
		fields.set("Composer", new FieldEditorImpl.for_string(_("Composer:"), sum.composer));
		fields.set("Grouping", new FieldEditorImpl.for_string(_("Grouping:"), sum.grouping));
		fields.set("Comment", new FieldEditorImpl.for_long_string("", sum.comment));
		fields.set("Track", new FieldEditorImpl.for_integer(_("Track number:"), (int)sum.track, 0, 999));
		fields.set("Tracks", new FieldEditorImpl.for_integer(_("of"), (int)sum.track_count, 0, 999));
		fields.set("Disc", new FieldEditorImpl.for_integer(_("Disc number:"), (int)sum.album_number, 0, 99));
		fields.set("Discs", new FieldEditorImpl.for_integer(_("of"), (int)sum.album_count, 0, 99));
		fields.set("Year", new FieldEditorImpl.for_integer(_("Year:"), (int)sum.year, 0, 9999));
		fields.set("BPM", new FieldEditorImpl.for_integer(_("BPM:"), (int)sum.bpm, 0, 999));
		fields.set("Rating", new FieldEditorImpl.for_rating(_("Rating:"), (int)sum.rating));
		fields.set("Compilation", new FieldEditorImpl.for_bool("", _("Part of a compilation by various artists"), sum.compilation));
		
		fields.set("Sort Title", new FieldEditorImpl.for_string(_("Sort name:"), sum.sort_title));
		fields.set("Sort Artist", new FieldEditorImpl.for_string(_("Sort artist:"), sum.sort_artist));
		fields.set("Sort Album Artist", new FieldEditorImpl.for_string(_("Sort album artist:"), sum.sort_album_artist));
		fields.set("Sort Album", new FieldEditorImpl.for_string(_("Sort album:"), sum.sort_album));
		fields.set("Sort Composer", new FieldEditorImpl.for_string(_("Sort composer:"), sum.sort_composer));
		
		fields.set("Volume", new FieldEditorImpl.for_slider(_("Volume adjustment:"), sum.volume_adjust, -100, 100, _("None")));
		fields.set("Skip Shuffle", new FieldEditorImpl.for_bool("", _("Skip when shuffling"), sum.skip_shuffle));
		fields.set("Remember Position", new FieldEditorImpl.for_bool("", _("Remember the playback position"), sum.remember_position));
		
		var box = page_box(6);
		foreach(var name in new string[] { "Title", "Artist", "Album Artist", "Album", "Composer", "Genre" })
			box.add(fields.get(name));
		box.add(row({ "Year", "BPM" }, { 130, 0 }));
		((FieldEditorImpl)fields.get("BPM")).set_label_width(-1); // as wide as its text
		box.add(row({ "Track", "Tracks" }, { 130, -1 }));
		box.add(row({ "Disc", "Discs" }, { 130, -1 }));
		box.add(fields.get("Grouping"));
		box.add(fields.get("Rating"));
		box.add(fields.get("Compilation"));
		return wrap(box);
	}
	
	public HashMap<string, Viewport> get_extra_views() {
		var rv = new HashMap<string, Viewport>();
		
		var comments = page_box();
		((FieldEditorImpl)fields.get("Comment")).set_label_width(0);
		fields.get("Comment").vexpand = true;
		comments.add(fields.get("Comment"));
		rv.set(_("Comments"), wrap(comments));
		
		var sorting = page_box();
		foreach(var name in new string[] { "Sort Title", "Sort Artist", "Sort Album Artist", "Sort Album", "Sort Composer" }) {
			((FieldEditorImpl)fields.get(name)).set_label_width(200);
			sorting.add(fields.get(name));
		}
		rv.set(_("Sorting"), wrap(sorting));
		
		var options = page_box(10);
		((FieldEditorImpl)fields.get("Volume")).set_label_width(200);
		options.add(fields.get("Volume"));
		foreach(var name in new string[] { "Remember Position", "Skip Shuffle" }) {
			((FieldEditorImpl)fields.get(name)).set_label_width(200);
			options.add(fields.get(name));
		}
		var hint = new Label(_("The volume adjustment raises or lowers this song next to the others: +100 % doubles it, −100 % silences it."));
		hint.wrap = true;
		hint.max_width_chars = 60;
		hint.xalign = 0;
		hint.margin_top = 8;
		hint.get_style_context().add_class("ti-meta");
		options.add(hint);
		rv.set(_("Options"), wrap(options));
		
		if(single) {
			rv.set(_("Summary"), get_summary_page());
			rv.set(_("Lyrics"), get_lyrics_page());
			rv.set(_("Pictures"), get_pictures_page());
			read_file();
		}
		else
			rv.set(_("Artwork"), get_artwork_page());
		
		return rv;
	}
	
	/* ===== Summary ===== */
	
	static Label summary_value(string text) {
		var l = new Label(text);
		l.xalign = 0;
		l.selectable = true;
		l.can_focus = false;
		return l;
	}
	
	Viewport get_summary_page() {
		var m = current_media;
		var box = page_box(10);
		
		var top = new Box(Orientation.HORIZONTAL, 16);
		var art = new Box(Orientation.VERTICAL, 6);
		art.valign = Align.START;
		artwork = new Image();
		artwork_size = 120;
		var frame = new Frame(null);
		frame.get_style_context().add_class("album-cell-frame");
		frame.halign = Align.START;
		frame.add(artwork);
		art.add(frame);
		art.add(cover_buttons(true));
		artworkStatus = new Label("");
		artworkStatus.xalign = 0;
		artworkStatus.wrap = true;
		artworkStatus.max_width_chars = 40;
		artworkStatus.get_style_context().add_class("ti-meta");
		art.add(artworkStatus);
		top.add(art);
		
		var titles = new Box(Orientation.VERTICAL, 3);
		titles.valign = Align.START;
		titles.hexpand = true;
		var title = new Label(m.length > 0 ? "%s (%s)".printf(m.title, TimeUtils.pretty_time_mins(m.length)) : m.title);
		title.get_style_context().add_class("ti-summary-title");
		var artist = new Label(m.artist);
		var album = new Label(m.album);
		album.get_style_context().add_class("dim-label");
		foreach(var l in new Label[] { title, artist, album }) {
			l.xalign = 0;
			l.wrap = true;
			l.max_width_chars = 60;
			l.selectable = true;
			l.can_focus = false;
			titles.add(l);
		}
		top.add(titles);
		box.add(top);
		box.add(new Separator(Orientation.HORIZONTAL));
		
		var file = File.new_for_uri(m.uri);
		string size = m.file_size > 0 ? format_size(m.file_size) : "—", modified = "—";
		try {
			var info = file.query_info(FileAttribute.STANDARD_SIZE + "," + FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
			size = format_size(info.get_size());
			var date = info.get_modification_date_time();
			if(date != null)
				modified = date.to_local().format("%x %H:%M");
		} catch(Error err) {}
		string ext = file.get_basename() != null && "." in file.get_basename() ? file.get_basename().substring(file.get_basename().last_index_of(".") + 1).up() : "";
		
		formatValue = summary_value("…");
		channelsValue = summary_value("…");
		encoderValue = summary_value("…");
		bitrateValue = summary_value(m.bitrate > 0 ? "%u kbps".printf(m.bitrate) : "…");
		var grid = new Grid();
		grid.row_spacing = 5;
		grid.column_spacing = 14;
		int r = 0;
		Widget[] rows = {
			new Label(_("Kind:")), summary_value(ext != "" ? _("%s audio file").printf(ext) : _("Audio file")),
			new Label(_("Format:")), formatValue,
			new Label(_("Size:")), summary_value(size),
			new Label(_("Bit rate:")), bitrateValue,
			new Label(_("Sample rate:")), summary_value(m.samplerate > 0 ? "%u Hz".printf(m.samplerate) : "—"),
			new Label(_("Channels:")), channelsValue,
			new Label(_("Plays:")), summary_value(m.play_count.to_string()),
			new Label(_("Last played:")), summary_value(m.last_played > 0 ? TimeUtils.pretty_timestamp_from_uint(m.last_played) : _("Never")),
			new Label(_("Date modified:")), summary_value(modified),
			new Label(_("Encoded with:")), encoderValue
		};
		for(int i = 0; i < rows.length; i += 2, r++) {
			((Label)rows[i]).xalign = 1;
			rows[i].get_style_context().add_class("ti-sum-key");
			grid.attach(rows[i], 0, r);
			grid.attach(rows[i + 1], 1, r);
		}
		box.add(grid);
		
		var where = new Label(file.get_path() ?? m.uri);
		where.xalign = 0;
		where.wrap = true;
		where.wrap_mode = Pango.WrapMode.CHAR;
		where.selectable = true;
		where.can_focus = false;
		where.get_style_context().add_class("ti-uri");
		box.add(where);
		
		// "Identify": fills the name, artist and album from the song's sound (AcoustID)
		identifyButton = new Button.with_label(_("Identify…"));
		identifyButton.get_style_context().add_class("ti-cover-btn");
		identifyButton.tooltip_text = AcoustId.available() ? _("Look the song up by its sound on AcoustID")
		                                                   : _("Needs fpcalc, from Chromaprint (the chromaprint or libchromaprint-tools package)");
		identifyButton.sensitive = AcoustId.available() && file.get_path() != null;
		identifyButton.clicked.connect(identify);
		identifyStatus = new Label("");
		identifyStatus.get_style_context().add_class("ti-meta");
		var id_row = new Box(Orientation.HORIZONTAL, 8);
		id_row.add(identifyButton);
		id_row.add(identifyStatus);
		box.add(id_row);
		
		show_artwork();
		return wrap(box);
	}
	
	/** Reads the file on a worker thread for the Summary and Pictures pages */
	void read_file() {
		if(!current_media.uri.has_prefix("file://")) {
			formatValue.label = channelsValue.label = encoderValue.label = bitrateValue.label = "—";
			return;
		}
		string uri = current_media.uri;
		new Thread<void*>("song-info", () => {
			var facts = TrackReport.read_file(uri, 200);
			Idle.add(() => {
				if(formatValue.get_toplevel() is Gtk.Window) // the page is still there
					show_file_facts(facts);
				return false;
			});
			return null;
		});
	}
	
	void show_file_facts(TrackReport.FileFacts facts) {
		formatValue.label = facts.codec != "" ? facts.codec : "—";
		channelsValue.label = facts.channels != "" ? facts.channels : "—";
		encoderValue.label = facts.encoder != "" ? facts.encoder : _("Not known");
		if(bitrateValue.label == "…")
			bitrateValue.label = facts.bitrate > 0 ? "%u kbps".printf(facts.bitrate) : "—";
		
		picturesBox.foreach((w) => w.destroy());
		if(facts.images.length == 0) {
			var none = new Label(facts.error ?? _("This file has no pictures inside it."));
			none.get_style_context().add_class("dim-label");
			none.xalign = 0;
			picturesBox.add(none);
		}
		for(int i = 0; i < facts.images.length; i++) {
			var row = new Box(Orientation.HORIZONTAL, 14);
			var frame = new Frame(null);
			frame.get_style_context().add_class("album-cell-frame");
			frame.valign = Align.START;
			frame.add(new Image.from_pixbuf(facts.images[i]));
			row.add(frame);
			var text = new Label(facts.image_texts[i]);
			text.xalign = 0;
			text.valign = Align.START;
			text.selectable = true;
			text.can_focus = false;
			row.add(text);
			picturesBox.add(row);
		}
		picturesBox.show_all();
	}
	
	Viewport get_pictures_page() {
		picturesBox = page_box(12);
		var reading = new Label(_("Reading the file…"));
		reading.get_style_context().add_class("dim-label");
		reading.xalign = 0;
		picturesBox.add(reading);
		var scroll = new ScrolledWindow(null, null);
		scroll.hscrollbar_policy = PolicyType.NEVER;
		scroll.add(picturesBox);
		scroll.vexpand = true;
		var rv = new Viewport(null, null);
		rv.shadow_type = ShadowType.NONE;
		rv.add(scroll);
		return rv;
	}
	
	/* ===== Artwork: the album cover of the songs being edited ===== */
	
	Box cover_buttons(bool small) {
		var choose = new Button.with_label(_("Add Artwork…"));
		var download = new Button.with_label(_("Download Artwork"));
		var embed = new Button.with_label(_("Embed in File"));
		download.tooltip_text = _("Look the cover up on MusicBrainz and the Apple catalogue");
		embed.tooltip_text = CoverEmbedder.available() ? _("Write the cover into the music files (the whole album)")
		                                               : _("This build of BeatBox can't write covers into files (it needs TagLib 2)");
		embed.sensitive = CoverEmbedder.available();
		var buttons = new Box(Orientation.HORIZONTAL, 4);
		foreach(var b in new Button[] { choose, download, embed }) {
			if(small)
				b.get_style_context().add_class("ti-cover-btn");
			buttons.add(b);
		}
		choose.clicked.connect(choose_artwork);
		download.clicked.connect(download_artwork);
		embed.clicked.connect(() => {
			artworkStatus.label = _("Writing…");
			CoverEmbedder.embed(targets, (written, failed) => {
				artworkStatus.label = (failed == 0) ? ngettext("Written into %d file.", "Written into %d files.", written).printf(written)
				                                    : _("Written into %d files; %d failed.").printf(written, failed);
			});
		});
		return buttons;
	}
	
	Viewport get_artwork_page() {
		var box = page_box(10);
		artwork = new Image();
		artwork_size = 240;
		var frame = new Frame(null);
		frame.get_style_context().add_class("album-cell-frame");
		frame.halign = Align.CENTER;
		frame.add(artwork);
		box.add(frame);
		var buttons = cover_buttons(false);
		buttons.halign = Align.CENTER;
		box.add(buttons);
		artworkStatus = new Label("");
		artworkStatus.wrap = true;
		artworkStatus.max_width_chars = 50;
		artworkStatus.get_style_context().add_class("ti-meta");
		box.add(artworkStatus);
		show_artwork();
		artworkStatus.label = _("Changes here apply to the albums of all the selected songs.");
		return wrap(box);
	}
	
	void show_artwork() {
		if(artwork == null || current_media == null)
			return;
		Gdk.Pixbuf? pix = null;
		try {
			pix = new Gdk.Pixbuf.from_file_at_scale(App.covers.get_cached_album_art_path(App.covers.get_media_coverart_key(current_media)), artwork_size, artwork_size, false);
		} catch(Error err) {}
		if(pix == null) {
			var framed = App.covers.get_album_art_from_media(current_media) ?? App.covers.DEFAULT_COVER_SHADOW;
			pix = framed.scale_simple(artwork_size, artwork_size, Gdk.InterpType.BILINEAR);
		}
		artwork.pixbuf = pix;
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
		artworkStatus.label = "";
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
				if(!(artwork.get_toplevel() is Gtk.Window))
					return false;
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
	
	Viewport get_lyrics_page() {
		var box = page_box(8);
		
		lyricsText = new TextView();
		lyricsText.set_wrap_mode(WrapMode.WORD_CHAR);
		lyricsText.top_margin = lyricsText.bottom_margin = 6;
		lyricsText.left_margin = lyricsText.right_margin = 8;
		lyricsText.get_buffer().text = current_media.lyrics;
		var scroll = new ScrolledWindow(null, null);
		scroll.shadow_type = ShadowType.IN;
		scroll.hscrollbar_policy = PolicyType.NEVER;
		scroll.vexpand = true;
		scroll.add(lyricsText);
		box.add(scroll);
		
		var download = new Button.with_label(_("Download Lyrics"));
		download.tooltip_text = _("Look the lyrics up on lrclib.net (they replace the ones here)");
		download.clicked.connect(() => fetch_lyrics(true));
		lyricsStatus = new Label("");
		lyricsStatus.ellipsize = Pango.EllipsizeMode.END;
		lyricsStatus.xalign = 0;
		lyricsStatus.get_style_context().add_class("ti-meta");
		var row = new Box(Orientation.HORIZONTAL, 8);
		row.add(download);
		row.add(lyricsStatus);
		box.add(row);
		
		fetch_lyrics(false);
		return wrap(box);
	}
	
	/** The window builds the pages again for another song */
	public void change_media(Media m) {
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
			if(fields.get("Compilation").checked())
				s.compilation = fields.get("Compilation").get_value().get_boolean();
			
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
				if(request != lyrics_request || !(lyricsText.get_toplevel() is Gtk.Window))
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
