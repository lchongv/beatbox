/*
 * The log format BeatBox always had, "[WARNING 12:34:56.123456] File.vala:12: text" in colour.
 * Adapted from Granite's Logger (granite 6.2.0, LGPL-3.0-or-later; Copyright 2011-2019 elementary, Inc.).
 */

namespace BeatBox.Logger {
	const string[] NAMES = { "DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL" };
	const string[] COLORS = { "92", "94", "93", "91", "101m\x1b[97" }; // CRITICAL: white on red

	bool show_debug;
	Mutex mutex;

	/** Debug messages show with G_MESSAGES_DEBUG set (any value) */
	public void initialize () {
		show_debug = Environment.get_variable ("G_MESSAGES_DEBUG") != null;
		Log.set_default_handler (write);
	}

	void write (string? domain, LogLevelFlags flags, string message) {
		int level;
		switch (flags & LogLevelFlags.LEVEL_MASK) {
			case LogLevelFlags.LEVEL_DEBUG:
				level = 0;
				break;
			case LogLevelFlags.LEVEL_INFO:
			case LogLevelFlags.LEVEL_MESSAGE:
				level = 1;
				break;
			case LogLevelFlags.LEVEL_ERROR:
				level = 3;
				break;
			case LogLevelFlags.LEVEL_CRITICAL:
				level = 4;
				break;
			default:
				level = 2;
				break;
		}
		if (level == 0 && !show_debug)
			return;

		var time = new DateTime.now_local ().format ("%H:%M:%S.%f");
		var text = message.replace ("\n", "").replace ("\r", "");
		mutex.lock ();
		stdout.printf ("\x1b[%sm[%s %s]\x1b[0m %s%s\n", COLORS[level], NAMES[level], time,
		               domain != null ? "[%s] ".printf (domain) : "", text);
		mutex.unlock ();
	}
}
