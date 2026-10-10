// meson test: what ItunesSync's pass changes and how it writes it
// (src/Core/ItunesSyncPass.vala; docs/SYNC-BEATBOX.md in itunes7), on a library
// in a temporary data folder: never the real one
using BeatBox;

const string A = "file:///music/a.ogg";
const string B = "file:///music/b.ogg";

void exec (DataBaseManager db, string sql) {
	if (db.execute (sql) == null)
		error ("%s failed", sql);
}

int64 value (DataBaseManager db, string sql) {
	try {
		var r = db.execute (sql);
		assert (r != null && !r.finished);
		return r.fetch_int64 (0);
	} catch (SQLHeavy.Error e) {
		error ("%s: %s", sql, e.message);
	}
}

// a song as BeatBox has it in memory and in 'songs', with its sync row
Media add_song (DataBaseManager db, int rowid, string uri, uint plays, int64 plays_in) {
	exec (db, "INSERT INTO songs (rowid, uri, playcount, lastplayed, rating, skip_shuffle, remember_position, volume_adjust, resume_pos) VALUES (%d, '%s', %u, 100, 0, 0, 0, 0, 0)".printf (rowid, uri, plays));
	exec (db, "INSERT INTO itunes7_sync (uri, plays_in) VALUES ('%s', %s)".printf (uri, plays_in.to_string ()));
	var m = new Preview (uri);
	m.rowid = rowid;
	m.play_count = plays;
	m.last_played = 100;
	return m;
}

PeerSync.Side side (int64 count, int64 plays_in, int64 last) {
	var s = new PeerSync.Side ();
	s.count = count;
	s.plays_in = plays_in;
	s.last = last;
	return s;
}

// this app's sync rows as ItunesSync reads them
Gee.HashMap<string, PeerSync.Side> own_rows (DataBaseManager db) {
	var rows = new Gee.HashMap<string, PeerSync.Side> ();
	try {
		for (var r = db.execute ("SELECT uri, plays_in FROM itunes7_sync"); !r.finished; r.next ())
			rows[r.fetch_string (0)] = side (0, r.fetch_int64 (1), 0);
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}
	return rows;
}

// case 3 of docs/SYNC-BEATBOX.md for song a (a play in itunes7: A 15/4, B 14/10 -> B 15/11),
// and the same for b when there is one
Gee.ArrayList<ItunesSyncPass.Change> plan (DataBaseManager db, Gee.List<Media> songs) {
	var theirs = new Gee.HashMap<string, PeerSync.Side> ();
	theirs[A] = side (15, 4, 200);
	theirs[B] = side (15, 4, 200);
	var changes = ItunesSyncPass.changes (songs, theirs, own_rows (db));
	assert (changes.size == songs.size);
	return changes;
}

void reset (DataBaseManager db) {
	exec (db, "DELETE FROM songs");
	exec (db, "DELETE FROM itunes7_sync");
}

// The song and its sync row change in the SAME transaction: itunes7 reads
// beatbox.db while BeatBox runs, and a sync row it sees without its song
// (plays_in 11, playcount still 14) makes it count that play twice
void test_together (DataBaseManager db) {
	reset (db);
	var a = add_song (db, 1, A, 14, 10);
	var songs = new Gee.ArrayList<Media> ();
	songs.add (a);
	var changed = ItunesSyncPass.save (db, plan (db, songs));
	assert (changed != null && changed.size == 1 && changed[0] == a);
	assert (value (db, "SELECT plays_in FROM itunes7_sync WHERE uri = '%s'".printf (A)) == 11);
	var plays = value (db, "SELECT playcount FROM songs WHERE rowid = 1");
	if (plays != 15)
		error ("the sync row is saved and the song isn't (playcount %s): itunes7 would count a play twice", plays.to_string ());
	assert (value (db, "SELECT lastplayed FROM songs WHERE rowid = 1") == 200);
	assert (a.play_count == 15 && a.last_played == 200);
}

// nothing changed: the rows, the songs and the songs in memory as before
void assert_untouched (DataBaseManager db, Media a, Media b) {
	foreach (var m in new Media[] { a, b }) {
		var plays_in = value (db, "SELECT plays_in FROM itunes7_sync WHERE uri = '%s'".printf (m.uri));
		if (plays_in != 10)
			error ("%s: its sync row was saved (plays_in %s) by a pass that failed", m.uri, plays_in.to_string ());
		assert (value (db, "SELECT playcount FROM songs WHERE rowid = %d".printf (m.rowid)) == 14);
		if (m.play_count != 14 || m.last_played != 100)
			error ("%s changed in memory after a pass that failed", m.uri);
	}
}

// A write that fails halfway (here b's song, as with a full disk) loses the
// whole pass: a's sync row and song too, and nothing changes in memory
void test_statement_fails (DataBaseManager db) {
	reset (db);
	var a = add_song (db, 1, A, 14, 10);
	var b = add_song (db, 2, B, 14, 10);
	var songs = new Gee.ArrayList<Media> ();
	songs.add (a);
	songs.add (b);
	var changes = plan (db, songs);
	exec (db, "CREATE TEMP TRIGGER fail_b BEFORE UPDATE ON songs WHEN OLD.rowid = 2 BEGIN SELECT RAISE(ABORT, 'disk full'); END");
	var changed = ItunesSyncPass.save (db, changes);
	exec (db, "DROP TRIGGER fail_b");
	assert (changed == null);
	assert_untouched (db, a, b);
}

// A COMMIT that fails (itunes7 still reading after the wait) loses it all too
void test_commit_fails (DataBaseManager db, string path) {
	reset (db);
	var a = add_song (db, 1, A, 14, 10);
	var b = add_song (db, 2, B, 14, 10);
	var songs = new Gee.ArrayList<Media> ();
	songs.add (a);
	songs.add (b);
	var changes = plan (db, songs);
	Sqlite.Database? reader; // holds a read transaction, as itunes7 does while it reads
	assert (Sqlite.Database.open_v2 (path, out reader, Sqlite.OPEN_READONLY) == Sqlite.OK);
	Sqlite.Statement? st;
	assert (reader.exec ("BEGIN") == Sqlite.OK);
	assert (reader.prepare_v2 ("SELECT count(*) FROM songs", -1, out st) == Sqlite.OK);
	assert (st.step () == Sqlite.ROW);
	var changed = ItunesSyncPass.save (db, changes);
	st = null;
	assert (reader.exec ("COMMIT") == Sqlite.OK);
	reader = null;
	assert (changed == null);
	assert_untouched (db, a, b);
}

// BeatBox's own rating and position read as itunes7 reads them (stars 0-5,
// seconds >= 0; docs/SYNC-BEATBOX.md section 1.2): an iPod import can leave a
// rating above 5. Otherwise the two apps decide on different numbers and never
// agree. Like a half star in itunes7, the value is only rewritten when the
// other app's is adopted
void test_clamps (DataBaseManager db) {
	reset (db);
	var a = add_song (db, 1, A, 14, 10);
	exec (db, "UPDATE songs SET rating = 60, remember_position = 1, resume_pos = -30 WHERE rowid = 1");
	a.rating = 60;
	a.remember_position = true;
	a.resume_pos = -30;
	var theirs = new Gee.HashMap<string, PeerSync.Side> ();
	var it7 = side (14, 4, 100); // A 14/4, B 14/10: no new plays, only the data
	it7.f[PeerSync.RATING].cur = 5;
	it7.f[PeerSync.REMEMBER_POS].cur = 1;
	theirs[A] = it7;
	var songs = new Gee.ArrayList<Media> ();
	songs.add (a);
	var changes = ItunesSyncPass.changes (songs, theirs, own_rows (db));
	assert (changes.size == 1); // the agreement on 5 stars is noted
	var c = changes[0];
	if (c.side.f[PeerSync.RATING].cur != 5 || c.side.f[PeerSync.RESUME_POS].cur != 0)
		error ("BeatBox takes rating %s and position %s; itunes7 reads them as 5 and 0",
			c.side.f[PeerSync.RATING].cur.to_string (), c.side.f[PeerSync.RESUME_POS].cur.to_string ());
	assert (c.side.f[PeerSync.RATING].agreed == 5 && c.side.f[PeerSync.RATING].epoch == 1);
	assert (!c.song_changed);
	assert (ItunesSyncPass.save (db, changes) != null);
	assert (value (db, "SELECT rating FROM itunes7_sync WHERE uri = '%s'".printf (A)) == 5);
	assert (value (db, "SELECT rating FROM songs WHERE rowid = 1") == 60);
	assert (value (db, "SELECT resume_pos FROM songs WHERE rowid = 1") == -30);
	assert (a.rating == 60 && a.resume_pos == -30);
}

// songs.uri is not UNIQUE. Of two songs on one file only one syncs, the one
// itunes7 reads (the last of its SELECT, in rowid order): sharing one sync row
// they would both take the same plays, and each its own Side
void test_duplicates (DataBaseManager db) {
	reset (db);
	var first = add_song (db, 1, A, 14, 10);
	exec (db, "INSERT INTO songs (rowid, uri, playcount, lastplayed) VALUES (3, '%s', 14, 100)".printf (A));
	var last = new Preview (A);
	last.rowid = 3;
	last.play_count = 14;
	last.last_played = 100;
	var songs = new Gee.ArrayList<Media> ();
	songs.add (last);
	songs.add (first);
	var theirs = new Gee.HashMap<string, PeerSync.Side> ();
	theirs[A] = side (15, 4, 200);
	var changes = ItunesSyncPass.changes (songs, theirs, own_rows (db));
	if (changes.size != 1)
		error ("%d changes for one file", changes.size);
	assert (changes[0].media == last);
	assert (ItunesSyncPass.save (db, changes) != null);
	assert (last.play_count == 15 && value (db, "SELECT playcount FROM songs WHERE rowid = 3") == 15);
	assert (first.play_count == 14 && value (db, "SELECT playcount FROM songs WHERE rowid = 1") == 14);
	assert (value (db, "SELECT plays_in FROM itunes7_sync WHERE uri = '%s'".printf (A)) == 11);
}

void main () {
	string dir;
	try {
		dir = DirUtils.make_tmp ("bb-syncpass-XXXXXX");
	} catch (FileError e) {
		error ("%s", e.message);
	}
	// GLib keeps the data folder it sees first: make sure it is this one before
	// anything opens a library
	Environment.set_variable ("XDG_DATA_HOME", dir, true);
	if (Environment.get_user_data_dir () != dir)
		error ("the data folder is %s, not the temporary one", Environment.get_user_data_dir ());

	var db = new DataBaseManager ();
	var library_dir = Path.build_filename (dir, "beatbox");
	var path = Path.build_filename (library_dir, "beatbox.db");
	test_together (db);
	test_statement_fails (db);
	test_commit_fails (db, path);
	test_clamps (db);
	test_duplicates (db);

	db = null;
	foreach (var name in new string[] { "beatbox.db", "beatbox.db-journal" })
		FileUtils.remove (Path.build_filename (library_dir, name));
	DirUtils.remove (library_dir);
	DirUtils.remove (dir);
}
