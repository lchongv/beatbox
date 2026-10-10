/*
 * What ItunesSync reads from itunes7's library.db (docs/SYNC-BEATBOX.md in
 * itunes7, section 1.3), in a file of its own so tests/itunes-reader.vala can
 * run it without the rest of BeatBox. Read only: itunes7 keeps its counts in
 * memory and would overwrite anything written there.
 */
namespace BeatBox.ItunesReader {
	// the sync columns of a row, in PeerSync's field order
	public const string SYNC_COLUMNS = "plays_in, rating, rating_ep, skip_shuffle, skip_shuffle_ep, remember_pos, remember_pos_ep, volume_adjust, volume_adjust_ep, resume_pos, resume_pos_ep";

	/** itunes7's songs by URI, in common units; null when they can't be read */
	public Gee.HashMap<string, PeerSync.Side>? read (string path) {
		Sqlite.Database db;
		if (Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY) != Sqlite.OK) {
			warning ("itunes7 sync: cannot open %s", path);
			return null;
		}
		db.busy_timeout (2000);
		// the table check and the songs in ONE read transaction: one snapshot of
		// the library, and one wait when itunes7 holds it
		if (db.exec ("BEGIN") != Sqlite.OK) {
			warning ("itunes7 sync: %s", db.errmsg ());
			return null;
		}
		var rows = read_in_transaction (db);
		db.exec ("COMMIT"); // read only: nothing to lose
		return rows;
	}

	static Gee.HashMap<string, PeerSync.Side>? read_in_transaction (Sqlite.Database db) {
		bool has_sync;
		// an error here is NOT "no such table": with plays_in read as 0, every
		// play already given to itunes7 would come back and count twice
		if (!table_exists (db, "beatbox_sync", out has_sync)) {
			warning ("itunes7 sync: %s", db.errmsg ());
			return null;
		}
		var sql = "SELECT t.uri, t.play_count, t.last_played, t.rating, t.skip_shuffle, t.remember_pos, t.volume_adjust, COALESCE(b.pos, 0), "
			+ (has_sync ? prefixed_sync_columns ("x") : "0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0")
			+ " FROM tracks t LEFT JOIN bookmarks b ON b.uri = t.uri"
			+ (has_sync ? " LEFT JOIN beatbox_sync x ON x.uri = t.uri" : "");
		Sqlite.Statement st;
		if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
			warning ("itunes7 sync: %s", db.errmsg ());
			return null;
		}
		var rows = new Gee.HashMap<string, PeerSync.Side> ();
		int rc;
		while ((rc = st.step ()) == Sqlite.ROW) {
			var uri = st.column_text (0);
			if (uri == null || uri == "")
				continue;
			var s = new PeerSync.Side ();
			s.count = st.column_int64 (1);
			s.last = st.column_int64 (2);
			int64 stars = (st.column_int64 (3) + 10) / 20; // itunes7 keeps 0-100
			s.f[PeerSync.RATING].cur = stars < 0 ? 0 : (stars > 5 ? 5 : stars);
			s.f[PeerSync.SKIP_SHUFFLE].cur = st.column_int64 (4) != 0 ? 1 : 0;
			s.f[PeerSync.REMEMBER_POS].cur = st.column_int64 (5) != 0 ? 1 : 0;
			s.f[PeerSync.VOLUME_ADJUST].cur = st.column_int64 (6);
			int64 seconds = st.column_int64 (7) / 1000000000; // nanoseconds there
			s.f[PeerSync.RESUME_POS].cur = seconds < 0 ? 0 : seconds; // as itunes7 reads it
			int col = 8;
			s.plays_in = st.column_int64 (col++);
			for (int i = 0; i < PeerSync.N_FIELDS; i++) {
				s.f[i].agreed = st.column_int64 (col++);
				s.f[i].epoch = st.column_int64 (col++);
			}
			rows[uri] = s;
		}
		if (rc != Sqlite.DONE) {
			warning ("itunes7 sync: %s", db.errmsg ());
			return null;
		}
		return rows;
	}

	static string prefixed_sync_columns (string table) {
		var cols = SYNC_COLUMNS.split (", ");
		for (int i = 0; i < cols.length; i++)
			cols[i] = "COALESCE(%s.%s, 0)".printf (table, cols[i]);
		return string.joinv (", ", cols);
	}

	/** false when the check itself failed (busy, unreadable): then exists means nothing */
	static bool table_exists (Sqlite.Database db, string name, out bool exists) {
		exists = false;
		Sqlite.Statement st;
		if (db.prepare_v2 ("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", -1, out st) != Sqlite.OK)
			return false;
		st.bind_text (1, name);
		int rc = st.step ();
		exists = rc == Sqlite.ROW;
		return rc == Sqlite.ROW || rc == Sqlite.DONE;
	}
}
