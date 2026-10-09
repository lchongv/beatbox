// meson test: PeerSync, the merge rules shared with itunes7 (docs/SYNC-BEATBOX.md
// in itunes7, section 1.5): the same cases as its tests/test-beatbox-sync.c
using BeatBox;

PeerSync.Side plays (int64 count, int64 plays_in) {
	var s = new PeerSync.Side ();
	s.count = count;
	s.plays_in = plays_in;
	return s;
}

PeerSync.Side deleted () {
	var s = new PeerSync.Side ();
	s.mark_deleted ();
	return s;
}

PeerSync.Side rated (int64 cur, int64 agreed, int64 epoch) {
	var s = new PeerSync.Side ();
	s.f[PeerSync.RATING].cur = cur;
	s.f[PeerSync.RATING].agreed = agreed;
	s.f[PeerSync.RATING].epoch = epoch;
	return s;
}

// 'A' = itunes7 syncs looking at Beatbox, 'B' the other way
void run (PeerSync.Side a, PeerSync.Side b, string order) {
	int64 unused;
	for (int i = 0; i < order.length; i++) {
		if (order[i] == 'A')
			PeerSync.sync_side (a, b, true, out unused);
		else
			PeerSync.sync_side (b, a, false, out unused);
	}
}

// after each case, one more pass on each side changes nothing
void assert_quiet (PeerSync.Side a, PeerSync.Side b) {
	int64 unused;
	assert (!PeerSync.sync_side (a, b, true, out unused));
	assert (!PeerSync.sync_side (b, a, false, out unused));
}

void check_plays (int n, PeerSync.Side a, PeerSync.Side b, string order, int64 ac, int64 ai, int64 bc, int64 bi) {
	run (a, b, order);
	if (a.count != ac || a.plays_in != ai || b.count != bc || b.plays_in != bi)
		error ("case %d: A %s/%s B %s/%s", n, a.count.to_string (), a.plays_in.to_string (),
			b.count.to_string (), b.plays_in.to_string ());
	assert_quiet (a, b);
}

void check_rating (int n, PeerSync.Side a, PeerSync.Side b, string order, int64 want) {
	run (a, b, order);
	if (a.f[PeerSync.RATING].cur != want || b.f[PeerSync.RATING].cur != want)
		error ("case %d: A %s B %s, want %s", n, a.f[PeerSync.RATING].cur.to_string (),
			b.f[PeerSync.RATING].cur.to_string (), want.to_string ());
	assert_quiet (a, b);
}

void test_cases () {
	check_plays (1, plays (10, 0), plays (3, 0), "ABA", 13, 3, 13, 10);
	check_plays (2, plays (13, 3), plays (14, 10), "AB", 14, 4, 14, 10);
	check_plays (3, plays (15, 4), plays (14, 10), "BA", 15, 4, 15, 11);
	check_plays (4, deleted (), plays (15, 11), "BAB", 15, 15, 15, 0);
	check_plays (5, deleted (), plays (15, 11), "ABAB", 15, 15, 15, 0);
	check_rating (6, rated (3, 0, 0), rated (0, 0, 0), "BA", 3);
	check_rating (7, rated (4, 3, 1), rated (2, 3, 1), "BA", 4);
	check_rating (8, rated (1, 1, 2), rated (0, 0, 1), "AB", 0);
	check_rating (9, rated (1, 1, 1), rated (0, 0, 2), "AB", 1);

	// 10: a position without "remember position" is left alone
	var a = new PeerSync.Side ();
	var b = new PeerSync.Side ();
	b.f[PeerSync.RESUME_POS].cur = 120;
	run (a, b, "AB");
	assert (a.f[PeerSync.RESUME_POS].cur == 0 && b.f[PeerSync.RESUME_POS].cur == 120);
	assert_quiet (a, b);

	// 11: "remember position" turned on in itunes7: Beatbox hands over its position
	a = new PeerSync.Side ();
	b = new PeerSync.Side ();
	a.f[PeerSync.REMEMBER_POS].cur = 1;
	b.f[PeerSync.RESUME_POS].cur = 120;
	run (a, b, "ABA");
	assert (a.f[PeerSync.REMEMBER_POS].cur == 1 && b.f[PeerSync.REMEMBER_POS].cur == 1);
	assert (a.f[PeerSync.RESUME_POS].cur == 120 && b.f[PeerSync.RESUME_POS].cur == 120);
	assert_quiet (a, b);

	check_rating (12, rated (0, 0, -1), rated (4, 4, 2), "AB", 4);
	check_rating (13, rated (4, 4, 2), rated (0, 0, -1), "BA", 4);
	check_rating (14, rated (0, 0, -1), rated (1, 4, 2), "AB", 1);
	check_rating (15, rated (0, 0, 0), rated (2, 2, 1), "AB", 0);
	check_rating (16, rated (3, 0, -1), rated (0, 0, -1), "ABA", 3);
	check_plays (17, plays (2, 5), plays (10, 3), "ABAB", 10, 10, 10, 0);
	check_plays (18, plays (14, 3), plays (13, 11), "ABA", 14, 2, 14, 12);
	check_plays (19, plays (10, 3), plays (2, 5), "ABAB", 10, 0, 10, 10);
}

// last played is the max of the two sides, whichever passes first, and the
// value returned is what was really added
void test_last_played () {
	var a = new PeerSync.Side ();
	var b = new PeerSync.Side ();
	int64 np = -1;
	a.last = 100;
	a.count = 4;
	b.last = 200;
	b.count = 1;
	assert (PeerSync.sync_side (a, b, true, out np));
	assert (np == 1);
	assert (a.last == 200);
	assert (b.last == 200); // B has not passed yet
	assert (PeerSync.sync_side (b, a, false, out np));
	assert (np == 4);
	assert (a.last == 200);
	assert (b.last == 200);
	assert_quiet (a, b);

	// the other way round: A's is the most recent and B picks it up
	a = new PeerSync.Side ();
	b = new PeerSync.Side ();
	a.last = 300;
	b.last = 50;
	run (a, b, "BA");
	assert (a.last == 300);
	assert (b.last == 300);
	assert_quiet (a, b);
}

// merge_plays directly: returns what was added and never takes plays away
void test_merge_plays () {
	var s = plays (10, 3);
	assert (PeerSync.merge_plays (s, 2, 5) == 0); // floor at 0
	assert (s.count == 10);
	assert (s.plays_in == 0);

	s = plays (10, 0);
	assert (PeerSync.merge_plays (s, 14, 10) == 4);
	assert (s.count == 14);
	assert (s.plays_in == 4);
}

// The same property check as itunes7's test_properties (same seeds, same
// GRand sequence): plays on each side, changes to each field, deletions (with
// the trigger's effect) and passes in any order; two crossed passes at the end.
void test_properties () {
	for (uint32 seed = 0; seed < 100000; seed++) {
		var r = new Rand.with_seed (seed);
		var a = new PeerSync.Side ();
		var b = new PeerSync.Side ();
		int64 own_a = 0, own_b = 0, ever_a = 0, ever_b = 0;
		bool pend_a = false, pend_b = false, edited_a = false, edited_b = false;
		bool[] has_last = new bool[PeerSync.N_FIELDS];
		int64[] last_val = new int64[PeerSync.N_FIELDS];
		uint mode = seed % 3; // 0: both edit, 1: only A, 2: only B
		int steps = r.int_range (1, 51);
		int64 unused;

		for (int s = 0; s < steps; s++) {
			double e = r.next_double ();
			if (e < 0.20) {
				a.count++;
				own_a++;
				ever_a++;
			} else if (e < 0.35) {
				b.count++;
				own_b++;
				ever_b++;
			} else if (e < 0.50) {
				PeerSync.sync_side (a, b, true, out unused);
				pend_a = false;
			} else if (e < 0.65) {
				PeerSync.sync_side (b, a, false, out unused);
				pend_b = false;
			} else if (e < 0.82) {
				bool on_a = mode == 1 || (mode == 0 && r.boolean ());
				var who = on_a ? a : b;
				int k = r.int_range (0, PeerSync.N_FIELDS);
				int64 v = k == PeerSync.RATING        ? r.int_range (0, 6)
				        : k == PeerSync.VOLUME_ADJUST ? r.int_range (-100, 101)
				        : k == PeerSync.RESUME_POS    ? r.int_range (0, 601)
				        :                               r.int_range (0, 2);
				// accepted limit: a change between that side's delete and its next pass is lost;
				// the position too, while it stays marked
				bool exempt = (on_a ? pend_a : pend_b) ||
					(k == PeerSync.RESUME_POS && who.f[k].epoch < 0);
				who.f[k].cur = v;
				if (on_a)
					edited_a = true;
				else
					edited_b = true;
				has_last[k] = !exempt;
				last_val[k] = v;
			} else if (e < 0.84) {
				a.mark_deleted ();
				own_a = 0;
				pend_a = true;
				for (int k = 0; k < PeerSync.N_FIELDS; k++)
					has_last[k] = false;
			} else if (e < 0.86) {
				b.mark_deleted ();
				own_b = 0;
				pend_b = true;
				for (int k = 0; k < PeerSync.N_FIELDS; k++)
					has_last[k] = false;
			}
		}
		run (a, b, "ABAB");

		bool remember = a.f[PeerSync.REMEMBER_POS].cur == 1;
		assert (a.count == b.count); // they converge
		for (int k = 0; k < PeerSync.N_FIELDS; k++)
			if (k != PeerSync.RESUME_POS || remember)
				assert (a.f[k].cur == b.f[k].cur);
		assert (a.count >= own_a + own_b); // nothing is lost...
		assert (a.count <= ever_a + ever_b); // ...nor duplicated
		if (edited_a != edited_b) // a single editor: it wins
			for (int k = 0; k < PeerSync.N_FIELDS; k++)
				if (has_last[k] && (k != PeerSync.RESUME_POS || remember))
					assert (a.f[k].cur == last_val[k]);
		assert_quiet (a, b);
	}
}

int64 scalar (SQLHeavy.Database db, string sql) throws Error {
	var r = new SQLHeavy.Query (db, sql).execute ();
	return r.finished ? -999 : r.fetch_int64 (0);
}

// the sync table's triggers: the row follows a moved song and is marked when it is deleted
void test_triggers () {
	try {
		var dir = DirUtils.make_tmp ("bb-peersync-XXXXXX");
		var db = new SQLHeavy.Database (Path.build_filename (dir, "t.db"));
		db.execute ("CREATE TABLE songs ('uri' TEXT, 'playcount' INT);");
		db.execute (PeerSync.DDL);
		db.execute (PeerSync.DDL); // it runs at every start
		db.execute ("INSERT INTO songs VALUES ('file:///a.mp3', 9);" +
			"INSERT INTO itunes7_sync (uri, plays_in, rating, rating_ep) VALUES ('file:///a.mp3', 7, 3, 2);");
		db.execute ("UPDATE songs SET uri = 'file:///b.mp3' WHERE uri = 'file:///a.mp3'");
		assert (scalar (db, "SELECT plays_in FROM itunes7_sync WHERE uri = 'file:///b.mp3'") == 7);
		assert (scalar (db, "SELECT count(*) FROM itunes7_sync WHERE uri = 'file:///a.mp3'") == 0);
		db.execute ("UPDATE songs SET uri = uri"); // what every save does: no change
		assert (scalar (db, "SELECT plays_in FROM itunes7_sync WHERE uri = 'file:///b.mp3'") == 7);
		db.execute ("DELETE FROM songs WHERE uri = 'file:///b.mp3'");
		assert (scalar (db, "SELECT plays_in + rating FROM itunes7_sync WHERE uri = 'file:///b.mp3'") == 0);
		assert (scalar (db, "SELECT rating_ep + skip_shuffle_ep + remember_pos_ep + volume_adjust_ep + resume_pos_ep FROM itunes7_sync WHERE uri = 'file:///b.mp3'") == -5);
	} catch (Error e) {
		error ("%s", e.message);
	}
}

void main () {
	test_cases ();
	test_last_played ();
	test_merge_plays ();
	test_properties ();
	test_triggers ();
}
