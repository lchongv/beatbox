/* The recorder that keeps streamripper running: its command line, relaunching, backing off and stopping.
 * The program is a script that logs its arguments and process id, and sleeps. */
string dir;
string log_path;
string pid_path;

void pump (uint ms) {
	var loop = new MainLoop ();
	Timeout.add (ms, () => { loop.quit (); return false; });
	loop.run ();
}

string[] lines (string path) {
	string text = "";
	try {
		FileUtils.get_contents (path, out text);
	} catch (Error err) {}
	return text.strip () == "" ? new string[0] : text.strip ().split ("\n");
}

bool alive (string pid) {
	return FileUtils.test ("/proc/" + pid, FileTest.EXISTS);
}

void reset_logs () {
	FileUtils.unlink (log_path);
	FileUtils.unlink (pid_path);
}

BeatBox.StreamRecorder fake_recorder (string program) {
	var recorder = new BeatBox.StreamRecorder ();
	recorder.program = program;
	return recorder;
}

void main () {
	try {
		dir = DirUtils.make_tmp ("recorderXXXXXX");
		log_path = Path.build_filename (dir, "args.log");
		pid_path = Path.build_filename (dir, "pids.log");
		string script = Path.build_filename (dir, "streamripper");
		// "long" in the address: runs until stopped; "stubborn": ignores SIGINT too; otherwise ends in 0.3 s
		FileUtils.set_contents (script, "#!/bin/sh\necho \"$@\" >> %s\necho $$ >> %s\ncase \"$1\" in\n*stubborn*) trap '' INT; exec sleep 30;;\n*long*) exec sleep 30;;\n*) exec sleep 0.3;;\nesac\n".printf (log_path, pid_path));
		FileUtils.chmod (script, 0755);

		// the pauses between launches: 0.1 s after a good run, then 1, 2, 4... up to a minute
		assert (BeatBox.StreamRecorder.retry_delay_ms (0) == 100);
		assert (BeatBox.StreamRecorder.retry_delay_ms (1) == 1000);
		assert (BeatBox.StreamRecorder.retry_delay_ms (2) == 2000);
		assert (BeatBox.StreamRecorder.retry_delay_ms (3) == 4000);
		assert (BeatBox.StreamRecorder.retry_delay_ms (7) == 60000);
		assert (BeatBox.StreamRecorder.retry_delay_ms (500) == 60000);

		// a station's name as a folder name
		assert (BeatBox.StreamRecorder.safe_name ("Radio BioBio Santiago") == "Radio BioBio Santiago");
		assert (BeatBox.StreamRecorder.safe_name ("AC/DC FM") == "AC_DC FM");
		assert (BeatBox.StreamRecorder.safe_name ("  ..hidden ") == "__hidden");
		assert (BeatBox.StreamRecorder.safe_name ("") == "station");
		assert (BeatBox.StreamRecorder.safe_name (" / ") == "_");

		// the command: the address twice, as the user agent too (some servers refuse streamripper's own)
		var recorder = fake_recorder (script);
		string folder = Path.build_filename (dir, "rips", "Radio long");
		string url = "http://example.org/long/stream";
		var changes = new string[0];
		recorder.changed.connect ((u) => { changes += u; });
		assert (!recorder.is_recording (url));
		assert (recorder.start (url, folder, 3600));
		assert (recorder.is_recording (url));
		assert (FileUtils.test (folder, FileTest.IS_DIR));
		assert (recorder.start (url, folder, 3600)); // already recording: no second process
		pump (500);
		assert (lines (log_path).length == 1);
		assert (lines (log_path)[0] == "%s -u %s -a -l 3600 -d %s -s --quiet".printf (url, url, folder));
		string pid = lines (pid_path)[0];
		assert (alive (pid));
		assert (changes.length == 1 && changes[0] == url);

		// stopping ends it for good
		recorder.stop (url);
		assert (!recorder.is_recording (url));
		pump (600);
		assert (!alive (pid));
		assert (lines (log_path).length == 1);
		assert (changes.length == 2);
		recorder.stop (url); // nothing to stop: no signal
		assert (changes.length == 2);

		// it ends by itself (the chunk is over): launched again at once
		reset_logs ();
		recorder = fake_recorder (script);
		recorder.healthy_ms = 0;
		assert (recorder.start ("http://example.org/short", folder, 60));
		pump (1500);
		assert (lines (log_path).length >= 3);
		recorder.stop_all ();
		pump (500);
		int launched = lines (log_path).length;
		pump (600);
		assert (lines (log_path).length == launched);

		// ...but one that fails at once waits longer each time: 0.3 s run, 1 s, 0.3 s run, 2 s...
		reset_logs ();
		recorder = fake_recorder (script);
		assert (recorder.start ("http://example.org/short", folder, 60));
		pump (2000);
		assert (lines (log_path).length == 2);
		recorder.stop_all ();

		// stop_all ends them all, and a stubborn one is killed after kill_after_ms
		reset_logs ();
		recorder = fake_recorder (script);
		recorder.kill_after_ms = 300;
		assert (recorder.start ("http://example.org/long/a", folder, 60));
		assert (recorder.start ("http://example.org/stubborn/b", folder, 60));
		pump (500);
		var pids = lines (pid_path);
		assert (pids.length == 2 && alive (pids[0]) && alive (pids[1]));
		recorder.stop_all ();
		assert (!recorder.is_recording ("http://example.org/long/a") && !recorder.is_recording ("http://example.org/stubborn/b"));
		pump (900);
		assert (!alive (pids[0]) && !alive (pids[1]));

		// no program, no recording
		recorder = fake_recorder ("/nonexistent/streamripper");
		assert (!recorder.available ());
		assert (!recorder.start ("http://example.org/short", folder, 60));
		assert (!recorder.is_recording ("http://example.org/short"));
	} catch (Error err) {
		error ("%s", err.message);
	}
}
