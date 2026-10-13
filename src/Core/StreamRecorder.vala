/*
 * Records radio stations with streamripper (an optional program), the way a shell loop would:
 *   while true; do streamripper URL -u URL -a -l SECONDS -d FOLDER -s; sleep .1; done
 * One file per run of SECONDS (with its .cue), and the next run starts when it ends. Each station
 * has its own process, apart from the playback. A process that dies at once (a dead stream, an
 * address that refuses) is launched again after 1, 2, 4... up to 60 seconds, so it doesn't spin.
 * Without GTK or App: tests/stream-recorder.vala runs it with a script in place of streamripper.
 */
public class BeatBox.StreamRecorder : Object {
	class Entry {
		public string folder;
		public int seconds;
		public Subprocess? process = null;
		public int64 started = 0;   // ms, monotonic
		public int quick_failures = 0;
		public uint retry = 0;      // the pause before the next launch
	}

	static StreamRecorder? instance = null;

	public string program = "streamripper";
	/** A run at least this long was a good one: the next launch doesn't wait */
	public int healthy_ms = 30000;
	/** How long a process gets to close its file after SIGINT before it is killed */
	public int kill_after_ms = 5000;

	Gee.HashMap<string, Entry> active = new Gee.HashMap<string, Entry> (); // by stream address

	/** A station started or stopped being recorded (emitted in the main loop) */
	public signal void changed (string uri);

	public static StreamRecorder get_default () {
		if (instance == null)
			instance = new StreamRecorder ();
		return instance;
	}

	public bool available () {
		return Environment.find_program_in_path (program) != null;
	}

	public bool is_recording (string uri) {
		return active.has_key (uri);
	}

	/** Starts recording uri into folder (made if missing), seconds per file. false when streamripper can't start; true too when it already was recording */
	public bool start (string uri, string folder, int seconds) {
		if (is_recording (uri))
			return true;
		if (DirUtils.create_with_parents (folder, 0755) != 0) {
			warning ("Could not create the recordings folder %s", folder);
			return false;
		}
		var entry = new Entry () { folder = folder, seconds = seconds };
		if (!launch (uri, entry))
			return false;
		active[uri] = entry;
		changed (uri);
		return true;
	}

	/** Ends the recording: streamripper closes its file on SIGINT, and is killed if it doesn't within kill_after_ms */
	public void stop (string uri) {
		Entry? entry;
		if (!active.unset (uri, out entry))
			return;
		if (entry.retry != 0)
			Source.remove (entry.retry);
		var process = entry.process;
		if (process != null && process.get_identifier () != null) {
			process.send_signal (ProcessSignal.INT);
			Timeout.add (kill_after_ms, () => {
				process.force_exit (); // nothing when it has gone already
				return Source.REMOVE;
			});
		}
		changed (uri);
	}

	public void stop_all () {
		foreach (var uri in active.keys.to_array ())
			stop (uri);
	}

	bool launch (string uri, Entry entry) {
		try {
			// -u: some servers refuse streamripper's own user agent
			entry.process = new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
				program, uri, "-u", uri, "-a", "-l", entry.seconds.to_string (), "-d", entry.folder, "-s", "--quiet", null);
		} catch (Error err) {
			warning ("Could not start %s: %s", program, err.message);
			return false;
		}
		entry.started = get_monotonic_time () / 1000;
		var process = entry.process;
		process.wait_async.begin (null, (obj, res) => {
			try {
				process.wait_async.end (res);
			} catch (Error err) {}
			if (active[uri] == entry && entry.process == process)
				ended (uri, entry);
		});
		return true;
	}

	void ended (string uri, Entry entry) {
		if (get_monotonic_time () / 1000 - entry.started >= healthy_ms)
			entry.quick_failures = 0;
		else
			entry.quick_failures++;
		entry.retry = Timeout.add (retry_delay_ms (entry.quick_failures), () => {
			entry.retry = 0;
			if (active[uri] == entry && !launch (uri, entry)) {
				active.unset (uri);
				changed (uri);
			}
			return Source.REMOVE;
		});
	}

	/** The pause before launching again, by how many runs in a row ended quickly: 0.1 s after a good run, then 1, 2, 4... up to 60 s */
	public static int retry_delay_ms (int quick_failures) {
		if (quick_failures <= 0)
			return 100;
		return int.min (1000 << int.min (quick_failures - 1, 6), 60000);
	}

	/** A station's name as a folder name: no slashes, not hidden, never empty */
	public static string safe_name (string title) {
		var sb = new StringBuilder ();
		unichar c;
		for (int i = 0; title.strip ().get_next_char (ref i, out c);)
			sb.append_unichar ((c == '/' || c.iscntrl ()) ? '_' : c);
		string name = sb.str;
		int dots = 0;
		while (dots < name.length && name[dots] == '.')
			dots++;
		name = string.nfill (dots, '_') + name.substring (dots);
		return (name.strip () == "") ? "station" : name;
	}
}
