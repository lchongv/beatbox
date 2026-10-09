// meson test: the database waits up to 2 s while another process holds it,
// instead of failing with SQLITE_BUSY and losing the write (itunes7 reads it live)
void main () {
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
