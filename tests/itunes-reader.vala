// meson test: what BeatBox reads from itunes7's library.db for the live sync
// (src/Core/ItunesReader.vala; docs/SYNC-BEATBOX.md in itunes7, sections 1.2 and 1.3)
using BeatBox;

const string URI = "file:///music/a.ogg";

void exec (Sqlite.Database db, string sql) {
	string errmsg;
	if (db.exec (sql, null, out errmsg) != Sqlite.OK)
		error ("%s: %s", sql, errmsg);
}

// a stand-in itunes7 library (its tables as itunes7 creates them), in WAL mode like the real one
string make_library (bool with_sync_table) {
	string dir;
	try {
		dir = DirUtils.make_tmp ("bb-itunesreader-XXXXXX");
	} catch (FileError e) {
		error ("%s", e.message);
	}
	var path = Path.build_filename (dir, "library.db");
	Sqlite.Database db;
	assert (Sqlite.Database.open (path, out db) == Sqlite.OK);
	exec (db, """PRAGMA journal_mode=WAL;
CREATE TABLE tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT UNIQUE NOT NULL,
	play_count INTEGER NOT NULL DEFAULT 0, last_played INTEGER NOT NULL DEFAULT 0,
	rating INTEGER NOT NULL DEFAULT 0, skip_shuffle INTEGER NOT NULL DEFAULT 0,
	remember_pos INTEGER NOT NULL DEFAULT 0, volume_adjust INTEGER NOT NULL DEFAULT 0);
CREATE TABLE bookmarks (uri TEXT PRIMARY KEY NOT NULL, pos INTEGER NOT NULL DEFAULT 0);
INSERT INTO tracks (uri, play_count, last_played, rating, skip_shuffle, remember_pos, volume_adjust)
	VALUES ('file:///music/a.ogg', 13, 1700000000, 50, 2, 1, -30);
INSERT INTO tracks (uri, play_count) VALUES ('', 7);
INSERT INTO bookmarks VALUES ('file:///music/a.ogg', 125900000000);""");
	if (with_sync_table)
		exec (db, """CREATE TABLE beatbox_sync (
	uri TEXT PRIMARY KEY,
	plays_in INTEGER NOT NULL DEFAULT 0,
	rating INTEGER NOT NULL DEFAULT 0, rating_ep INTEGER NOT NULL DEFAULT 0,
	skip_shuffle INTEGER NOT NULL DEFAULT 0, skip_shuffle_ep INTEGER NOT NULL DEFAULT 0,
	remember_pos INTEGER NOT NULL DEFAULT 0, remember_pos_ep INTEGER NOT NULL DEFAULT 0,
	volume_adjust INTEGER NOT NULL DEFAULT 0, volume_adjust_ep INTEGER NOT NULL DEFAULT 0,
	resume_pos INTEGER NOT NULL DEFAULT 0, resume_pos_ep INTEGER NOT NULL DEFAULT 0);
INSERT INTO beatbox_sync VALUES ('file:///music/a.ogg', 3, 2, 4, 1, 5, 1, 6, -30, 7, 125, 8);""");
	return path;
}

void remove_library (string path) {
	foreach (var suffix in new string[] { "", "-wal", "-shm" })
		FileUtils.remove (path + suffix);
	DirUtils.remove (Path.get_dirname (path));
}

// the values in common units, and the sync row whole
void test_read () {
	var path = make_library (true);
	var rows = ItunesReader.read (path);
	remove_library (path);
	assert (rows != null);
	assert (rows.size == 1); // no song without a URI: nothing to pair it with
	var s = rows[URI];
	assert (s.count == 13 && s.last == 1700000000);
	assert (s.f[PeerSync.RATING].cur == 3);         // (50 + 10) / 20: half a star rounds up
	assert (s.f[PeerSync.SKIP_SHUFFLE].cur == 1);   // any value but 0 is 1
	assert (s.f[PeerSync.REMEMBER_POS].cur == 1);
	assert (s.f[PeerSync.VOLUME_ADJUST].cur == -30);
	assert (s.f[PeerSync.RESUME_POS].cur == 125);   // nanoseconds there
	assert (s.plays_in == 3);
	for (int i = 0; i < PeerSync.N_FIELDS; i++)
		assert (s.f[i].epoch == 4 + i);
	assert (s.f[PeerSync.RATING].agreed == 2 && s.f[PeerSync.RESUME_POS].agreed == 125);
}

// an itunes7 without the sync yet: its row counts as all 0
void test_no_sync_table () {
	var path = make_library (false);
	var rows = ItunesReader.read (path);
	remove_library (path);
	assert (rows != null);
	var s = rows[URI];
	assert (s.count == 13 && s.f[PeerSync.RATING].cur == 3);
	assert (s.plays_in == 0);
	for (int i = 0; i < PeerSync.N_FIELDS; i++)
		assert (s.f[i].agreed == 0 && s.f[i].epoch == 0);
}

void test_missing () {
	assert (ItunesReader.read ("/nonexistent/itunes7/library.db") == null);
}

// Regression: itunes7 releases its lock WHILE the read waits. A failed check for
// beatbox_sync must not read as "no such table": plays_in would be 0 and BeatBox
// would add again every play it already gave itunes7 (13 - 0 instead of 13 - 3).
// Failing the read is right (the next change retries); a read with 3 is too.
void test_lock_released () {
	var path = make_library (true);
	Sqlite.Database? locker;
	assert (Sqlite.Database.open (path, out locker) == Sqlite.OK);
	// in WAL mode only an exclusive locking mode keeps readers out
	exec (locker, "PRAGMA locking_mode=EXCLUSIVE; BEGIN EXCLUSIVE;");
	var release = new Thread<bool> ("release-lock", () => {
		Thread.usleep (2500 * 1000); // past the 2 s wait of the check, within the next one
		exec (locker, "ROLLBACK");
		locker = null; // closes it: the exclusive lock goes
		return true;
	});
	var rows = ItunesReader.read (path);
	release.join ();
	if (rows != null && rows[URI].plays_in != 3)
		error ("read plays_in %s instead of 3: those plays would count twice", rows[URI].plays_in.to_string ());
	assert (ItunesReader.read (path)[URI].plays_in == 3); // once free, it reads whole
	remove_library (path);
}

// out-of-range values read as itunes7 reads them in its own pass: stars 0-5,
// seconds >= 0 (docs/SYNC-BEATBOX.md section 1.2)
void test_clamps () {
	var path = make_library (true);
	Sqlite.Database db;
	assert (Sqlite.Database.open (path, out db) == Sqlite.OK);
	exec (db, "UPDATE tracks SET rating = 250; UPDATE bookmarks SET pos = -125900000000;");
	db = null;
	var rows = ItunesReader.read (path);
	remove_library (path);
	assert (rows != null);
	var s = rows[URI];
	assert (s.f[PeerSync.RATING].cur == 5);
	if (s.f[PeerSync.RESUME_POS].cur != 0)
		error ("a position of %s s: itunes7 reads 0", s.f[PeerSync.RESUME_POS].cur.to_string ());
}

void main () {
	test_read ();
	test_no_sync_table ();
	test_missing ();
	test_lock_released ();
	test_clamps ();
}
