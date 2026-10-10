// meson test: the database waits up to 2 s while another process holds it,
// instead of failing with SQLITE_BUSY and losing the write (itunes7 reads it live)
void test_busy_timeout () {
	try {
		var dir = DirUtils.make_tmp ("bb-busy-XXXXXX");
		var db = new SQLHeavy.Database (Path.build_filename (dir, "t.db"));
		var r = new SQLHeavy.Query (db, "PRAGMA busy_timeout").execute ();
		assert (!r.finished);
		assert (r.fetch_int (0) == 2000);
	} catch (Error e) {
		error ("%s", e.message);
	}
}

// a fresh connection, as itunes7 reads: true if it can read the table now
bool can_read (string path) {
	Sqlite.Database db;
	assert (Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY) == Sqlite.OK);
	db.busy_timeout (100);
	Sqlite.Statement st;
	if (db.prepare_v2 ("SELECT count(*) FROM t", -1, out st) != Sqlite.OK)
		return false;
	return st.step () == Sqlite.ROW;
}

// A COMMIT that still meets a reader after the wait fails. The transaction must
// not stay open: it would keep its lock (itunes7 could no longer read), every
// later BEGIN would fail and later writes would join it, to be lost at exit
void test_failed_commit () {
	try {
		var dir = DirUtils.make_tmp ("bb-busy-XXXXXX");
		var path = Path.build_filename (dir, "t.db");
		var db = new SQLHeavy.Database (path);
		db.execute ("PRAGMA busy_timeout = 100; CREATE TABLE t (n INT); INSERT INTO t VALUES (1);");

		Sqlite.Database reader; // holds a read transaction, as itunes7 does while it reads
		assert (Sqlite.Database.open (path, out reader) == Sqlite.OK);
		Sqlite.Statement? st;
		assert (reader.exec ("BEGIN") == Sqlite.OK);
		assert (reader.prepare_v2 ("SELECT n FROM t", -1, out st) == Sqlite.OK);
		assert (st.step () == Sqlite.ROW);

		var tx = db.begin_transaction ();
		tx.prepare ("INSERT INTO t VALUES (2)").execute ();
		bool failed = false;
		try {
			tx.commit ();
		} catch (SQLHeavy.Error e) {
			failed = true; // busy: the reader is still reading
		}
		assert (failed);
		st = null;
		assert (reader.exec ("COMMIT") == Sqlite.OK);

		assert (can_read (path)); // no lock left behind
		var next = db.begin_transaction (); // and the next transactions work
		next.prepare ("INSERT INTO t VALUES (3)").execute ();
		next.commit ();
		var r = new SQLHeavy.Query (db, "SELECT group_concat(n) FROM t").execute ();
		assert (r.fetch_string (0) == "1,3"); // the failed one rolled back, the next one saved
		r = null;
		next = null;
		tx = null;
		db = null;
		foreach (var suffix in new string[] { "", "-journal" })
			FileUtils.remove (path + suffix);
		DirUtils.remove (dir);
	} catch (Error e) {
		error ("%s", e.message);
	}
}

void main () {
	test_busy_timeout ();
	test_failed_commit ();
}
