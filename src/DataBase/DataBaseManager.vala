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

using SQLHeavy;
using Gee;

public class BeatBox.DataBaseManager : GLib.Object, BeatBox.DatabaseInterface {
	const string SCHEMA = """
CREATE TABLE IF NOT EXISTS known_libraries (
	'key' TEXT
);

CREATE TABLE IF NOT EXISTS songs (
	'uri' TEXT,
	'file_size' INT,
	'title' TEXT,
	'artist' TEXT,
	'composer' TEXT,
	'album_artist' TEXT,
	'album' TEXT,
	'grouping' TEXT,
	'genre' TEXT,
	'comment' TEXT,
	'lyrics' TEXT,
	'album_path' TEXT,
	'has_embedded' INT,
	'year' INT,
	'track' INT,
	'track_count' INT,
	'album_number' INT,
	'album_count' INT,
	'bitrate' INT,
	'length' INT,
	'samplerate' INT,
	'rating' INT,
	'playcount' INT,
	'skipcount' INT,
	'dateadded' INT,
	'lastplayed' INT,
	'lastmodified' INT,
	'mediatype' INT,
	'podcast_rss' TEXT,
	'podcast_url' TEXT,
	'podcast_date' INT,
	'is_new_podcast' INT,
	'resume_pos' INT,
	'is_video' INT
);

CREATE TABLE IF NOT EXISTS podcasts (
	'uri' TEXT,
	'file_size' INT,
	'title' TEXT,
	'artist' TEXT,
	'composer' TEXT,
	'album_artist' TEXT,
	'album' TEXT,
	'grouping' TEXT,
	'genre' TEXT,
	'comment' TEXT,
	'lyrics' TEXT,
	'album_path' TEXT,
	'has_embedded' INT,
	'year' INT,
	'track' INT,
	'track_count' INT,
	'album_number' INT,
	'album_count' INT,
	'bitrate' INT,
	'length' INT,
	'samplerate' INT,
	'rating' INT,
	'playcount' INT,
	'skipcount' INT,
	'dateadded' INT,
	'lastplayed' INT,
	'lastmodified' INT,
	'mediatype' INT,
	'podcast_rss' TEXT,
	'podcast_url' TEXT,
	'podcast_date' INT,
	'is_new_podcast' INT,
	'resume_pos' INT,
	'is_video' INT
);

CREATE TABLE IF NOT EXISTS stations (
	'uri' TEXT,
	'file_size' INT,
	'title' TEXT,
	'artist' TEXT,
	'composer' TEXT,
	'album_artist' TEXT,
	'album' TEXT,
	'grouping' TEXT,
	'genre' TEXT,
	'comment' TEXT,
	'lyrics' TEXT,
	'album_path' TEXT,
	'has_embedded' INT,
	'year' INT,
	'track' INT,
	'track_count' INT,
	'album_number' INT,
	'album_count' INT,
	'bitrate' INT,
	'length' INT,
	'samplerate' INT,
	'rating' INT,
	'playcount' INT,
	'skipcount' INT,
	'dateadded' INT,
	'lastplayed' INT,
	'lastmodified' INT,
	'mediatype' INT,
	'podcast_rss' TEXT,
	'podcast_url' TEXT,
	'podcast_date' INT,
	'is_new_podcast' INT,
	'resume_pos' INT,
	'is_video' INT
);

CREATE TABLE IF NOT EXISTS playlists (
	'name' TEXT,
	'medias' TEXT
);

CREATE TABLE IF NOT EXISTS smart_playlists (
	'name' TEXT,
	'and_or' INT,
	'queries' TEXT,
	'limit_results' INT,
	'limit_amount' INT
);
				
CREATE TABLE IF NOT EXISTS devices (
	'unique_id' TEXT,
	'sync_when_mounted' INT,
	'sync_music' INT,
	'sync_podcasts' INT,
	'sync_audiobooks' INT,
	'sync_all_music' INT,
	'sync_all_podcasts' INT,
	'sync_all_audiobooks' INT,
	'music_playlist' TEXT,
	'podcast_playlist' TEXT,
	'audiobook_playlist' TEXT,
	'last_sync_time' INT
);
				
CREATE TABLE IF NOT EXISTS artists (
	'artist' TEXT,
	'full_desc' TEXT,
	'short_desc' TEXT,
	'merged_desc' TEXT,
	'tags' TEXT,
	'more_info_urls' TEXT,
	'similar_artists' TEXT,
	'photo_uri' TEXT
);

CREATE TABLE IF NOT EXISTS albums (
	'album' TEXT,
	'album_artist' TEXT,
	'full_desc' TEXT,
	'short_desc' TEXT,
	'merged_desc' TEXT,
	'tags' TEXT,
	'more_info_urls' TEXT,
	'release_date' TEXT,
	'similar_albums' TEXT,
	'art_uri' TEXT
);

CREATE TABLE IF NOT EXISTS tracks (
	'title' TEXT,
	'artist' TEXT,
	'full_desc' TEXT,
	'short_desc' TEXT,
	'merged_desc' TEXT,
	'tags' TEXT,
	'more_info_urls' TEXT,
	'lyrics' TEXT
);

CREATE TABLE IF NOT EXISTS list_setups (
	'key' TEXT,
	'hint' INT,
	'sort_column_id' INT,
	'sort_direction' TEXT,
	'columns' TEXT
);
""";

	SQLHeavy.Database _db;
	
	LinkedList<DatabaseTransactionFiller> periodic_transactions;
	LinkedList<DatabaseTransactionFiller> transaction_queue;
	Transaction transaction;// the current sql transaction
	
	// App.database represents the default database, but plugins may want to use this
	// file on their own database, so allow for that.
	public DataBaseManager() {
		periodic_transactions = new LinkedList<DatabaseTransactionFiller>();
		transaction_queue = new LinkedList<DatabaseTransactionFiller>();
		
		// First make sure that the folder that the database will be in exists
		var user_database_folder = GLib.File.new_for_path(GLib.Path.build_filename(Environment.get_user_data_dir(), "beatbox"));
		if(!user_database_folder.query_exists()) {
			try {
				user_database_folder.make_directory_with_parents(null);
			}
			catch(GLib.Error err) {
				critical("Could not create beatbox folder in data directory: %s\n", err.message);
			}
		}
		
		// Open the database and create any missing table
		try {
			_db = new SQLHeavy.Database (GLib.Path.build_filename(user_database_folder.get_path(), "beatbox.db"));
			_db.execute (SCHEMA);
		}
		catch (SQLHeavy.Error err) {
			critical("Could not load database: %s", err.message);
		}
		
		// Every 15 seconds, do the periodic saves
		Timeout.add(15000, periodic_save);
	}
	
	public QueryResult execute(string statement) {
		QueryResult? rv = null;
		
		try {
			Query query = new Query(_db, statement);
			rv = query.execute();
		}
		catch (SQLHeavy.Error err) {
			warning("Could not execute statement '%s': %s\n", statement, err.message);
		}
		
		return rv;
	}
	
	// These functions must have mutual exclusion
	// This is the entrance function
	public void queue_transaction(DatabaseTransactionFiller db_filler) {
		if(transaction == null) {
			begin_transaction(db_filler);
		}
		else {
			transaction_queue.offer(db_filler);
		}
	}
	
	// TODO: Thread this
	void begin_transaction(DatabaseTransactionFiller db_filler) {
		try {
			if(db_filler.pre_transaction_execute != null && db_filler.pre_transaction_execute != "") {
				_db.execute(db_filler.pre_transaction_execute);
			}
			
			transaction = _db.begin_transaction();
			db_filler.filler(ref transaction, db_filler);
			transaction.commit();
		} catch(SQLHeavy.Error err) {
			warning("Could not commit transaction: %s \n", err.message);
		}
		
		transaction = null;
		
		if(transaction_queue.size > 0) {
			begin_transaction(transaction_queue.poll());
		}
		else {
			transactions_finished();
		}
	}
	
	void transactions_finished() {
		transaction = null;
	}
	
	public void add_periodic_transaction(DatabaseTransactionFiller periodic_filler) {
		periodic_transactions.add(periodic_filler);
	}
	
	bool periodic_save() {
		debug("Doing periodic save");
		
		foreach(var filler in periodic_transactions) {
			queue_transaction(filler);
		}
		
		return true;
	}
}
