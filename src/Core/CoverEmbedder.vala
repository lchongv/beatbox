/*-
 * Writes the album art BeatBox shows into the song files themselves, so other
 * players and devices see it too.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#if HAVE_EMBED_COVER
[CCode (cname = "beatbox_embed_cover")]
extern bool beatbox_embed_cover (string path, [CCode (array_length_type = "gsize")] uint8[] data, string mime_type);
#endif

namespace BeatBox.CoverEmbedder {
	/** false when BeatBox was built with a TagLib older than 2.0 */
	public bool available () {
#if HAVE_EMBED_COVER
		return true;
#else
		return false;
#endif
	}

	public delegate void DoneFunc (int written, int failed);

	/** Embeds each local song's album art (songs without art are skipped); done runs on the main loop */
	public void embed (Gee.Collection<Media> medias, owned DoneFunc done) {
		// the images, once per album, prepared here: CoverManager isn't thread-safe
		var images = new Gee.HashMap<string, Bytes> ();
		var jobs = new Gee.ArrayList<Media> ();
		var paths = new Gee.ArrayList<string> ();   // all the thread reads: paths and image data
		var datas = new Gee.ArrayList<Bytes> ();
		foreach (var m in medias) {
			if (!m.uri.has_prefix ("file://"))
				continue;
			string key = App.covers.get_media_coverart_key (m);
			if (!images.has_key (key)) {
				var data = cover_bytes (m, key);
				if (data == null)
					continue;
				images[key] = data;
			}
			jobs.add (m);
			paths.add (File.new_for_uri (m.uri).get_path ());
			datas.add (images[key]);
		}

		var written = new Gee.ArrayList<Media> ();
		int failed = 0;
		new Thread<void*> ("embed-covers", () => {
			for (int i = 0; i < jobs.size; i++) {
				unowned uint8[] data = datas[i].get_data ();
				string mime = (data.length > 3 && data[0] == 0x89 && data[1] == 'P') ? "image/png" : "image/jpeg";
#if HAVE_EMBED_COVER
				if (beatbox_embed_cover (paths[i], data, mime))
					written.add (jobs[i]);
				else
					failed++;
#else
				failed++;
#endif
			}
			Idle.add (() => {
				foreach (var m in written) {
					m.has_embedded = true;
					try {
						m.file_size = (uint) File.new_for_uri (m.uri).query_info (FileAttribute.STANDARD_SIZE, 0).get_size ();
					} catch (Error err) {}
				}
				if (written.size > 0)
					App.library.update_medias (written, false, false, true);
				done (written.size, failed);
				return false;
			});
			return null;
		});
	}

	/** The album art as image file data: the original from the cache, or the cover BeatBox shows */
	Bytes? cover_bytes (Media m, string key) {
		try {
			uint8[] contents;
			FileUtils.get_data (App.covers.get_cached_album_art_path (key), out contents);
			return new Bytes (contents);
		} catch (Error err) {}

		var framed = App.covers.get_album_art_from_media (m);
		if (framed == null)
			return null;
		int crop = 6; // the shadow baked into the shown covers (see LcdCover)
		if (framed.width > 2 * crop && framed.height > 2 * crop)
			framed = new Gdk.Pixbuf.subpixbuf (framed, crop, crop, framed.width - 2 * crop, framed.height - 2 * crop);
		try {
			uint8[] buffer;
			framed.save_to_buffer (out buffer, "jpeg", "quality", "95");
			return new Bytes (buffer);
		} catch (Error err) {
			return null;
		}
	}
}
