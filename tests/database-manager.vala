// meson test: DataBaseManager (src/DataBase/DataBaseManager.vala), on a library
// in a temporary data folder: never the real one
using BeatBox;

// struct rlimit is { rlim_cur, rlim_max }, two 64-bit numbers
[CCode (cname = "getrlimit", cheader_filename = "sys/resource.h")]
extern int getrlimit (int resource, void* rlim);
[CCode (cname = "setrlimit", cheader_filename = "sys/resource.h")]
extern int setrlimit (int resource, void* rlim);
[CCode (cname = "RLIMIT_FSIZE", cheader_filename = "sys/resource.h")]
extern const int RLIMIT_FSIZE;

// The copy before the first sync with itunes7, when VACUUM INTO fails halfway
// (here: the file size limit, as with a full disk). A half copy left behind
// would pass for the copy at the next start, and the sync would run without one
void test_backup_failure (DataBaseManager db, string dir) {
	var backup = Path.build_filename (dir, "beatbox.db.pre-sync");
	Posix.signal (Posix.Signal.XFSZ, Posix.SIG_IGN); // a write past the limit fails instead of killing us
	uint64 old[2];
	assert (getrlimit (RLIMIT_FSIZE, old) == 0);
	uint64 low[2] = { 4096, old[1] }; // the library takes several pages
	assert (setrlimit (RLIMIT_FSIZE, low) == 0);
	bool copied = db.backup_to (backup);
	assert (setrlimit (RLIMIT_FSIZE, old) == 0);
	assert (!copied);
	if (FileUtils.test (backup, FileTest.EXISTS))
		error ("a half copy was left at %s", backup);

	assert (db.backup_to (backup)); // with room, a real copy
	assert (FileUtils.test (backup, FileTest.EXISTS));
	assert (!db.backup_to (backup)); // one already there is refused, and kept
	assert (FileUtils.test (backup, FileTest.EXISTS));
	FileUtils.remove (backup);
}

void insert_then_lose_it (ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller filler) {
	try {
		transaction.prepare ("INSERT INTO itunes7_sync (uri, plays_in) VALUES ('file:///a.ogg', 5)").execute ();
		// what SQLite itself does when a statement fails with SQLITE_FULL, IOERR
		// or NOMEM: the whole transaction is rolled back, and the COMMIT fails
		transaction.prepare ("ROLLBACK").execute ();
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}
}

void insert (ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller filler) {
	try {
		transaction.prepare ("INSERT INTO itunes7_sync (uri, plays_in) VALUES ('file:///b.ogg', 7)").execute ();
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}
}

// ItunesSync changes a song only once its sync row is committed: a filler must
// say whether its transaction was, beyond its statements having run
void test_committed (DataBaseManager db) {
	var lost = new DatabaseTransactionFiller ();
	lost.filler = insert_then_lose_it;
	db.queue_transaction (lost);
	if (lost.committed)
		error ("a transaction rolled back reads as committed");

	var saved = new DatabaseTransactionFiller ();
	saved.filler = insert;
	db.queue_transaction (saved);
	assert (saved.committed);
	try {
		assert (db.execute ("SELECT group_concat(uri) FROM itunes7_sync").fetch_string (0) == "file:///b.ogg");
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}
}

void main () {
	string dir;
	try {
		dir = DirUtils.make_tmp ("bb-dbmanager-XXXXXX");
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
	test_backup_failure (db, library_dir);
	test_committed (db);

	db = null;
	foreach (var name in new string[] { "beatbox.db", "beatbox.db-journal" })
		FileUtils.remove (Path.build_filename (library_dir, name));
	DirUtils.remove (library_dir);
	DirUtils.remove (dir);
}
