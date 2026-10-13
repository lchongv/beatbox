// meson test: the options that belong to a library (ConfigSection) and Libraries, on a
// beatbox.conf in a temporary folder: never the real one. Without arguments it runs itself
// once per case: ConfigSection reads the file once per process.
using BeatBox;

const string CONF = """[settings]
library=%s
music-folder=/main
skin=classic

[library disco]
library-name=Disco
music-folder=/media/disco

[savedstate]
queue=1;2;
""";

/** beatbox.conf as written now */
KeyFile saved () {
	ConfigSection.flush ();
	var file = new KeyFile ();
	try {
		file.load_from_file (ConfigSection.config_path (), KeyFileFlags.NONE);
	} catch (Error e) {
		error ("%s", e.message);
	}
	return file;
}

string value_of (KeyFile file, string group, string key) {
	try {
		return file.get_string (group, key);
	} catch (Error e) {
		error ("%s/%s: %s", group, key, e.message);
	}
}

// The open library is "disco": its own options are read from and written to its group
void open_disco () {
	var settings = new BeatBox.Settings ();
	assert (settings.main.library == "disco");
	assert (settings.main.music_folder == "/media/disco");
	assert (settings.main.library_name == "Disco");
	assert (settings.main.skin == "classic");        // shared
	assert (settings.saved_state.queue.length == 0);  // the main library's queue is not disco's
	settings.main.music_folder = "/media/disco/music";
	settings.saved_state.queue = { "7" };
	var file = saved ();
	assert (value_of (file, "library disco", "music-folder") == "/media/disco/music");
	assert (value_of (file, "settings", "music-folder") == "/main");
	try {
		assert (file.get_string_list ("library disco", "queue")[0] == "7");
		assert (file.get_string_list ("savedstate", "queue").length == 2);
	} catch (Error e) {
		error ("%s", e.message);
	}
}

// A library missing from the file: the main one opens, and library= is cleared
void open_missing () {
	var settings = new BeatBox.Settings ();
	assert (settings.main.library == "");
	assert (settings.main.music_folder == "/main");
	assert (value_of (saved (), "settings", "library") == "");
}

// Libraries: ids from names, options, rename, remove
void manage () {
	assert (string.joinv (",", Libraries.ids ()) == "disco");
	assert (Libraries.create ("Música Clásica", "/srv/clasica") == "musica-clasica");
	assert (Libraries.create ("música clásica!", "/srv/otra") == "musica-clasica-2");
	assert (Libraries.create ("///", "/srv/x") == "library");
	assert (Libraries.option ("musica-clasica", "music-folder") == "/srv/clasica");
	assert (Libraries.option ("musica-clasica", "library-name") == "Música Clásica");
	assert (Libraries.option ("", "music-folder") == "/main");
	assert (Libraries.option ("disco", "no-such-key") == "");
	Libraries.rename ("musica-clasica", "Clásica");
	assert (Libraries.option ("musica-clasica", "library-name") == "Clásica");
	assert (Libraries.db_path ("").has_suffix ("/beatbox/beatbox.db"));
	var db = Libraries.db_path ("musica-clasica-2");
	assert (db.has_suffix ("/beatbox/libraries/musica-clasica-2.db"));
	DirUtils.create_with_parents (Path.get_dirname (db), 0755);
	try {
		FileUtils.set_contents (db, "");
	} catch (Error e) {
		error ("%s", e.message);
	}
	Libraries.remove ("musica-clasica-2");
	assert (!FileUtils.test (db, FileTest.EXISTS));
	assert (string.joinv (",", Libraries.ids ()) == "disco,musica-clasica,library");
	assert (!saved ().has_group ("library musica-clasica-2"));
}

int main (string[] args) {
	if (args.length == 1) { // the parent: one process per case
		foreach (var name in new string[] { "disco", "missing", "manage" }) {
			int status;
			try {
				Process.spawn_sync (null, { args[0], name }, null, 0, null, null, null, out status);
			} catch (SpawnError e) {
				error ("%s", e.message);
			}
			if (status != 0)
				error ("case %s failed", name);
		}
		return 0;
	}

	string dir;
	try {
		dir = DirUtils.make_tmp ("bb-libraries-XXXXXX");
	} catch (FileError e) {
		error ("%s", e.message);
	}
	// GLib keeps the folders it sees first: set them before anything reads them
	Environment.set_variable ("XDG_CONFIG_HOME", dir, true);
	Environment.set_variable ("XDG_DATA_HOME", dir, true);
	DirUtils.create_with_parents (Path.build_filename (dir, "beatbox"), 0755);
	try {
		FileUtils.set_contents (ConfigSection.config_path (), CONF.printf (args[1] == "missing" ? "gone" : "disco"));
	} catch (Error e) {
		error ("%s", e.message);
	}

	if (args[1] == "disco")
		open_disco ();
	else if (args[1] == "missing")
		open_missing ();
	else
		manage ();

	try {
		Process.spawn_command_line_sync ("rm -rf " + Shell.quote (dir));
	} catch (SpawnError e) {
		error ("%s", e.message);
	}
	return 0;
}
