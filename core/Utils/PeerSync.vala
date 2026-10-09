/*
 * The merge rules for the live sync with itunes7. The agreement between the
 * two apps (tables, units, rules and test cases) is docs/SYNC-BEATBOX.md in
 * itunes7, which implements the same rules in C (src/it7-beatbox-sync.c):
 * change one, change both, add the case to the table and run both tests.
 */
namespace BeatBox.PeerSync {
	// The data merged with "agreed value + epoch", in the order of the table's columns
	public const int RATING = 0;        // stars 0-5
	public const int SKIP_SHUFFLE = 1;  // 0/1
	public const int REMEMBER_POS = 2;  // 0/1
	public const int VOLUME_ADJUST = 3; // -100..100
	public const int RESUME_POS = 4;    // seconds
	public const int N_FIELDS = 5;

	/** The sync table and its two triggers over 'songs' */
	public const string DDL = """
CREATE TABLE IF NOT EXISTS itunes7_sync (
	uri TEXT PRIMARY KEY,
	plays_in INTEGER NOT NULL DEFAULT 0,
	rating INTEGER NOT NULL DEFAULT 0, rating_ep INTEGER NOT NULL DEFAULT 0,
	skip_shuffle INTEGER NOT NULL DEFAULT 0, skip_shuffle_ep INTEGER NOT NULL DEFAULT 0,
	remember_pos INTEGER NOT NULL DEFAULT 0, remember_pos_ep INTEGER NOT NULL DEFAULT 0,
	volume_adjust INTEGER NOT NULL DEFAULT 0, volume_adjust_ep INTEGER NOT NULL DEFAULT 0,
	resume_pos INTEGER NOT NULL DEFAULT 0, resume_pos_ep INTEGER NOT NULL DEFAULT 0
);
CREATE TRIGGER IF NOT EXISTS itunes7_sync_del AFTER DELETE ON songs BEGIN
	INSERT OR REPLACE INTO itunes7_sync (uri, rating_ep, skip_shuffle_ep, remember_pos_ep, volume_adjust_ep, resume_pos_ep)
	VALUES (OLD.uri, -1, -1, -1, -1, -1);
END;
CREATE TRIGGER IF NOT EXISTS itunes7_sync_mv AFTER UPDATE OF uri ON songs WHEN OLD.uri <> NEW.uri BEGIN
	UPDATE OR REPLACE itunes7_sync SET uri = NEW.uri WHERE uri = OLD.uri;
END;
""";

	public class Field {
		public int64 cur;    // the value in this app
		public int64 agreed; // the last value both apps had
		public int64 epoch;  // the order of that agreement; -1 = the song was added again
	}

	/** A song as one app sees it, which is what the other app reads */
	public class Side {
		public int64 count;    // plays
		public int64 last;     // last played, Unix seconds
		public int64 plays_in; // the other app's plays already added here
		public Field[] f;

		public Side () {
			f = new Field[N_FIELDS];
			for (int i = 0; i < N_FIELDS; i++)
				f[i] = new Field ();
		}

		public Side copy () {
			var s = new Side ();
			s.count = count;
			s.last = last;
			s.plays_in = plays_in;
			for (int i = 0; i < N_FIELDS; i++) {
				s.f[i].cur = f[i].cur;
				s.f[i].agreed = f[i].agreed;
				s.f[i].epoch = f[i].epoch;
			}
			return s;
		}

		public bool same_as (Side o) {
			if (count != o.count || last != o.last || plays_in != o.plays_in)
				return false;
			for (int i = 0; i < N_FIELDS; i++)
				if (f[i].cur != o.f[i].cur || f[i].agreed != o.f[i].agreed || f[i].epoch != o.f[i].epoch)
					return false;
			return true;
		}

		/** What the delete trigger leaves */
		public void mark_deleted () {
			count = 0;
			last = 0;
			plays_in = 0;
			for (int i = 0; i < N_FIELDS; i++) {
				f[i].cur = 0;
				f[i].agreed = 0;
				f[i].epoch = -1;
			}
		}
	}

	/** Plays: returns how many new ones were added. Plays are never taken away */
	public int64 merge_plays (Side me, int64 peer_count, int64 peer_plays_in) {
		if (me.count < me.plays_in)
			me.plays_in = me.count; // safety net: the total went down some other way
		int64 peer_own = peer_count - peer_plays_in;
		if (peer_own < 0)
			peer_own = 0;
		int64 d = peer_own - me.plays_in;
		if (d > 0)
			me.count += d;
		me.plays_in = peer_own; // also when d < 0: what the other lost stays here and goes back
		return d > 0 ? d : 0;
	}

	/** The value both apps must end with: ALWAYS itunes7's data first (a, ba, ea) */
	public int64 decide (int64 a, int64 ba, int64 ea, int64 b, int64 bb, int64 eb) {
		if (a == b)
			return a;
		if (ea < 0 && eb >= 0)
			return b; // itunes7 added it again: it gets Beatbox's
		if (eb < 0 && ea >= 0)
			return a; // Beatbox added it again: it gets itunes7's
		int64 reference = ea >= eb ? ba : bb; // the latest agreement (a tie: itunes7's)
		return a == reference ? b : a;        // only Beatbox changed: b; otherwise itunes7 wins
	}

	public void apply (Field mine, int64 r, int64 peer_cur, int64 peer_epoch) {
		mine.cur = r; // adopt (or keep, when r is ours)
		if (mine.cur == peer_cur && (mine.agreed != mine.cur || mine.epoch < 0)) {
			mine.agreed = mine.cur; // a new agreement
			int64 e = mine.epoch > peer_epoch ? mine.epoch : peer_epoch;
			mine.epoch = (e > 0 ? e : 0) + 1;
		}
		else if (mine.epoch < 0) {
			mine.epoch = 0; // the "added again" mark only counts for the first decision
		}
	}

	public int64 decide_field (Side a, Side b, int i) {
		return decide (a.f[i].cur, a.f[i].agreed, a.f[i].epoch, b.f[i].cur, b.f[i].agreed, b.f[i].epoch);
	}

	/** All the rules for one song, from `me` looking at `peer`; true if `me` changed */
	public bool sync_side (Side me, Side peer, bool me_is_itunes7, out int64 new_plays) {
		var before = me.copy ();
		new_plays = merge_plays (me, peer.count, peer.plays_in);
		if (peer.last > me.last)
			me.last = peer.last;
		Side a = me_is_itunes7 ? me : peer;
		Side b = me_is_itunes7 ? peer : me;
		// the position only counts when "remember position" (decided first, the same in both apps) is 1
		int64 remember = decide_field (a, b, REMEMBER_POS);
		for (int i = 0; i < N_FIELDS; i++) {
			if (i == RESUME_POS && remember != 1)
				continue;
			apply (me.f[i], decide_field (a, b, i), peer.f[i].cur, peer.f[i].epoch);
		}
		return !me.same_as (before);
	}
}
