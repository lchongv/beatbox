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
		var songs = new Gee.ArrayList<Media> ();
		foreach (var m in App.library.medias ())
			if (m.key == "song")
				songs.add (m);
		var changes = ItunesSyncPass.changes (songs, theirs, mine);
		if (changes.size == 0)
			return; // nothing to change writes nothing, so itunes7 isn't woken up for nothing
		// the sync rows and the songs in one transaction, then memory; null when
		// not committed: nothing changed, the next change retries
		var changed = ItunesSyncPass.save (App.database, changes);
		// the lists and the other listeners (it writes the same values again: harmless)
		if (changed != null && changed.size > 0)
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
}
