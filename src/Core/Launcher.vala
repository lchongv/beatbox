/*
 * The desktop shell finds a window's icon and name through the launcher named
 * after the application id (net.launchpad.beatbox.desktop). Without a valid
 * one (not installed, or pointing to a program that is gone) the window gets a
 * generic icon. In that case BeatBox writes its own launcher in
 * ~/.local/share/applications, pointing to the executable that is running,
 * wherever it is, with the icon copied next to the library.
 */

namespace BeatBox.Launcher {
	const string ID = "net.launchpad.beatbox";
	const string GENERATED = "X-BeatBox-Generated"; // marks launchers written by this code

	/** Quoting as the desktop entry spec wants it: double quotes, and \ " ` $ escaped */
	string exec_quote (string path) {
		if (!Regex.match_simple ("[^A-Za-z0-9_./+-]", path))
			return path;
		var sb = new StringBuilder ("\"");
		unichar c;
		for (int i = 0; path.get_next_char (ref i, out c);) {
			if (c == '"' || c == '`' || c == '$' || c == '\\')
				sb.append_c ('\\');
			sb.append_unichar (c);
		}
		return sb.str + "\"";
	}

	public void ensure () {
		string exe;
		try {
			exe = FileUtils.read_link ("/proc/self/exe");
		} catch (FileError err) {
			return;
		}

		var installed = new DesktopAppInfo (ID + ".desktop");
		if (installed != null) {
			if (!installed.has_key (GENERATED))
				return; // provided by an installation: leave it alone
			if (installed.get_string ("TryExec") == exe)
				return; // ours, and up to date
		}

		try {
			// The icon, as a file the shell can read
			var icon = Path.build_filename (Environment.get_user_data_dir (), "beatbox", "beatbox.svg");
			DirUtils.create_with_parents (Path.get_dirname (icon), 0755);
			var svg = resources_lookup_data ("/net/launchpad/beatbox/icons/128x128/apps/beatbox.svg", ResourceLookupFlags.NONE);
			FileUtils.set_data (icon, svg.get_data ());

			// The launcher shipped with BeatBox, with Exec and Icon pointing here
			var entry = new KeyFile ();
			var desktop = resources_lookup_data ("/net/launchpad/beatbox/beatbox.desktop", ResourceLookupFlags.NONE);
			entry.load_from_bytes (desktop, KeyFileFlags.KEEP_TRANSLATIONS);
			entry.set_string ("Desktop Entry", "Exec", exec_quote (exe) + " %U");
			entry.set_string ("Desktop Entry", "TryExec", exe);
			entry.set_string ("Desktop Entry", "Icon", icon);
			entry.set_boolean ("Desktop Entry", GENERATED, true);

			var dir = Path.build_filename (Environment.get_user_data_dir (), "applications");
			DirUtils.create_with_parents (dir, 0755);
			FileUtils.set_contents (Path.build_filename (dir, ID + ".desktop"), entry.to_data ());
			message ("Registered the launcher for %s", exe);
		} catch (Error err) {
			warning ("Could not register the launcher: %s", err.message);
		}
	}
}
