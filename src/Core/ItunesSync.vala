/*
 * Live sync with itunes7: play counts, last played, rating, per-song options
 * and the resume position, both ways and while both apps run. The agreement
 * (tables, units, rules, test cases) is docs/SYNC-BEATBOX.md in itunes7; the
 * rules themselves are PeerSync (core/Utils/PeerSync.vala).
 *
 * This app only READS itunes7's library.db (itunes7 keeps its counts in memory
 * and would overwrite anything written there; ItunesReader) and writes its own
 * beatbox.db.
 */
public class BeatBox.ItunesSync : GLib.Object {
	const uint DEBOUNCE_MS = 1000;

	string itunes7_db;
	FileMonitor? monitor;
	uint debounce_id;

	class Row : Object {
		public Media media;
		public string uri;
		public PeerSync.Side side;
		public bool saved; // its INSERT ran (the transaction may still fail: see save_rows)
		public Row (Media media, PeerSync.Side side) {
			this.media = media;
			this.uri = media.uri;
			this.side = side;
		}
	}

	public ItunesSync () {
		itunes7_db = Path.build_filename (Environment.get_user_data_dir (), "itunes7", "library.db");
		App.settings.main.notify["itunes7-sync"].connect ((s, p) => setting_changed ());
		App.library.medias_imported.connect ((l, t, added, failed) => schedule ()); // new songs may be in itunes7
		setting_changed ();
	}

	void setting_changed () {
		if (App.settings.main.itunes7_sync)
			start ();
		else
			stop ();
	}

	void start () {
		if (monitor != null)
			return;
		var dir = File.new_for_path (Path.get_dirname (itunes7_db));
		if (!dir.query_exists ()) {
			debug ("itunes7 sync: no %s, nothing to watch", dir.get_path ());
			return; // no itunes7: nothing to watch (until the option is turned on again)
		}
		var backup = Path.build_filename (Environment.get_user_data_dir (), "beatbox", "beatbox.db.pre-sync");
		if (!FileUtils.test (backup, FileTest.EXISTS) && !((DataBaseManager) App.database).backup_to (backup))
			return; // the first pass moves thousands of plays: not without a copy
		try {
			monitor = dir.monitor_directory (FileMonitorFlags.NONE);
		}
		catch (Error err) {
			warning ("itunes7 sync: cannot watch %s: %s", dir.get_path (), err.message);
			return;
		}
		monitor.changed.connect ((file, other, kind) => {
			// the database and its -wal only, NEVER -shm: reading a WAL database
			// writes it, so each of our reads would start another pass
			var name = file.get_basename ();
			if (name == "library.db" || name == "library.db-wal")
				schedule ();
		});
		schedule (); // the library is loaded already
	}

	void stop () {
		if (debounce_id != 0) {
			Source.remove (debounce_id);
			debounce_id = 0;
		}
		if (monitor != null) {
			monitor.cancel ();
			monitor = null;
		}
	}

	void schedule () {
		if (monitor == null)
			return; // off, or no itunes7
		if (debounce_id != 0)
			Source.remove (debounce_id);
		debounce_id = Timeout.add (DEBOUNCE_MS, () => {
			debounce_id = 0;
			pass ();
			return false;
		});
	}

	void pass () {
		var theirs = ItunesReader.read (itunes7_db);
		var mine = read_own_rows ();
		if (theirs == null || mine == null)
			return; // busy, half written or not there: the next change retries
		var rows = new Gee.ArrayList<Row> ();
		foreach (var m in App.library.medias ()) {
			if (m.key != "song" || m.uri == "")
				continue;
			var peer = theirs[m.uri];
			if (peer == null)
				continue;
			var me = mine[m.uri] ?? new PeerSync.Side ();
			me.count = m.play_count;
			me.last = m.last_played;
			me.f[PeerSync.RATING].cur = m.rating;
			me.f[PeerSync.SKIP_SHUFFLE].cur = m.skip_shuffle ? 1 : 0;
			me.f[PeerSync.REMEMBER_POS].cur = m.remember_position ? 1 : 0;
			me.f[PeerSync.VOLUME_ADJUST].cur = m.volume_adjust;
			me.f[PeerSync.RESUME_POS].cur = m.resume_pos;
			int64 added;
			if (PeerSync.sync_side (me, peer, false, out added))
				rows.add (new Row (m, me));
		}
		// The sync rows BEFORE the songs (two transactions): if BeatBox dies in
		// between, the next pass puts it right; the other way round those plays
		// would count twice (case 18 of docs/SYNC-BEATBOX.md). For the same
		// reason a song, even in memory, only changes once its row is saved.
		// Nothing to change writes nothing, so itunes7 isn't woken up for nothing.
		if (rows.size == 0 || !save_rows (rows))
			return; // not committed: nothing changed, the next change retries
		var changed = new Gee.LinkedList<Media> ();
		foreach (var row in rows) {
			if (!row.saved)
				continue; // the next change retries it
			var m = row.media;
			var me = row.side;
			if (m.play_count != me.count || m.last_played != me.last || m.rating != me.f[PeerSync.RATING].cur
					|| m.skip_shuffle != (me.f[PeerSync.SKIP_SHUFFLE].cur != 0)
					|| m.remember_position != (me.f[PeerSync.REMEMBER_POS].cur != 0)
					|| m.volume_adjust != me.f[PeerSync.VOLUME_ADJUST].cur
					|| m.resume_pos != me.f[PeerSync.RESUME_POS].cur) {
				m.play_count = (uint) me.count;
				m.last_played = (uint) me.last;
				m.rating = (uint) me.f[PeerSync.RATING].cur;
				m.skip_shuffle = me.f[PeerSync.SKIP_SHUFFLE].cur != 0;
				m.remember_position = me.f[PeerSync.REMEMBER_POS].cur != 0;
				m.volume_adjust = (int) me.f[PeerSync.VOLUME_ADJUST].cur;
				m.resume_pos = (int) me.f[PeerSync.RESUME_POS].cur;
				changed.add (m);
			}
		}
		if (changed.size > 0)
			App.library.update_medias (changed, false, false, true);
	}

	Gee.HashMap<string, PeerSync.Side>? read_own_rows () {
		var r = App.database.execute ("SELECT uri, " + ItunesReader.SYNC_COLUMNS + " FROM itunes7_sync");
		if (r == null)
			return null; // DataBaseManager already warned
		var rows = new Gee.HashMap<string, PeerSync.Side> ();
		try {
			for (; !r.finished; r.next ()) {
				var s = new PeerSync.Side ();
				s.plays_in = r.fetch_int64 (1);
				for (int i = 0; i < PeerSync.N_FIELDS; i++) {
					s.f[i].agreed = r.fetch_int64 (2 + 2 * i);
					s.f[i].epoch = r.fetch_int64 (3 + 2 * i);
				}
				rows[r.fetch_string (0)] = s;
			}
		}
		catch (SQLHeavy.Error err) {
			warning ("itunes7 sync: %s", err.message);
			return null; // without our own rows the plays already added would count again
		}
		return rows;
	}

	/** true once the transaction is committed: an INSERT that failed with
	 * SQLITE_FULL, IOERR or NOMEM can roll back the rows already written */
	bool save_rows (Gee.ArrayList<Row> rows) {
		var filler = new DatabaseTransactionFiller ();
		filler.data = rows;
		filler.filler = save_rows_filler;
		App.database.queue_transaction (filler); // runs now: no transaction is open outside a filler
		return filler.committed;
	}

	void save_rows_filler (ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller db_filler) {
		var rows = (Gee.ArrayList<Row>) db_filler.data;
		string[] fields = { "rating", "skip_shuffle", "remember_pos", "volume_adjust", "resume_pos" };
		try {
			var query = transaction.prepare ("INSERT OR REPLACE INTO itunes7_sync (uri, %s) VALUES (:uri, :plays_in, :rating, :rating_ep, :skip_shuffle, :skip_shuffle_ep, :remember_pos, :remember_pos_ep, :volume_adjust, :volume_adjust_ep, :resume_pos, :resume_pos_ep)".printf (ItunesReader.SYNC_COLUMNS));
			foreach (var row in rows) {
				query.set_string (":uri", row.uri);
				query.set_int64 (":plays_in", row.side.plays_in);
				for (int i = 0; i < PeerSync.N_FIELDS; i++) {
					query.set_int64 (":" + fields[i], row.side.f[i].agreed);
					query.set_int64 (":" + fields[i] + "_ep", row.side.f[i].epoch);
				}
				query.execute ();
				row.saved = true;
			}
		}
		catch (SQLHeavy.Error err) {
			warning ("itunes7 sync: could not save: %s", err.message);
		}
	}
}
