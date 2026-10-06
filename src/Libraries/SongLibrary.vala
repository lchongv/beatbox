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

using Gee;
using SQLHeavy;

public class BeatBox.SongLibrary : BaseLibrary {
	const string LOAD_SONGS_QUERY = "SELECT rowid,* FROM 'songs'";
	
	Song ref_song = new Song("");
	public override string key { get { return ref_song.key; } }
	public override string name { get { return _("Music"); } }
	
	File _default_folder;
	public override File? default_folder { 
		get { return _default_folder; }
	}
	
	File _folder;
	public override File folder { 
		get { 
			return _folder;
		}
		set {
			App.settings.main.music_folder = value.get_path();
			_folder = value;
		}
	}
	public override bool uses_local_folder { get { return true; } }
	public override Type media_type { get { return typeof(Song); } }
	
	PreferencesSection section;
	public override PreferencesSection? preferences_section { 
		get {
			section = new MusicPreferences();
			return section;
		}
	}
	
	public SongLibrary() {
		_default_folder = File.new_for_path(Environment.get_user_special_dir(UserDirectory.MUSIC) ?? Path.build_filename(Environment.get_home_dir(), "Music"));
		_folder = File.new_for_path(App.settings.main.music_folder);
		
		load_from_database();
	}
	
	void load_from_database() {
		message("Loading songs...");
		try {
			var results = App.database.execute(LOAD_SONGS_QUERY);
			if(results == null) {
				warning("Could not load songs from database");
				return;
			}
			
			for (; !results.finished; results.next() ) {
				Song s = new Song(results.fetch_string(1));
				
				s.rowid = results.fetch_int(0);
				s.file_size = (uint)results.fetch_int(2);
				s.title = results.fetch_string(3);
				s.artist = results.fetch_string(4);
				s.composer = results.fetch_string(5);
				s.album_artist = results.fetch_string(6);
				s.album = results.fetch_string(7);
				s.grouping = results.fetch_string(8);
				s.genre = results.fetch_string(9);
				s.comment = results.fetch_string(10);
				s.lyrics = results.fetch_string(11);
				s.has_embedded = (results.fetch_int(13) == 1);
				s.year = (uint)results.fetch_int(14);
				s.track = (uint)results.fetch_int(15);
				s.track_count = (uint)results.fetch_int(16);
				s.album_number = (uint)results.fetch_int(17);
				s.album_count = (uint)results.fetch_int(18);
				s.bitrate = (uint)results.fetch_int(19);
				s.length = (uint)results.fetch_int(20);
				s.samplerate = (uint)results.fetch_int(21);
				s.rating = (uint)results.fetch_int(22);
				s.play_count = (uint)results.fetch_int(23);
				s.skip_count = (uint)results.fetch_int(24);
				s.date_added = (uint)results.fetch_int(25);
				s.last_played = (uint)results.fetch_int(26);
				s.last_modified = (uint)results.fetch_int(27);
				//s.mediatype = (MediaType)results.fetch_int(28);
				//s.podcast_rss = results.fetch_string(29);
				//s.podcast_url = results.fetch_string(30);
				//s.podcast_date = results.fetch_int(31);
				//s.is_new_podcast = (results.fetch_int(32) == 1) ? true : false;
				s.resume_pos = results.fetch_int(33);
				s.is_video = (results.fetch_int(34) == 1) ? true : false;
				s.bpm = (uint)results.fetch_int(35);
				s.sort_title = results.fetch_string(36);
				s.sort_artist = results.fetch_string(37);
				s.sort_album_artist = results.fetch_string(38);
				s.sort_album = results.fetch_string(39);
				s.sort_composer = results.fetch_string(40);
				s.compilation = results.fetch_int(41) == 1;
				s.skip_shuffle = results.fetch_int(42) == 1;
				s.volume_adjust = results.fetch_int(43);
				s.remember_position = results.fetch_int(44) == 1;
				
				//lock(_medias) {
					App.library.assign_id_to_media(s);
					_medias.set (s.rowid, s);
				//}
			}
		}
		catch(SQLHeavy.Error err) {
			warning("Error loading songs: %s", err.message);
		}
	}
	
	public override void add_db_function(Collection<Media> added) {
		DatabaseTransactionFiller db_filler = new DatabaseTransactionFiller();
		db_filler.data = added;
		db_filler.filler = add_to_db_filler;
		
		App.database.queue_transaction(db_filler);
	}
	
	void add_to_db_filler(ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller db_filler) {
		Collection<Media> added = (Collection<Media>)db_filler.data;
		
		try {
			Query query = transaction.prepare ("""INSERT INTO 'songs' ('rowid', 'uri', 'file_size', 'title', 'artist', 'composer', 'album_artist',
'album', 'grouping', 'genre', 'comment', 'lyrics', 'has_embedded', 'year', 'track', 'track_count', 'album_number', 'album_count',
'bitrate', 'length', 'samplerate', 'rating', 'playcount', 'skipcount', 'dateadded', 'lastplayed', 'lastmodified', 'mediatype', 'podcast_rss',
'podcast_url', 'podcast_date', 'is_new_podcast', 'resume_pos', 'is_video', 'bpm', 'sort_title', 'sort_artist', 'sort_album_artist',
'sort_album', 'sort_composer', 'compilation', 'skip_shuffle', 'volume_adjust', 'remember_position') 
VALUES (:rowid, :uri, :file_size, :title, :artist, :composer, :album_artist, :album, :grouping, 
:genre, :comment, :lyrics, :has_embedded, :year, :track, :track_count, :album_number, :album_count, :bitrate, :length, :samplerate, 
:rating, :playcount, :skipcount, :dateadded, :lastplayed, :lastmodified, :mediatype, :podcast_rss, :podcast_url, :podcast_date, :is_new_podcast,
:resume_pos, :is_video, :bpm, :sort_title, :sort_artist, :sort_album_artist, :sort_album, :sort_composer, :compilation,
:skip_shuffle, :volume_adjust, :remember_position);""");
			
			foreach(Media s in added) {
				if(s.rowid > 0 && !s.isTemporary) {
					query.set_int(":rowid", (int)s.rowid);
					query.set_string(":uri", s.uri);
					query.set_int(":file_size", (int)s.file_size);
					query.set_string(":title", s.title);
					query.set_string(":artist", s.artist);
					query.set_string(":composer", s.composer);
					query.set_string(":album_artist", s.album_artist);
					query.set_string(":album", s.album);
					query.set_string(":grouping", s.grouping);
					query.set_string(":genre", s.genre);
					query.set_string(":comment", s.comment);
					query.set_string(":lyrics", s.lyrics);
					query.set_int(":has_embedded", s.has_embedded ? 1 : 0);
					query.set_int(":year", (int)s.year);
					query.set_int(":track", (int)s.track);
					query.set_int(":track_count", (int)s.track_count);
					query.set_int(":album_number", (int)s.album_number);
					query.set_int(":album_count", (int)s.album_count);
					query.set_int(":bitrate", (int)s.bitrate);
					query.set_int(":length", (int)s.length);
					query.set_int(":samplerate", (int)s.samplerate);
					query.set_int(":rating", (int)s.rating);
					query.set_int(":playcount", (int)s.play_count);
					query.set_int(":skipcount", (int)s.skip_count);
					query.set_int(":dateadded", (int)s.date_added);
					query.set_int(":lastplayed", (int)s.last_played);
					query.set_int(":lastmodified", (int)s.last_modified);
					query.set_int(":mediatype", 0); // FIXME
					query.set_string(":podcast_rss", ""); // FIXME
					query.set_string(":podcast_url", ""); // FIXME
					query.set_int(":podcast_date", 0); // FIXME
					query.set_int(":is_new_podcast", s.is_new_podcast ? 1 : 0);
					query.set_int(":resume_pos", s.resume_pos);
					query.set_int(":is_video", s.is_video ? 1 : 0);
					query.set_int(":bpm", (int)s.bpm);
					query.set_string(":sort_title", s.sort_title);
					query.set_string(":sort_artist", s.sort_artist);
					query.set_string(":sort_album_artist", s.sort_album_artist);
					query.set_string(":sort_album", s.sort_album);
					query.set_string(":sort_composer", s.sort_composer);
					query.set_int(":compilation", s.compilation ? 1 : 0);
					query.set_int(":skip_shuffle", s.skip_shuffle ? 1 : 0);
					query.set_int(":volume_adjust", s.volume_adjust);
					query.set_int(":remember_position", s.remember_position ? 1 : 0);
					
					query.execute();
				}
			}
		}
		catch(SQLHeavy.Error err) {
			stdout.printf("Could not save medias: %s \n", err.message);
		}
	}
	
	public override void update_db_function(Collection<Media> updates) {
		DatabaseTransactionFiller db_filler = new DatabaseTransactionFiller();
		db_filler.data = updates;
		db_filler.filler = update_in_db_filler;
		
		App.database.queue_transaction(db_filler);
	}
	
	void update_in_db_filler(ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller db_filler) {
		Collection<Media> updated = (Collection<Media>)db_filler.data; 
		
		try {
			Query query = transaction.prepare("""UPDATE 'songs' SET uri=:uri, file_size=:file_size, title=:title, artist=:artist,
composer=:composer, album_artist=:album_artist, album=:album, grouping=:grouping, genre=:genre, comment=:comment, lyrics=:lyrics, 
has_embedded=:has_embedded, year=:year, track=:track, track_count=:track_count, album_number=:album_number, 
album_count=:album_count,bitrate=:bitrate, length=:length, samplerate=:samplerate, rating=:rating, playcount=:playcount, skipcount=:skipcount, 
dateadded=:dateadded, lastplayed=:lastplayed, lastmodified=:lastmodified, mediatype=:mediatype, podcast_rss=:podcast_rss, podcast_url=:podcast_url,
podcast_date=:podcast_date, is_new_podcast=:is_new_podcast, resume_pos=:resume_pos, is_video=:is_video, bpm=:bpm,
sort_title=:sort_title, sort_artist=:sort_artist, sort_album_artist=:sort_album_artist, sort_album=:sort_album, sort_composer=:sort_composer,
compilation=:compilation, skip_shuffle=:skip_shuffle, volume_adjust=:volume_adjust, remember_position=:remember_position WHERE rowid=:rowid""");
			
			foreach(Media s in updated) {
				if(s.rowid != -2 && s.rowid > 0) {
					
					query.set_int(":rowid", (int)s.rowid);
					query.set_string(":uri", s.uri);
					query.set_int(":file_size", (int)s.file_size);
					query.set_string(":title", s.title);
					query.set_string(":artist", s.artist);
					query.set_string(":composer", s.composer);
					query.set_string(":album_artist", s.album_artist);
					query.set_string(":album", s.album);
					query.set_string(":grouping", s.grouping);
					query.set_string(":genre", s.genre);
					query.set_string(":comment", s.comment);
					query.set_string(":lyrics", s.lyrics);
					query.set_int(":has_embedded", s.has_embedded ? 1 : 0);
					query.set_int(":year", (int)s.year);
					query.set_int(":track", (int)s.track);
					query.set_int(":track_count", (int)s.track_count);
					query.set_int(":album_number", (int)s.album_number);
					query.set_int(":album_count", (int)s.album_count);
					query.set_int(":bitrate", (int)s.bitrate);
					query.set_int(":length", (int)s.length);
					query.set_int(":samplerate", (int)s.samplerate);
					query.set_int(":rating", (int)s.rating);
					query.set_int(":playcount", (int)s.play_count);
					query.set_int(":skipcount", (int)s.skip_count);
					query.set_int(":dateadded", (int)s.date_added);
					query.set_int(":lastplayed", (int)s.last_played);
					query.set_int(":lastmodified", (int)s.last_modified);
					query.set_int(":mediatype", 0); // FIXME
					query.set_string(":podcast_rss", ""); // FIXME
					query.set_string(":podcast_url", ""); // FIXME
					query.set_int(":podcast_date", 0); // FIXME
					query.set_int(":is_new_podcast", s.is_new_podcast ? 1 : 0);
					query.set_int(":resume_pos", s.resume_pos);
					query.set_int(":is_video", s.is_video ? 1 : 0);
					query.set_int(":bpm", (int)s.bpm);
					query.set_string(":sort_title", s.sort_title);
					query.set_string(":sort_artist", s.sort_artist);
					query.set_string(":sort_album_artist", s.sort_album_artist);
					query.set_string(":sort_album", s.sort_album);
					query.set_string(":sort_composer", s.sort_composer);
					query.set_int(":compilation", s.compilation ? 1 : 0);
					query.set_int(":skip_shuffle", s.skip_shuffle ? 1 : 0);
					query.set_int(":volume_adjust", s.volume_adjust);
					query.set_int(":remember_position", s.remember_position ? 1 : 0);
					
					query.execute();
				}
			}
		}
		catch(SQLHeavy.Error err) {
			stdout.printf("Could not update songs: %s \n", err.message);
		}
	}
	
	public override void remove_db_function(Collection<Media> removed) {
		DatabaseTransactionFiller db_filler = new DatabaseTransactionFiller();
		db_filler.data = removed;
		db_filler.filler = remove_from_db_filler;
		
		App.database.queue_transaction(db_filler);
	}
	
	void remove_from_db_filler(ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller db_filler) {
		Collection<Media> removed = (Collection<Media>)db_filler.data; 
		
		try {
			Query query = transaction.prepare("DELETE FROM 'songs' WHERE rowid=:rowid");
			
			foreach(var s in removed) {
				query.set_int(":rowid", s.rowid);
				query.execute();
			}
		}
		catch (SQLHeavy.Error err) {
			stdout.printf("Could not remove songs from db: %s\n", err.message);
		}
	}
	
	public override Media import_tags_to_media(Gst.PbUtils.DiscovererInfo info) {
		Gst.TagList tags = GStreamerTagger.all_tags(info) ?? new Gst.TagList.empty(); // untagged: named after the file
		Song s = new Song(info.get_uri());
			
		try {
			string title = "";
			string artist, composer, album_artist, album, grouping, genre, comment, lyrics;
			uint track, track_count, album_number, album_count, bitrate, rating;
			double bpm;
			GLib.Date? date = GLib.Date();
			
			// get title, artist, album artist, album, genre, comment, lyrics strings
			if(tags.get_string(Gst.Tags.TITLE, out title))
				s.title = title;
			if(tags.get_string(Gst.Tags.ARTIST, out artist))
				s.artist = artist;
			if(tags.get_string(Gst.Tags.COMPOSER, out composer))
				s.composer = composer;
			
			if(tags.get_string(Gst.Tags.ALBUM_ARTIST, out album_artist))
				s.album_artist = album_artist;
			else
				s.album_artist = s.artist;
			
			if(tags.get_string(Gst.Tags.ALBUM, out album))
				s.album = album;
			if(tags.get_string(Gst.Tags.GROUPING, out grouping))
				s.grouping = grouping;
			if(tags.get_string(Gst.Tags.GENRE, out genre))
				s.genre = genre;
			if(tags.get_string(Gst.Tags.COMMENT, out comment))
				s.comment = comment;
			if(tags.get_string(Gst.Tags.LYRICS, out lyrics))
				s.lyrics = lyrics;
			
			// get the year
			// GStreamer reports the year as DATE_TIME nowadays; DATE only for old demuxers
			Gst.DateTime? date_time;
			if(tags.get_date_time(Gst.Tags.DATE_TIME, out date_time) && date_time != null && date_time.has_year())
				s.year = date_time.get_year();
			else if(tags.get_date(Gst.Tags.DATE, out date) && date.valid())
				s.year = (int)date.get_year();
			// get track/album number/count, bitrating, rating, bpm
			if(tags.get_uint(Gst.Tags.TRACK_NUMBER, out track))
				s.track = (int)track;
			if(tags.get_uint(Gst.Tags.TRACK_COUNT, out track_count))
				s.track_count = track_count;
				
			if(tags.get_uint(Gst.Tags.ALBUM_VOLUME_NUMBER, out album_number))
				s.album_number = album_number;
			if(tags.get_uint(Gst.Tags.ALBUM_VOLUME_COUNT, out album_count))
				s.album_count = album_count;
			
			if(tags.get_uint(Gst.Tags.BITRATE, out bitrate))
				s.bitrate = (int)(bitrate/1000);
			if(tags.get_uint(Gst.Tags.USER_RATING, out rating))
				s.rating = (int)((rating > 0 && rating <= 5) ? rating : 0);
			if(tags.get_double(Gst.Tags.BEATS_PER_MINUTE, out bpm))
				s.bpm = (int)bpm;
			string sort;
			if(tags.get_string(Gst.Tags.TITLE_SORTNAME, out sort))
				s.sort_title = sort;
			if(tags.get_string(Gst.Tags.ARTIST_SORTNAME, out sort))
				s.sort_artist = sort;
			if(tags.get_string(Gst.Tags.ALBUM_ARTIST_SORTNAME, out sort))
				s.sort_album_artist = sort;
			if(tags.get_string(Gst.Tags.ALBUM_SORTNAME, out sort))
				s.sort_album = sort;
			if(tags.get_string(Gst.Tags.COMPOSER_SORTNAME, out sort))
				s.sort_composer = sort;
			if(info.get_audio_streams().length() > 0)
				s.samplerate = ((Gst.PbUtils.DiscovererAudioInfo) info.get_audio_streams().nth_data(0)).get_sample_rate();
			
			s.length = get_length(s.uri);
			
			// load embedded art
			if(s.artist == null || s.artist == "") s.artist = "Unknown Artist";
			if(s.album_artist == null || s.album_artist == "")	s.album_artist = s.artist;
			if(s.album == null)	s.album = "";
			import_art(info, s);
			
			s.date_added = (int)time_t();
			
			// get the size
			s.file_size = (int)(File.new_for_uri(info.get_uri()).query_info("*", FileQueryInfoFlags.NONE).get_size());
			
		}
		catch (GLib.Error e) {
			warning ("GStreamerTagger error: %s", e.message);
		}
		finally {
			if(s.title == null || s.title == "") {
				string[] paths = info.get_uri().split("/", 0);
				s.title = paths[paths.length - 1];
			}
			if(s.artist == null || s.artist == "") s.artist = "Unknown Artist";
			if(s.album_artist == null || s.album_artist == "")	s.album_artist = s.artist;
			if(s.album == null) s.album = "";
			
			/*if(s.genre.down().contains("podcast") || s.length > 9000) {// OVER 9000!!!!! aka 15 minutes
				s.mediatype = MediaType.PODCAST;
				if(info.get_video_streams().length() > 0)
					s.is_video = true;
			}*/
		}
		
		return s;
	}
	
	void import_art(Gst.PbUtils.DiscovererInfo info, Media s) {
		Gst.TagList? tags = (info != null) ? GStreamerTagger.all_tags(info) : null;
		if(App.covers.get_album_art_from_key(s.album_artist, s.album) != null) {
			debug("not loading embedded art since album already has art (%s)\n", s.album);
			return;
		}
		
		if(info != null && tags != null) {
			try {
				Gst.Buffer buf = null;
				Gdk.Pixbuf? rv = null;
				int i;
				
				// choose the best image based on image type
				for(i = 0; ; ++i) {
					Gst.Sample sample;
					if(!tags.get_sample_index(Gst.Tags.IMAGE, i, out sample))
						break;
					
					Gst.Buffer buffer = sample.get_buffer();
					if (buffer == null || sample.get_caps() == null)
						continue;
					
					if (sample.get_caps().get_structure(0).get_name() == "text/uri-list")
						continue;
					
					int imgtype = Gst.Tag.ImageType.UNDEFINED;
					unowned Gst.Structure? sinfo = sample.get_info();
					if (sinfo != null)
						sinfo.get_enum ("image-type", typeof(Gst.Tag.ImageType), out imgtype);
					
					if (imgtype == Gst.Tag.ImageType.FRONT_COVER) {
						buf = buffer;
						break;
					} else if(buf == null) {
						buf = buffer;
					}
				}
				
				if(buf == null) {
					debug("Could not find emedded art for %s\n", info.get_uri());
					return;
				}
				
				// now that we have the buffer we want, load it into the pixbuf
				Gdk.PixbufLoader loader = new Gdk.PixbufLoader();
				try {
					uint8[] data;
					buf.extract_dup(0, buf.get_size(), out data);
					if (!loader.write(data)) {
						debug("Pixbuf loader doesn't like the data");
						loader.close();
						return;
					}
				}
				catch(GLib.Error err) {
					loader.close();
					return;
				}
				
				try {
					loader.close();
				}
				catch(GLib.Error err) {}
				
				rv = loader.get_pixbuf();
                
                App.covers.save_album_art_in_cache(s, rv);
                App.covers.set_album_art(s, rv, false);
                
				debug("Loaded embedded art from %s\n", info.get_uri());
			}
			catch(GLib.Error err) {
				warning("Failed to import album art from %s\n", info.get_uri());
			}
		}
	}
	
	uint get_length(string uri) {
		uint rv = 0;
		TagLib.File tag_file = new TagLib.File(File.new_for_uri(uri).get_path());
		
		if(tag_file != null && tag_file.audioproperties != null) {
			rv = tag_file.audioproperties.length;
		}
		
		return rv;
	}
	
	public override Collection<SmartPlaylist> get_default_smart_playlists() {
		var rv = new LinkedList<SmartPlaylist>();
		
		SmartPlaylist sp = new SmartPlaylist();
		
		sp.name = _("Favorite Songs");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.MEDIATYPE, SmartQuery.Comparator.IS, "", MediaType.SONG));
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.RATING, SmartQuery.Comparator.IS_AT_LEAST, "", 4));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Recently Added");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.DATE_ADDED, SmartQuery.Comparator.IS_WITHIN, "", 7));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Recently Played");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.LAST_PLAYED, SmartQuery.Comparator.IS_WITHIN, "", 7));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Recent Favorites");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.MEDIATYPE, SmartQuery.Comparator.IS, "", MediaType.SONG));
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.LAST_PLAYED, SmartQuery.Comparator.IS_WITHIN, "", 7));
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.RATING, SmartQuery.Comparator.IS_AT_LEAST, "", 4));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Never Played");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.MEDIATYPE, SmartQuery.Comparator.IS, "", MediaType.SONG));
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.PLAY_COUNT, SmartQuery.Comparator.IS_EXACTLY, "", 0));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Over Played");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.MEDIATYPE, SmartQuery.Comparator.IS, "", MediaType.SONG));
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.PLAY_COUNT, SmartQuery.Comparator.IS_AT_LEAST, "", 10));
		rv.add(sp);
		
		sp = new SmartPlaylist();
		sp.name = _("Not Recently Played");
		sp.conditional = SmartPlaylist.Conditional.ALL;
		sp.limit = false;
		sp.limit_amount = 50;
		sp.queries.add(new SmartQuery.with_info(SmartQuery.Field.LAST_PLAYED, SmartQuery.Comparator.IS_BEFORE, "", 7));
		rv.add(sp);
		
		return rv;
	}
}
