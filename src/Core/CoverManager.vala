/*-
 * Copyright (c) 2011-2012       BeatBox Developers
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
 *
 * Authored by: Lucas Baudin <xapantu@gmail.com>
 *              Scott Ringwelski <sgringwe@mtu.edu>
 */

using Gee;

public class BeatBox.CoverManager : Object, BeatBox.CoverInterface {
	bool in_fetch_thread;
	
    Gee.HashMap<string, Gdk.Pixbuf> m_covers; // The id has the form "album - artist".
	Gee.HashMap<string, string> art_locations = new Gee.HashMap<string, string>();
	HashMap<Media, int> remaining_art;
	
	private Gdk.Pixbuf? _default_cover_shadow = null;
    public Gdk.Pixbuf DEFAULT_COVER_SHADOW {
        get {
            if (_default_cover_shadow == null)
                _default_cover_shadow = App.covers.add_shadow_to_album_art(App.icons.DEFAULT_ALBUM_ART_PIXBUF);
            return _default_cover_shadow;
        }
    }

    public CoverManager() {
        m_covers = new Gee.HashMap<string, Gdk.Pixbuf>();
        remaining_art = new HashMap<Media, int>();
    }
    
    public void setup_signals() {
		App.info.album_info_updated.connect(album_info_updated);
		App.library.medias_removed.connect(medias_removed);
	}
    
    public string get_media_coverart_key (Media s) {
        /* FIXME: what happens if I have Album/ and Album_ as album names? */
		return (s.album_artist + " - " + s.album).replace("/", "_");
	}
	
	public Gdk.Pixbuf? get_album_art_from_key(string album_artist, string album) {
		return m_covers.get(album_artist + " - " + album);
    }
    
    public Gdk.Pixbuf? get_album_art_from_media(Media s) {
        return m_covers.get(get_media_coverart_key (s));
    }

	public string get_cached_album_art_path (string key) {
		string filename = Checksum.compute_for_string (ChecksumType.MD5, key);
		return GLib.Path.build_filename (App.settings.get_album_art_cache_dir (), filename + ".jpg");
	}

    Gdk.Pixbuf? get_cached_album_art (string key, out string uri) {
		Gdk.Pixbuf? rv = null;
		uri = get_cached_album_art_path (key);

		try {
			rv = new Gdk.Pixbuf.from_file (uri);
		} catch (Error err) {
			//debug (err.message);
		}

		if (rv == null)
			uri = "";

		return rv;
	}
	
	public void set_album_art(Media s, Gdk.Pixbuf pix, bool emit) {
		string key = get_media_coverart_key (s);
		
		if(key != null) {
			m_covers.set(key, add_shadow_to_album_art(pix));
			
			// We need to let views know of this update
			if(emit) {
				cover_changed(s.album_artist, s.album);
			}
		}
	}
	
	public void save_album_art_in_cache (Media m, Gdk.Pixbuf? pixbuf) {
		if (m == null || pixbuf == null)
			return;
		
		string key = get_media_coverart_key (m);
		if(key == "")
			return;
		
		string uri = get_cached_album_art_path (key);

		debug ("Saving cached album-art for %s", key);
		
		bool success = false;
		try {
			success = pixbuf.save (uri, "jpeg", null);
		} catch (Error err) {
			warning (err.message);
		}
		
		/*if(success) {
			foreach(int i in media_ids()) {
				if(media_from_id(i).album_artist == m.album_artist && lm.media_from_id(i).album == m.album) {
					debug("setting album art for %s by %s", lm.media_from_id(i).title, lm.media_from_id(i).artist);
					media_from_id(i).setAlbumArtPath(uri);
				}
			}
		}*/
	}

    static bool is_valid_image_type(string type) {
		var typeDown = type.down();
		
		return (typeDown.has_suffix(".jpg") || typeDown.has_suffix(".jpeg") ||
				typeDown.has_suffix(".png"));
	}

    public Gdk.Pixbuf add_shadow_to_album_art (Gdk.Pixbuf pixbuf, bool use_default_size = true, bool stretch = true) {
        return PixbufUtils.get_pixbuf_shadow (pixbuf, use_default_size ? Icons.ALBUM_VIEW_IMAGE_SIZE : pixbuf.width, stretch);
    }

    public void fetch_cover_of_media(Media s) {
        string key = get_media_coverart_key(s);
        string path = "";
        Gdk.Pixbuf? pix = null;
            
        if(!m_covers.has_key (key)) {
            Gdk.Pixbuf? coverart_pixbuf = get_cached_album_art (key, out path);

            // try to get image from the cache folder (faster)
            if (coverart_pixbuf != null) {
                pix = add_shadow_to_album_art(coverart_pixbuf);
            }
            else {
				pix = get_cached_album_art(get_media_coverart_key(s), out path);
					
                if (pix == null && (path = get_best_album_art_file(s)) != null) {
                    try {
                        coverart_pixbuf = new Gdk.Pixbuf.from_file (path);
                        pix = add_shadow_to_album_art(coverart_pixbuf);
                        
                        // Add image to cache
                        save_album_art_in_cache (s, coverart_pixbuf);
                    }
                    catch(GLib.Error err) {
                        debug (err.message);
                    }
                }
                
                // TODO: Try gstreamer tagger otherwise.
            }

            m_covers[key] = pix;
        }
    }
	
    public string? get_best_album_art_file(Media m) {
		// If it is not a local file, ignore it (asking GVfs about an https
		// podcast episode is a network round trip per episode)
		if(!m.uri.has_prefix("file:")) {
			return get_cached_album_art_path(get_media_coverart_key(m));
		}
		
		GLib.File media_file = GLib.File.new_for_uri(m.uri);
		if(!media_file.query_exists())
			return null;
		
		string artPath = "";
		GLib.FileInfo file_info = null;
		var album_folder = media_file.get_parent();
		
		if(!album_folder.query_exists() || album_folder.get_path() == null)
			return null;
		
		if( (artPath = art_locations.get(album_folder.get_path())) != null)
			return artPath;
			
		artPath = "";
		
		/* get a list of all images in folder as potential album art choices */
		var image_list = new Gee.LinkedList<string>();

		try {
			var enumerator = album_folder.enumerate_children(FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE, 0);
			while ((file_info = enumerator.next_file ()) != null) {
				if(file_info.get_file_type() == GLib.FileType.REGULAR && is_valid_image_type(file_info.get_name())) {
					image_list.add(file_info.get_name());
				}
			}
        }
        catch (Error e) {
            warning ("Error while looking for covers: %s", e.message);
        }
		
		/* now choose one based on priorities */
		foreach(string sU in image_list) {
			var sD = sU.down();
			if(sD.contains("folder.")) {
				artPath = album_folder.get_path() + "/" + sU;
				break;
			}
			else if(sD.contains("cover."))
				artPath = album_folder.get_path() + "/" + sU;
			else if(!artPath.contains("cover.") && sD.contains("album."))
				artPath = album_folder.get_path() + "/" + sU;
			else if(artPath == "")
				artPath = album_folder.get_path() + "/" + sU;
		}
		
		art_locations.set(album_folder.get_path(), artPath);
		return artPath;
	}
	
	public Gdk.Pixbuf? get_art_from_media_folder(Media m) {
		Gdk.Pixbuf? pix = null;
		string? path = get_best_album_art_file(m);
		
		if(path != null) {
			try {
				pix = new Gdk.Pixbuf.from_file(path);
			}
			catch(GLib.Error err) {}
		}
		
		return pix;
	}
	
	public void save_album_locally_for_meta(string album_artist, string album, string image_uri, bool emit = true) {
		Media m = new Song("");
		m.album_artist = album_artist;
		m.album = album;
		
		save_album_locally(m, image_uri, emit);
	}
	
	public void save_album_locally(Media m, string image_uri, bool emit = true) {
		GLib.File file = GLib.File.new_for_uri(image_uri);
		if(file == null) {
			warning("Could not read image_uri as file\n");
			return;
		}
		
		FileInputStream filestream;
		Gdk.Pixbuf? pix = null;
		
		try {
			filestream = file.read(null);
			pix = new Gdk.Pixbuf.from_stream(filestream, null);
		} catch(GLib.Error err) {
			warning("Failed to save album art locally from %s: %s\n", image_uri, err.message);
		}
		
		if(pix != null) {
			save_album_art_in_cache(m, pix);
			set_album_art(m, pix, emit);
		}
	}

	public async void fetch_image_cache_async () {
		try {
			new Thread<void*>.try (null, fetch_image_thread_function);
		} catch(Error err) {
			warning ("Could not create thread to load media pixbuf's: %s \n", err.message);
		}
	}

	/* at the start, load all the pixbufs */
	private void* fetch_image_thread_function () {
		if(in_fetch_thread)
			return null;
		
		in_fetch_thread = true;
		
        LinkedList<Media> medias = new LinkedList<Media>();
		medias.add_all(App.library.medias());
		
		// first get from file
		foreach(var s in medias) {
            fetch_cover_of_media(s);
		}
		
		message("Album art cached in memory.\n");
		in_fetch_thread = false;
		
		// Views may have been drawn before the covers were ready
		Idle.add(() => { App.window.queue_draw(); return false; });
		
		fetch_remaining_album_art();
		
		return null;
	}
	
	/* Covers missing from the music folders: MusicBrainz finds the album's
	 * release group, the Cover Art Archive has its front cover. MusicBrainz
	 * allows one request per second, so this runs slowly in the background. */
	bool fetching_online = false;
	
	public void fetch_remaining_album_art() {
		if(fetching_online || !App.settings.main.download_covers)
			return;
		fetching_online = true;
		new Thread<void*>("covers-online", fetch_online_thread);
	}
	
	// Albums that MusicBrainz doesn't know, so they are not asked again on every start
	string not_found_path() {
		return Path.build_filename(App.settings.get_album_art_cache_dir(), "not-found-online.txt");
	}
	
	void* fetch_online_thread() {
		var not_found = new HashSet<string>();
		try {
			string contents;
			FileUtils.get_contents(not_found_path(), out contents);
			foreach(var line in contents.split("\n"))
				not_found.add(line);
		} catch(Error err) {}
		
		var wanted = new HashMap<string, Media>();
		foreach(var m in App.library.song_library.medias()) {
			string key = get_media_coverart_key(m);
			if(m.album.strip() == "" || wanted.has_key(key) || not_found.contains(key) || m_covers.get(key) != null)
				continue;
			wanted[key] = m;
		}
		if(wanted.size > 0)
			message("Looking up %d missing album covers online", wanted.size);
		
		foreach(var entry in wanted.entries) {
			if(!App.settings.main.download_covers)
				break;
			var m = entry.value;
			var pix = download_cover(m.album_artist != "" ? m.album_artist : m.artist, m.album);
			if(pix == null) {
				try {
					var stream = File.new_for_path(not_found_path()).append_to(FileCreateFlags.NONE);
					stream.write((entry.key + "\n").data);
				} catch(Error err) {}
				continue;
			}
			save_album_art_in_cache(m, pix);
			Idle.add(() => { set_album_art(m, pix, true); return false; });
		}
		fetching_online = false;
		return null;
	}
	
	static string quote(string s) {
		return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
	}
	
	/** "Definitely Maybe (Remastered)" → "definitely maybe"; also drops " - Single" */
	static string simplify(string s) {
		try {
			var plain = new Regex("""\s*[(\[][^)\]]*[)\]]|\s+-\s+(single|ep)$""", RegexCompileFlags.CASELESS).replace(s, -1, 0, "");
			return plain.down().strip();
		} catch(RegexError err) {
			return s.down().strip();
		}
	}
	
	Gdk.Pixbuf? download_cover(string artist, string album) {
		return cover_from_musicbrainz(artist, simplify(album)) ?? cover_from_itunes(artist, album);
	}
	
	Gdk.Pixbuf? pixbuf_from_url(string url) {
		var bytes = Http.fetch_bytes(url);
		if(bytes == null)
			return null;
		try {
			return new Gdk.Pixbuf.from_stream(new MemoryInputStream.from_bytes(bytes));
		} catch(Error err) {
			return null;
		}
	}
	
	Gdk.Pixbuf? cover_from_musicbrainz(string artist, string album) {
		var query = "releasegroup:%s AND artist:%s".printf(quote(album), quote(artist));
		var body = Http.fetch("https://musicbrainz.org/ws/2/release-group/?fmt=json&limit=3&query=" + Uri.escape_string(query, null, false));
		Thread.usleep(1100000); // MusicBrainz rate limit
		
		try {
			var parser = new Json.Parser();
			parser.load_from_data(body);
			foreach(var node in parser.get_root().get_object().get_array_member("release-groups").get_elements()) {
				var group = node.get_object();
				if(group.get_int_member("score") < 90)
					continue;
				var pix = pixbuf_from_url("https://coverartarchive.org/release-group/" + group.get_string_member("id") + "/front-500");
				if(pix != null)
					return pix;
			}
		} catch(Error err) {}
		return null;
	}
	
	/* The Apple Music catalogue knows most commercial releases MusicBrainz lacks */
	Gdk.Pixbuf? cover_from_itunes(string artist, string album) {
		var body = Http.fetch("https://itunes.apple.com/search?entity=album&limit=10&term=" + Uri.escape_string(artist + " " + simplify(album), null, false));
		Thread.usleep(3000000); // Apple allows about 20 searches per minute
		
		try {
			var parser = new Json.Parser();
			parser.load_from_data(body);
			foreach(var node in parser.get_root().get_object().get_array_member("results").get_elements()) {
				var r = node.get_object();
				string their_artist = r.get_string_member("artistName").down();
				if(simplify(r.get_string_member("collectionName")) != simplify(album)
				   || !(artist.down() in their_artist || their_artist in artist.down()))
					continue;
				var pix = pixbuf_from_url(r.get_string_member("artworkUrl100").replace("100x100bb", "600x600bb"));
				if(pix != null)
					return pix;
			}
		} catch(Error err) {}
		return null;
	}
	
	void medias_removed(Collection<Media> removed) {
		foreach(var m in removed) {
			remaining_art.unset(m);
		}
	}
	
	void album_info_updated(AlbumInfo album) {
	}
}
