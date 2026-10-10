/*
 * The part of ItunesSync's pass that needs no running BeatBox, in a file of its
 * own so tests/itunes-sync-pass.vala can run it: which songs change (changes)
 * and how they are written (save). The agreement is docs/SYNC-BEATBOX.md in
 * itunes7; the rules themselves are PeerSync (core/Utils/PeerSync.vala).
 */
namespace BeatBox.ItunesSyncPass {
	// This app's rating and position as both apps compare them, which is what
	// itunes7 reads of them (docs/SYNC-BEATBOX.md section 1.2): stars 0-5 (an
	// iPod import can leave more than 5) and seconds >= 0
	int64 stars (Media m) {
		return m.rating > 5 ? 5 : m.rating;
	}

	int64 seconds (Media m) {
		return m.resume_pos < 0 ? 0 : m.resume_pos;
	}

	/** A song whose values or sync row the pass changes */
	public class Change : Object {
		public Media media;
		public string uri;
		public PeerSync.Side side; // after the rules: what the sync row gets
		// what the song gets: written with its sync row, then put in memory
		public uint play_count;
		public uint last_played;
		public uint rating;
		public bool skip_shuffle;
		public bool remember_position;
		public int volume_adjust;
		public int resume_pos;
		public bool song_changed; // the song itself changes, not just its sync row

		public Change (Media media, PeerSync.Side side) {
			this.media = media;
			this.uri = media.uri;
			this.side = side;
			play_count = (uint) side.count;
			last_played = (uint) side.last;
			// out of range, they are only rewritten when the other app's value is
			// adopted, like a half star in itunes7
			rating = side.f[PeerSync.RATING].cur != stars (media) ? (uint) side.f[PeerSync.RATING].cur : media.rating;
			skip_shuffle = side.f[PeerSync.SKIP_SHUFFLE].cur != 0;
			remember_position = side.f[PeerSync.REMEMBER_POS].cur != 0;
			volume_adjust = (int) side.f[PeerSync.VOLUME_ADJUST].cur;
			resume_pos = side.f[PeerSync.RESUME_POS].cur != seconds (media) ? (int) side.f[PeerSync.RESUME_POS].cur : media.resume_pos;
			song_changed = media.play_count != play_count || media.last_played != last_played
				|| media.rating != rating || media.skip_shuffle != skip_shuffle
				|| media.remember_position != remember_position
				|| media.volume_adjust != volume_adjust || media.resume_pos != resume_pos;
		}

		public void apply () {
			media.play_count = play_count;
			media.last_played = last_played;
			media.rating = rating;
			media.skip_shuffle = skip_shuffle;
			media.remember_position = remember_position;
			media.volume_adjust = volume_adjust;
			media.resume_pos = resume_pos;
		}
	}

	/** The songs the pass changes: this app's songs against itunes7's (theirs,
	 * from ItunesReader) and this app's sync rows (mine), both by URI */
	public Gee.ArrayList<Change> changes (Gee.Collection<Media> songs, Gee.Map<string, PeerSync.Side> theirs,
			Gee.Map<string, PeerSync.Side> mine) {
		var list = new Gee.ArrayList<Change> ();
		foreach (var m in songs) {
			if (m.uri == "")
				continue;
			var peer = theirs[m.uri];
			if (peer == null)
				continue;
			var me = mine[m.uri] ?? new PeerSync.Side ();
			me.count = m.play_count;
			me.last = m.last_played;
			me.f[PeerSync.RATING].cur = stars (m);
			me.f[PeerSync.SKIP_SHUFFLE].cur = m.skip_shuffle ? 1 : 0;
			me.f[PeerSync.REMEMBER_POS].cur = m.remember_position ? 1 : 0;
			me.f[PeerSync.VOLUME_ADJUST].cur = m.volume_adjust;
			me.f[PeerSync.RESUME_POS].cur = seconds (m);
			int64 added;
			if (PeerSync.sync_side (me, peer, false, out added))
				list.add (new Change (m, me));
		}
		return list;
	}

	/**
	 * Writes the sync rows and the songs that change in ONE transaction and,
	 * only once it is committed, puts the songs' new values in memory. Returns
	 * the songs changed in memory, or null when nothing was committed (the next
	 * change retries).
	 *
	 * One transaction because itunes7 reads beatbox.db while BeatBox runs: a sync
	 * row it saw without its song (plays_in already counting a play the song
	 * doesn't have yet) would make it count that play twice. And memory only
	 * after the commit, because BeatBox saves songs from memory: values that
	 * never reached the database would be saved later without their sync rows.
	 */
	public Gee.ArrayList<Media>? save (DatabaseInterface db, Gee.ArrayList<Change> changes) {
		var filler = new DatabaseTransactionFiller ();
		filler.data = changes;
		filler.filler = save_filler;
		db.queue_transaction (filler); // runs now: no transaction is open outside a filler
		if (!filler.committed)
			return null;
		var changed = new Gee.ArrayList<Media> ();
		foreach (var c in changes) {
			if (c.song_changed) {
				c.apply ();
				changed.add (c.media);
			}
		}
		return changed;
	}

	void save_filler (ref SQLHeavy.Transaction transaction, DatabaseTransactionFiller db_filler) {
		var changes = (Gee.ArrayList<Change>) db_filler.data;
		string[] fields = { "rating", "skip_shuffle", "remember_pos", "volume_adjust", "resume_pos" };
		try {
			var row = transaction.prepare ("INSERT OR REPLACE INTO itunes7_sync (uri, %s) VALUES (:uri, :plays_in, :rating, :rating_ep, :skip_shuffle, :skip_shuffle_ep, :remember_pos, :remember_pos_ep, :volume_adjust, :volume_adjust_ep, :resume_pos, :resume_pos_ep)".printf (ItunesReader.SYNC_COLUMNS));
			var song = transaction.prepare ("UPDATE songs SET playcount=:playcount, lastplayed=:lastplayed, rating=:rating, skip_shuffle=:skip_shuffle, remember_position=:remember_position, volume_adjust=:volume_adjust, resume_pos=:resume_pos WHERE rowid=:rowid");
			foreach (var c in changes) {
				row.set_string (":uri", c.uri);
				row.set_int64 (":plays_in", c.side.plays_in);
				for (int i = 0; i < PeerSync.N_FIELDS; i++) {
					row.set_int64 (":" + fields[i], c.side.f[i].agreed);
					row.set_int64 (":" + fields[i] + "_ep", c.side.f[i].epoch);
				}
				row.execute ();
				if (!c.song_changed || c.media.rowid <= 0)
					continue;
				// the same values as SongLibrary's update, which writes them again afterwards
				song.set_int (":rowid", c.media.rowid);
				song.set_int (":playcount", (int) c.play_count);
				song.set_int (":lastplayed", (int) c.last_played);
				song.set_int (":rating", (int) c.rating);
				song.set_int (":skip_shuffle", c.skip_shuffle ? 1 : 0);
				song.set_int (":remember_position", c.remember_position ? 1 : 0);
				song.set_int (":volume_adjust", c.volume_adjust);
				song.set_int (":resume_pos", c.resume_pos);
				song.execute ();
			}
		}
		catch (SQLHeavy.Error err) {
			warning ("itunes7 sync: could not save: %s", err.message);
			// all or nothing: what was written already would be committed without the rest
			transaction.rollback ();
		}
	}
}
