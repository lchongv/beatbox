/*
 * The information panel at the right of the lists: a full report on the song
 * playing, read from the file itself (GStreamer's Discoverer): its format and
 * audio stream, every tag it carries, the pictures inside it, and what the
 * library knows about it (plays, skips, rating, dates).
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

using Gtk;

public class BeatBox.TrackReport : ScrolledWindow {
	Box content;
	uint request = 0; // drops reports of songs no longer playing

	/* What the file says, read on a worker thread: plain data, the widgets are made on the main loop */
	class FileFacts {
		public string[] format = {};  // label, value, label, value...
		public string[] tags = {};
		public Gdk.Pixbuf[] images = {};
		public string[] image_texts = {};
		public string? error = null;
	}

	public TrackReport () {
		hscrollbar_policy = PolicyType.NEVER;
		get_style_context ().add_class ("track-report");
		content = new Box (Orientation.VERTICAL, 4);
		content.margin = 10;
		add (content);

		App.playback.media_played.connect ((m, old) => refresh ());
		App.playback.playback_stopped.connect ((m) => refresh ());
		App.library.medias_updated.connect ((medias) => {
			if (App.playback.media_active && App.playback.current_media in medias)
				refresh ();
		});
		map.connect (refresh); // nothing is read while the panel is hidden
		refresh ();
	}

	void refresh () {
		if (!get_mapped ())
			return;
		uint mine = ++request;
		content.foreach ((w) => w.destroy ());

		var m = App.playback.media_active ? App.playback.current_media : null;
		if (m == null) {
			var nothing = new Label (_("Nothing is playing."));
			nothing.get_style_context ().add_class ("dim-label");
			nothing.margin_top = 20;
			content.add (nothing);
			content.show_all ();
			return;
		}

		var title = new Label ("");
		title.set_markup ("<b><big>%s</big></b>".printf (Markup.escape_text (m.title)));
		title.wrap = true;
		title.xalign = 0;
		content.add (title);
		var who = new Label ((m.media_type == MediaType.STATION) ? m.artist : string.joinv (" — ", { m.artist, m.album }));
		who.wrap = true;
		who.xalign = 0;
		who.get_style_context ().add_class ("dim-label");
		content.add (who);

		var reading = new Label (_("Reading the file…"));
		reading.get_style_context ().add_class ("dim-label");
		reading.xalign = 0;
		reading.margin_top = 10;
		content.add (reading);
		add_section (_("Library"), library_facts (m));
		content.show_all ();

		// a stream would be opened just to look at it: only files are read
		if (!m.uri.has_prefix ("file://")) {
			reading.label = _("An internet stream: there is no file to read.");
			return;
		}
		string uri = m.uri;
		new Thread<void*> ("track-report", () => {
			var facts = read_file (uri);
			Idle.add (() => {
				if (mine == request) {
					reading.destroy ();
					show_file_facts (facts);
				}
				return false;
			});
			return null;
		});
	}

	void show_file_facts (FileFacts facts) {
		if (facts.error != null) {
			add_section (_("File"), { _("Error"), facts.error });
			content.show_all ();
			return;
		}
		// before the library section, which is already there
		var library = content.get_children ().last ().data;
		var heading = content.get_children ().nth_data (content.get_children ().length () - 2);
		content.remove (heading);
		content.remove (library);

		add_section (_("Format and audio"), facts.format);
		add_section (_("Tags in the file"), facts.tags.length > 0 ? facts.tags : new string[] { _("None"), "" });
		add_heading (_("Embedded pictures"));
		if (facts.images.length == 0)
			add_section (null, { _("None"), "" });
		for (int i = 0; i < facts.images.length; i++) {
			var row = new Box (Orientation.HORIZONTAL, 8);
			row.add (new Image.from_pixbuf (facts.images[i]));
			var text = new Label (facts.image_texts[i]);
			text.xalign = 0;
			text.wrap = true;
			text.selectable = true;
			row.add (text);
			content.add (row);
		}
		content.add (heading);
		content.add (library);
		content.show_all ();
	}

	void add_heading (string text) {
		var heading = new Label ("");
		heading.set_markup ("<b>%s</b>".printf (Markup.escape_text (text)));
		heading.xalign = 0;
		heading.margin_top = 12;
		content.add (heading);
	}

	/** A heading and its label/value pairs, the labels dim and to the right */
	void add_section (string? title, string[] pairs) {
		if (title != null)
			add_heading (title);
		var grid = new Grid ();
		grid.column_spacing = 8;
		grid.row_spacing = 2;
		for (int i = 0; i + 1 < pairs.length; i += 2) {
			var key = new Label (pairs[i]);
			key.xalign = 1;
			key.yalign = 0;
			key.get_style_context ().add_class ("dim-label");
			var val = new Label (pairs[i + 1]);
			val.xalign = 0;
			val.wrap = true;
			val.wrap_mode = Pango.WrapMode.WORD_CHAR;
			val.selectable = true;
			val.can_focus = false;
			val.hexpand = true;
			grid.attach (key, 0, i / 2);
			grid.attach (val, 1, i / 2);
		}
		content.add (grid);
	}

	static string[] library_facts (Media m) {
		string[] rv = {
			_("Plays"), m.play_count.to_string (),
			_("Skips"), m.skip_count.to_string (),
			_("Rating"), (m.rating == 0) ? _("None") : string.nfill (m.rating, '*').replace ("*", "★"),
			_("Added"), (m.date_added == 0) ? _("Unknown") : TimeUtils.pretty_timestamp_from_uint (m.date_added),
			_("Last played"), (m.last_played == 0) ? _("Never") : TimeUtils.pretty_timestamp_from_uint (m.last_played)
		};
		if (m.last_modified != 0) {
			rv += _("Edited");
			rv += TimeUtils.pretty_timestamp_from_uint (m.last_modified);
		}
		if (m.volume_adjust != 0) {
			rv += _("Volume adjustment");
			rv += "%+d %%".printf (m.volume_adjust);
		}
		if (m.skip_shuffle) {
			rv += _("Shuffle");
			rv += _("Skipped when shuffling");
		}
		if (m.uses_resume_pos && m.resume_pos > 0) {
			rv += _("Resumes at");
			rv += TimeUtils.pretty_time_mins (m.resume_pos);
		}
		return rv;
	}

	static string clock (uint64 ns) {
		uint64 ms = ns / Gst.MSECOND;
		uint64 s = ms / 1000;
		return (s >= 3600) ? "%u:%02u:%02u.%03u".printf ((uint)(s / 3600), (uint)(s / 60 % 60), (uint)(s % 60), (uint)(ms % 1000))
		                   : "%u:%02u.%03u".printf ((uint)(s / 60), (uint)(s % 60), (uint)(ms % 1000));
	}

	const string[] LOSSLESS = { "audio/x-flac", "audio/x-alac", "audio/x-wavpack", "audio/x-raw", "audio/x-ape", "audio/x-tta", "audio/x-true-hd" };

	/** Blocking */
	static FileFacts read_file (string uri) {
		var facts = new FileFacts ();
		Gst.PbUtils.DiscovererInfo info;
		try {
			info = new Gst.PbUtils.Discoverer (10 * Gst.SECOND).discover_uri (uri);
		} catch (Error err) {
			facts.error = err.message;
			return facts;
		}

		string[] f = {};
		var file = File.new_for_uri (uri);
		f += _("File"); f += file.get_path ();
		try {
			var file_info = file.query_info (FileAttribute.STANDARD_SIZE + "," + FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
			f += _("Size"); f += "%s (%s bytes)".printf (format_size (file_info.get_size ()), file_info.get_size ().to_string ());
			var modified = file_info.get_modification_date_time ();
			if (modified != null) {
				f += _("File modified"); f += modified.to_local ().format ("%x %X");
			}
		} catch (Error err) {}

		var top = info.get_stream_info ();
		if (top is Gst.PbUtils.DiscovererContainerInfo && top.get_caps () != null) {
			f += _("Container"); f += Gst.PbUtils.get_codec_description (top.get_caps ());
		}
		uint64 duration = info.get_duration ();
		f += _("Duration"); f += clock (duration);

		foreach (var stream in info.get_audio_streams ()) {
			var audio = (Gst.PbUtils.DiscovererAudioInfo) stream;
			var caps = audio.get_caps ();
			if (caps != null) {
				string name = caps.get_structure (0).get_name ();
				f += _("Codec"); f += "%s (%s)".printf (Gst.PbUtils.get_codec_description (caps), (name in LOSSLESS) ? _("lossless") : _("lossy"));
			}
			f += _("Sample rate"); f += "%.1f kHz".printf (audio.get_sample_rate () / 1000.0);
			if (audio.get_depth () > 0 && caps != null && caps.get_structure (0).get_name () in LOSSLESS) { // a lossy one is decoded to whatever depth
				f += _("Bit depth"); f += "%u bits".printf (audio.get_depth ());
			}
			uint ch = audio.get_channels ();
			f += _("Channels"); f += (ch == 1) ? _("Mono") : (ch == 2) ? _("Stereo") : "%u".printf (ch);
		}

		// the average is exact: size over length; the file's own figures beside it
		Gst.TagList? tags = GStreamerTagger.all_tags (info);
		try {
			int64 size = file.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE).get_size ();
			if (duration > 0) {
				string rate = "%.0f kbps".printf (size * 8.0 / (duration / (double) Gst.SECOND) / 1000.0);
				uint nominal = 0, min = 0, max = 0;
				if (tags != null && tags.get_uint (Gst.Tags.MINIMUM_BITRATE, out min) && tags.get_uint (Gst.Tags.MAXIMUM_BITRATE, out max) && min != max)
					rate += " · " + _("variable (%u–%u kbps)").printf (min / 1000, max / 1000);
				else if (tags != null && tags.get_uint (Gst.Tags.NOMINAL_BITRATE, out nominal))
					rate += " · " + _("nominal %u kbps").printf (nominal / 1000);
				f += _("Bitrate (average)"); f += rate;
			}
		} catch (Error err) {}
		facts.format = f;

		if (tags != null) {
			string[] t = {};
			var images = new GenericArray<Gst.Sample> ();
			tags.foreach ((list, tag) => {
				for (uint i = 0; i < list.get_tag_size (tag); i++) {
					unowned GLib.Value? val = list.get_value_index (tag, i);
					if (val.holds (typeof (Gst.Sample))) {
						if (tag == Gst.Tags.IMAGE || tag == Gst.Tags.PREVIEW_IMAGE)
							images.add ((Gst.Sample) val.get_boxed ());
						continue;
					}
					t += Gst.Tags.get_nick (tag) ?? tag;
					t += value_text (val);
				}
			});
			facts.tags = t;

			foreach (var sample in images.data) {
				var buffer = sample.get_buffer ();
				Gst.MapInfo map = {};
				if (buffer == null || !buffer.map (out map, Gst.MapFlags.READ))
					continue;
				try {
					var loader = new Gdk.PixbufLoader ();
					loader.write (map.data);
					loader.close ();
					var pix = loader.get_pixbuf ();
					if (pix != null) {
						string kind = _("Picture");
						unowned Gst.Structure? s = sample.get_info ();
						int type = 0;
						if (s != null && s.get_enum ("image-type", typeof (Gst.Tag.ImageType), out type)) {
							var it = (Gst.Tag.ImageType) type;
							kind = (it == Gst.Tag.ImageType.FRONT_COVER) ? _("Front cover") : (it == Gst.Tag.ImageType.BACK_COVER) ? _("Back cover")
							     : (it == Gst.Tag.ImageType.MEDIUM) ? _("Disc") : it.to_string ().replace ("GST_TAG_IMAGE_TYPE_", "").replace ("_", " ").down ();
						}
						facts.image_texts += "%s\n%d × %d px, %s".printf (kind, pix.width, pix.height, format_size (map.size));
						double k = 96.0 / int.max (pix.width, pix.height);
						facts.images += pix.scale_simple (int.max (1, (int)(pix.width * k)), int.max (1, (int)(pix.height * k)), Gdk.InterpType.BILINEAR);
					}
				} catch (Error err) {}
				buffer.unmap (map);
			}
		}
		return facts;
	}

	static string value_text (GLib.Value val) {
		string text;
		if (val.holds (typeof (Gst.DateTime)))
			text = ((Gst.DateTime) val.get_boxed ()).to_iso8601_string ();
		else if (val.holds (typeof (GLib.Date))) {
			var d = (GLib.Date?) val.get_boxed ();
			char[] buf = new char[32];
			d.strftime (buf, "%Y-%m-%d");
			text = (string) buf;
		}
		else if (val.holds (typeof (string)))
			text = val.get_string ();
		else
			text = Gst.Value.serialize (val) ?? "";
		text = text.strip ();
		return (text.char_count () > 400) ? text.substring (0, text.index_of_nth_char (400)) + "…" : text;
	}
}
