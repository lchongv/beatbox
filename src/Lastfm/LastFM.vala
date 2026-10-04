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

public class BeatBox.LastFMCore : GLib.Object, BeatBox.LastFMInterface {
	/** NOTICE: These API keys and secrets are unique to BeatBox and BeatBox
	 * only. To get your own, FREE key go to http://www.last.fm/api/account */
	public const string api = "a40ea1720028bd40c66b17d7146b3f3b";
	public const string secret = "92ba5023f6868e680a3352c71e21243d";
	
	public const string HTTP_BASE = "http://ws.audioscrobbler.com/2.0/";
	public const string HTTPS_BASE = "https://ws.audioscrobbler.com/2.0/";
	
	// Mostly conveniences
	public string session_key {
		get { return BeatBox.App.settings.lastfm.session_key; }
		set { BeatBox.App.settings.lastfm.session_key = value; }
	}
	public bool is_subscriber {
		get { return BeatBox.App.settings.lastfm.is_subscriber; }
		set { BeatBox.App.settings.lastfm.is_subscriber = value; }
	}
	public string username {
		get { return BeatBox.App.settings.lastfm.username; }
		set { BeatBox.App.settings.lastfm.username = value; }
	}
	
	LastFM.SimilarMedias similarMedias;
	LastFM.TopArtistSongs topArtistSongs;
	LastFM.TopArtistAlbums topArtistAlbums;
	
	public LastFMCore() {
		similarMedias = new LastFM.SimilarMedias();
		topArtistSongs = new LastFM.TopArtistSongs();
		topArtistAlbums = new LastFM.TopArtistAlbums();
		
		similarMedias.similar_retrieved.connect(similar_retrieved_signal);
		topArtistSongs.top_artist_songs_retrieved.connect(top_artist_songs_retrieved_signal);
		topArtistAlbums.top_artist_albums_retrieved.connect(top_artist_albums_retrieved_signal);
	}
	
	/** Last.FM Api functions **/
	/* Signed call (api_sig over the raw values, see last.fm/api/authspec); POST sends
	 * the parameters as a form, GET in the query string, escaped either way.
	 * call_back runs in a worker thread. */
	public void query(string type, HashMap<string, string> params, bool requires_sk, BeatBox.LastFMCallback call_back) {
		if(requires_sk && BeatBox.String.is_empty(session_key)) {
			debug("Not logged in to Last.fm: %s not sent", params.get("method"));
			return;
		}
		
		var fields = new HashMap<string, string>();
		foreach(var entry in params.entries)
			fields.set(entry.key, entry.value);
		fields.set("api_key", api);
		if(requires_sk)
			fields.set("sk", session_key);
		fields.set("api_sig", signature(fields));
		
		new Thread<void*>("lastfm", () => {
			uint status;
			string body;
			if(type == "POST")
				body = BeatBox.Http.send("POST", HTTPS_BASE, "application/x-www-form-urlencoded", BeatBox.Http.form_encode(fields), null, out status);
			else
				body = BeatBox.Http.send("GET", HTTPS_BASE + "?" + BeatBox.Http.form_encode(fields), null, null, null, out status);
			if(status != 200)
				message("Last.fm %s answered %u: %s", fields.get("method"), status, body);
			call_back(body);
			return null;
		});
	}
	
	/** md5 of the parameters sorted by name, each name followed by its value, then the secret */
	static string signature(Map<string, string> fields) {
		var names = new ArrayList<string>();
		names.add_all(fields.keys);
		names.sort((a, b) => strcmp(a, b));
		var sb = new StringBuilder();
		foreach(var name in names) {
			sb.append(name);
			sb.append(fields.get(name));
		}
		sb.append(secret);
		return Checksum.compute_for_string(ChecksumType.MD5, sb.str);
	}
	
	public static string fix_for_url (string fix) {
		return Uri.escape_string (fix, "", false);
	}
	
	public void authenticate_user(string username, string password) {
		var params = new HashMap<string, string>();
		params.set("method", "auth.getMobileSession");
		params.set("username", username);
		params.set("password", password);
		
		query("POST", params, false, (body) => {
			string user = "";
			string key = "";
			bool subsc = false;;
			
			Xml.Doc* doc = Xml.Parser.parse_memory(body, body.length);
			Xml.Node* root = (doc != null) ? doc->get_root_element() : null;
			if(root == null) { // no answer, or not XML: still tell the preferences
				delete doc;
				Idle.add(() => { App.info.lastfm.login_returned(false); return false; });
				return;
			}
			
			for (Xml.Node* iter = root->children; iter != null; iter = iter->next) {
				if(iter->name == "session") {
					for(Xml.Node* n = iter->children; n != null; n = n->next) {
						if(n->name == "key") {
							key = n->get_content();
						}
						else if(n->name == "subscriber") {
							subsc = int.parse(n->get_content()) == 1;
						}
						else if(n->name == "name") {
							user = n->get_content();
						}
					}
				}
			}
			
			delete doc;
			
			bool success = false;
			if(!BeatBox.String.is_empty(key)) {
				App.info.lastfm.session_key = key;
				App.info.lastfm.is_subscriber = subsc;
				App.info.lastfm.username = user;
				
				success = true;
			}
			
			Idle.add( () => { App.info.lastfm.login_returned(success); return false; });
		});
	}
	
	public void logout_user() {
		session_key = "";
		username = "";
		is_subscriber = false;
		
		logged_out();
	}
	
	public void love_track(string title, string artist) {
		var params = new HashMap<string, string>();
		params.set("method", "track.love");
		params.set("artist", artist);
		params.set("track", title);
		
		query("POST", params, true, (body) => {
			
		});
	}
	
	/** Update's the user's currently playing track on last.fm
	 * 
	 */
	public void post_now_playing() {
		if(!BeatBox.App.playback.media_active || BeatBox.String.is_empty(session_key))
			return;
		
		var artist = BeatBox.App.playback.current_media.artist;
		var title = BeatBox.App.playback.current_media.title;
		var album_artist = BeatBox.App.playback.current_media.album_artist;
		var album = BeatBox.App.playback.current_media.album;
		
		var params = new HashMap<string, string>();
		params.set("method", "track.updateNowPlaying");
		params.set("track", title);
		params.set("artist", artist);
		params.set("albumArtist", album_artist);
		params.set("album", album);
		params.set("duration", BeatBox.App.playback.current_media.length.to_string());
		
		query("POST", params, true, (body) => {
			// TODO: Use corrections. Be careful though, because 
			// corrections should not be used in the scrobble() POST.
			debug("Now playing response: %s", body);
		});
	}
	
	/**
	 * Scrobbles the currently playing track to last.fm; started_at is when it
	 * began playing (unix time), as last.fm/api/scrobbling asks.
	 */
	public void scrobble(int64 started_at) {
		if(!BeatBox.App.playback.media_active || BeatBox.String.is_empty(session_key))
			return;
		
		var timestamp = started_at;
		var artist = BeatBox.App.playback.current_media.artist;
		var title = BeatBox.App.playback.current_media.title;
		var album_artist = BeatBox.App.playback.current_media.album_artist;
		var album = BeatBox.App.playback.current_media.album;
		
		var params = new HashMap<string, string>();
		params.set("method", "track.scrobble");
		params.set("track", title);
		params.set("artist", artist);
		params.set("albumArtist", album_artist);
		params.set("album", album);
		params.set("timestamp", timestamp.to_string());
		params.set("duration", BeatBox.App.playback.current_media.length.to_string());
		
		query("POST", params, true, (body) => {
			// TODO: Use the corrections returned
		});
	}
	
	public void fetch_current_similar_songs() {
		similarMedias.getSimilarTracks(BeatBox.App.playback.current_media);
	}
	
	void similar_retrieved_signal(Gee.LinkedList<BeatBox.Media> similarDos, Gee.LinkedList<BeatBox.Media> similarDont) {
		similar_retrieved(similarDos, similarDont);
	}
	
	public void fetch_top_artist_songs() {
		topArtistSongs.queryForTopArtistSongs(BeatBox.App.playback.current_media);
	}
	
	void top_artist_songs_retrieved_signal(HashTable<int, BeatBox.Media> songs) {
		top_artist_songs_retrieved(songs);
	}
	
	public void fetch_top_artist_albums() {
		topArtistAlbums.queryForTopArtistAlbums(BeatBox.App.playback.current_media);
	}
	
	void top_artist_albums_retrieved_signal(HashTable<int, BeatBox.ExternalAlbum> albums) {
		top_artist_albums_retrieved(albums);
	}
}
