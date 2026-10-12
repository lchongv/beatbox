# Several Music Libraries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate music libraries (own folder, songs, ratings, play counts, playlists), switched from the app menu by restarting BeatBox, with radio and podcasts shared from the main database.

**Architecture:** The main library stays exactly as it is (`beatbox.db`, `[settings]`). Each other library gets a `[library <id>]` group in `beatbox.conf` for the few options that belong to a library (ConfigSection routes them) and its own database `libraries/<id>.db`, with `beatbox.db` attached as `shared` for the `stations` and `podcasts` tables. Switching writes `[settings] library=<id>`, quits the normal way and re-executes the program.

**Tech Stack:** Vala, GTK 3, GLib/GIO (KeyFile, GMenu, GAction), SQLite through the SQLHeavy shim (`core/SQLHeavy.vala`), meson; tests in Vala (`tests/*.vala`, `meson test`) and Python (`tests/smoke.py`, Xvfb + MPRIS).

**Spec:** `docs/superpowers/specs/2026-10-11-multiple-libraries-design.md`

## Global Constraints

- The main library's files and keys do not move: `~/.local/share/beatbox/beatbox.db` and the `[settings]` / `[savedstate]` groups of `~/.config/beatbox/beatbox.conf`. No migration.
- Options that belong to a library: `library-name`, `music-folder`, `music-mount-name`, `watch-music-folder`, `last-media-playing`, `last-media-position` (group `settings`) and `queue` (group `savedstate`). Everything else stays shared.
- New `[settings]` keys: `library` (open library's id, empty = main), `library-name` (main's name, empty shows "Music"), `last-rowid` (highest media id given in any library).
- Other libraries: group `[library <id>]`, database `~/.local/share/beatbox/libraries/<id>.db`; ids are lowercase ASCII letters, digits and dashes made from the name, `-2`, `-3`… when taken.
- itunes7 sync only while the main library is open.
- UI strings in English inside `_()`, Spanish added by hand to `po/es.po`. No "iTunes" wording in anything user-facing (itunes7 is the name of the user's own app and is fine).
- Commits: the repository's local git config already has the author (`lchongv <lchongv+beatbox@gmail.com>`); never pass another one. The local pre-commit hook rewrites the version in `meson.build` on every commit: do not edit it by hand. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests never touch the user's real `~/.config/beatbox`, `~/.local/share/beatbox` or music: temporary folders, `XDG_*` variables, and for the app a private Xvfb + `dbus-run-session` with `unset WAYLAND_DISPLAY; export GDK_BACKEND=x11`.
- Work on a branch `libraries` made from `master`; it is merged (fast-forward) only when the user says so. Do not install (`ninja -C build install`) during the tasks.

## Review Focus

1. A library name with accents, symbols only, or the same as another one ("Música Clásica", "///", "música clásica!") must give a safe, unique id, and the name shown stays as typed. → Task 1 test `manage`.
2. Another library opened when the main `beatbox.db` does not exist yet must create it and still have radio and podcasts. → Task 2 test `test_library`.
3. `beatbox.conf` naming a library that is gone (`library=gone`) must open the main library, clear `library=` and create no database. → Task 1 test `open_missing` and Task 3 smoke phase 5.
4. Switching to another library and back must give each library back its own last song, position and queue. → Task 4 GUI check, step "switch back and forth".
5. Choosing another library while an import runs must be refused with a message, leaving the open library as it was. → Task 4 GUI check, step "switch during an import".

---

### Task 1: Options that belong to a library, and the list of libraries

**Files:**
- Modify: `core/Settings.vala` (class `ConfigSection` lines 37-176; class `Settings.Settings` lines 253-310; `SavedState` constructor line 248)
- Create: `core/Libraries.vala`
- Create: `tests/libraries.vala`
- Modify: `meson.build` (`core_sources` list from line 58; tests from line 356)

**Interfaces:**
- Produces:
  - `ConfigSection.keyfile () : unowned KeyFile` — the options file, read once.
  - `ConfigSection.open_library () : string` — id of the open library, `""` for the main one.
  - `ConfigSection.schedule_save ()` — now public.
  - `ConfigSection.init_config (string group, string old_schema, string[] library_keys = {})`.
  - `App.settings.main.library : string`, `App.settings.main.library_name : string`, `App.settings.main.last_rowid : int`.
  - `Libraries.group (string id) : string`, `Libraries.ids () : string[]`, `Libraries.option (string id, string key) : string`, `Libraries.create (string name, string music_folder) : string`, `Libraries.rename (string id, string name)`, `Libraries.remove (string id)`, `Libraries.db_path (string id) : string`, `Libraries.new_id (string name) : string`.

- [ ] **Step 1: Make the branch**

```bash
cd /home/lchongv/Proyectos/beatbox-master
git switch -c libraries
```

- [ ] **Step 2: Write the failing test** — create `tests/libraries.vala`:

```vala
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
```

- [ ] **Step 3: Register the test and the new source** — in `meson.build`, add `'core/Libraries.vala',` to `core_sources = files(` (keep the list's order: put it next to `core/Settings.vala` if that is listed, otherwise at the end of the core files), and after the `test('peer-sync', ...)` line add:

```meson
# the options that belong to a library and the list of libraries, in a temporary config folder
test('libraries', executable('test-libraries', 'tests/libraries.vala', dependencies: core_dep))
```

Create an empty `core/Libraries.vala` for now (one line: `// see Task 1 step 5`) so meson can configure.

- [ ] **Step 4: Run the test to see it fail**

Run: `ninja -C build 2>&1 | grep -E "error" | head`
Expected: compile errors in `tests/libraries.vala`: `The name 'Libraries' does not exist`, `'library' does not exist in the context of 'BeatBox.Settings.Settings'`.

- [ ] **Step 5: Write `core/Libraries.vala`**

```vala
/*
 * The music libraries besides the main one (docs/superpowers/specs/2026-10-11-multiple-libraries-design.md).
 * The main library is what BeatBox always had: the [settings] options and beatbox.db. Each other
 * library has an id, a group "library <id>" in beatbox.conf with the options that belong to a
 * library (ConfigSection's library keys) and a database data/beatbox/libraries/<id>.db.
 */
[GIR (visible = false)] // internal, not for plugins
public class BeatBox.Libraries : Object {
	const string PREFIX = "library ";

	/** The group of beatbox.conf holding a library's own options */
	public static string group (string id) {
		return PREFIX + id;
	}

	/** The libraries besides the main one, in the order they were made */
	public static string[] ids () {
		string[] list = {};
		foreach (var g in ConfigSection.keyfile ().get_groups ())
			if (g.has_prefix (PREFIX))
				list += g.substring (PREFIX.length);
		return list;
	}

	/** A library's own value of an option (its key, with dashes), "" when unset. "" is the main library */
	public static string option (string id, string key) {
		try {
			return ConfigSection.keyfile ().get_string (id == "" ? "settings" : group (id), key);
		} catch (KeyFileError err) {
			return "";
		}
	}

	/** Adds a library and returns its id, made from its name */
	public static string create (string name, string music_folder) {
		var id = new_id (name);
		var file = ConfigSection.keyfile ();
		file.set_string (group (id), "library-name", name);
		file.set_string (group (id), "music-folder", music_folder);
		ConfigSection.schedule_save ();
		return id;
	}

	/** Renames a library that is not open (the open one's name is App.settings.main.library_name) */
	public static void rename (string id, string name) {
		ConfigSection.keyfile ().set_string (id == "" ? "settings" : group (id), "library-name", name);
		ConfigSection.schedule_save ();
	}

	/** Forgets a library besides the main one: its options and its database, not its music */
	public static void remove (string id) {
		return_if_fail (id != "");
		try {
			ConfigSection.keyfile ().remove_group (group (id));
		} catch (KeyFileError err) {}
		ConfigSection.schedule_save ();
		foreach (var suffix in new string[] { "", "-journal", ".bak" })
			FileUtils.remove (db_path (id) + suffix);
	}

	/** A library's database: beatbox.db for the main one */
	public static string db_path (string id) {
		var dir = Path.build_filename (Environment.get_user_data_dir (), "beatbox");
		return (id == "") ? Path.build_filename (dir, "beatbox.db") : Path.build_filename (dir, "libraries", id + ".db");
	}

	/** Lowercase ASCII letters, digits and dashes from the name ("Música Clásica" is musica-clasica),
	 *  with -2, -3… when that is taken */
	public static string new_id (string name) {
		var slug = new StringBuilder ();
		string s = name.normalize (-1, NormalizeMode.NFD).down ();
		unichar c;
		for (int i = 0; s.get_next_char (ref i, out c);) {
			if (c < 128 && c.isalnum ())
				slug.append_unichar (c);
			else if (c.type () != UnicodeType.NON_SPACING_MARK && slug.len > 0 && slug.str[(int) slug.len - 1] != '-')
				slug.append_c ('-');
		}
		string base_id = slug.str;
		while (base_id.has_suffix ("-"))
			base_id = base_id.substring (0, base_id.length - 1);
		if (base_id == "")
			base_id = "library";
		string id = base_id;
		for (int n = 2; ConfigSection.keyfile ().has_group (group (id)); n++)
			id = "%s-%d".printf (base_id, n);
		return id;
	}
}
```

- [ ] **Step 6: Route the library's options in `ConfigSection`** (`core/Settings.vala`)

Add two static fields after `static uint save_id = 0;`:

```vala
    static string library_group = ""; // "library <id>" while a library besides the main one is open
```

and after `string group = "";`:

```vala
    string[] library_keys = {};       // the options that belong to the open library
```

Add, after `config_path ()`:

```vala
    /** The options file, read the first time it is needed (also by Libraries) */
    public static unowned KeyFile keyfile () {
        if (file == null) {
            path = config_path ();
            file = new KeyFile ();
            first_run = !FileUtils.test (path, FileTest.EXISTS);
            try {
                file.load_from_file (path, KeyFileFlags.NONE);
            } catch (Error err) {
                if (!first_run)
                    warning ("Could not read %s, using the defaults: %s", path, err.message);
            }
            string id = "";
            try {
                id = file.get_string ("settings", "library");
            } catch (Error err) {} // the main library
            if (id != "" && !file.has_group (Libraries.group (id))) {
                warning ("The library %s has no options in %s: opening the main library", id, path);
                id = "";
            }
            library_group = (id != "") ? Libraries.group (id) : "";
        }
        return file;
    }

    /** Id of the open library: "" for the main one */
    public static string open_library () {
        keyfile ();
        return (library_group != "") ? library_group.substring (Libraries.group ("").length) : "";
    }
```

Make `schedule_save` public: `public static void schedule_save () {`.

Replace the start of `init_config` (from its doc comment to the line before `SettingsSchema? old = null;`) with:

```vala
    /** Call at the end of the subclass constructor, once the defaults are set. The options named in
     *  library_keys (with dashes) belong to the open library: another library than the main one
     *  keeps them in its own group */
    protected void init_config (string group, string old_schema, string[] library_keys = {}) {
        this.group = group;
        this.library_keys = library_keys;
        keyfile ();
```

In the `foreach (var pspec in klass.list_properties ())` loop replace

```vala
                if (file.has_group (group) && file.has_key (group, pspec.name)) {
```

with

```vala
                var g = group_of (pspec.name);
                if (file.has_group (g) && file.has_key (g, pspec.name)) {
```

Add the helper before `read_from_file`:

```vala
    /** The group an option is kept in */
    string group_of (string key) {
        return (library_group != "" && key in library_keys) ? library_group : group;
    }
```

In `read_from_file` add `var g = group_of (pspec.name);` as its first line and use `g` instead of `group` in its five `file.get_*` calls. In `store` add `var g = group_of (pspec.name);` after `get_property (...)` and use `g` instead of `group` in its five `file.set_*` calls.

- [ ] **Step 7: The new options** — in `public class Settings : ConfigSection` (inside `BeatBox.Settings`), add after `public string music_folder { get; set; }`:

```vala
        public string library { get; set; }          // id of the open library, "" the main one (Libraries)
        public string library_name { get; set; }     // the open library's name ("" shows "Music")
        public int last_rowid { get; set; }          // highest media id given in any library (LibraryManager)
```

In its constructor add `library = "";` and `library_name = "";` after `music_folder = "";`, and replace `init_config ("settings", "net.launchpad.beatbox.Settings");` with:

```vala
            init_config ("settings", "net.launchpad.beatbox.Settings", {
                "library-name", "music-folder", "music-mount-name", "watch-music-folder",
                "last-media-playing", "last-media-position" });
            if (library != ConfigSection.open_library ())
                library = ConfigSection.open_library (); // it named a library that is gone
```

In `SavedState`'s constructor replace `init_config ("savedstate", "net.launchpad.beatbox.SavedState");` with:

```vala
            init_config ("savedstate", "net.launchpad.beatbox.SavedState", { "queue" });
```

- [ ] **Step 8: Run the tests**

Run: `ninja -C build && meson test -C build libraries shortcuts --print-errorlogs`
Expected: `libraries` OK, `shortcuts` OK (it also uses the options file code).

- [ ] **Step 9: Commit**

```bash
git add core/Settings.vala core/Libraries.vala tests/libraries.vala meson.build
git commit -F - <<'EOF'
Options that belong to a library, and the list of libraries

ConfigSection keeps the options of the open library (folder, drive, last song,
queue...) in a [library <id>] group while a library besides the main one is
open; the main library keeps them where they always were. Libraries lists,
creates, renames and removes the others. New options: library, library-name
and last-rowid.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: DataBaseManager opens the open library's database

**Files:**
- Modify: `core/DatabaseInterface.vala:40-46`
- Modify: `src/DataBase/DataBaseManager.vala:233-266` (constructor)
- Modify: `tests/database-manager.vala` (new test function; `main` order and cleanup)

**Interfaces:**
- Consumes: `Libraries.db_path (string id) : string` (Task 1).
- Produces: `DataBaseManager (string library = "")`; `DatabaseInterface.shared : string` — `"shared."` while a library besides the main one is open, else `""`.

- [ ] **Step 1: Write the failing test** — in `tests/database-manager.vala`, add before `void main ()`:

```vala
// A library besides the main one: its own database, with radio and podcasts from the main one's,
// also when the main library's database doesn't exist yet
void test_library (string library_dir) {
	FileUtils.remove (Path.build_filename (library_dir, "beatbox.db"));
	var disco = new DataBaseManager ("disco");
	assert (disco.shared == "shared.");
	assert (FileUtils.test (Path.build_filename (library_dir, "libraries", "disco.db"), FileTest.EXISTS));
	try {
		disco.execute ("INSERT INTO shared.stations (uri, title) VALUES ('http://radio.invalid', 'Radio')");
		// its first opening must not import (and so empty) the shared podcasts and stations
		assert (disco.execute ("SELECT group_concat(key) FROM known_libraries").fetch_string (0) == "podcast,station");
		assert (disco.execute ("SELECT count(*) FROM songs").fetch_int (0) == 0);
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}

	var main = new DataBaseManager ();
	assert (main.shared == "");
	try {
		assert (main.execute ("SELECT title FROM stations").fetch_string (0) == "Radio");
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}

	disco = new DataBaseManager ("disco"); // not new any more: known_libraries is not filled twice
	try {
		assert (disco.execute ("SELECT count(*) FROM known_libraries").fetch_int (0) == 2);
	} catch (SQLHeavy.Error e) {
		error ("%s", e.message);
	}
}
```

Replace the end of `main ()`, from `db = null;` to the last `DirUtils.remove (dir);`, with:

```vala
	db = null;
	test_library (library_dir);

	try {
		Process.spawn_command_line_sync ("rm -rf " + Shell.quote (dir));
	} catch (SpawnError e) {
		error ("%s", e.message);
	}
```

- [ ] **Step 2: Run it to see it fail**

Run: `ninja -C build 2>&1 | grep error | head -3`
Expected: `error: Too many arguments, method 'BeatBox.DataBaseManager.new' does not take 1 arguments` (or `'shared' does not exist`).

- [ ] **Step 3: `shared` in the interface** — in `core/DatabaseInterface.vala`, inside `BeatBox.DatabaseInterface`, after `public abstract void flush();` add:

```vala
	/** Prefix of the radio and podcast tables: "shared." while a library besides the main one is
	 *  open (they are the main library's), else "" */
	public abstract string shared { get; }
```

- [ ] **Step 4: Open the library's database** — in `src/DataBase/DataBaseManager.vala` add the property before the constructor:

```vala
	public string shared { get; private set; default = ""; }
```

Replace the constructor's signature and body from `public DataBaseManager() {` down to (not including) `// Every 15 seconds, do the periodic saves` with:

```vala
	public DataBaseManager(string library = "") {
		periodic_transactions = new LinkedList<DatabaseTransactionFiller>();
		transaction_queue = new LinkedList<DatabaseTransactionFiller>();
		
		// First make sure that the folders the databases are in exist
		var path = Libraries.db_path(library);
		var main_path = Libraries.db_path("");
		foreach (var dir in new string[] { Path.get_dirname(path), Path.get_dirname(main_path) }) {
			if (DirUtils.create_with_parents(dir, 0755) != 0)
				critical("Could not create the folder %s", dir);
		}
		
		// Open the database and create any missing table
		try {
			bool existed = FileUtils.test(path, FileTest.EXISTS);
			_db = new SQLHeavy.Database (path);
			if(existed)
				backup_on_new_version(path);
			_db.execute (SCHEMA);
			add_song_columns ();
			_db.execute (PeerSync.DDL); // the live sync with itunes7 (ItunesSync)
			_db.execute ("PRAGMA user_version = %d".printf(version_number()));
			if (library != "")
				attach_main (main_path, existed);
		}
		catch (SQLHeavy.Error err) {
			critical("Could not load database: %s", err.message);
		}
		
```

and add after the constructor:

```vala
	/** A library besides the main one is open: radio and podcasts are still the main library's */
	void attach_main (string main_path, bool existed) throws SQLHeavy.Error {
		if (!FileUtils.test (main_path, FileTest.EXISTS))
			new SQLHeavy.Database (main_path).execute (SCHEMA);
		_db.execute ("ATTACH DATABASE '%s' AS shared".printf (main_path.replace ("'", "''")));
		shared = "shared.";
		// At a database's first opening every library it doesn't know imports from its folder
		// (LibraryManager.add_library), which first empties it: not the shared podcasts and stations
		if (!existed)
			_db.execute ("INSERT INTO known_libraries (key) VALUES ('podcast'), ('station')");
	}
```

- [ ] **Step 5: Run the tests**

Run: `ninja -C build && meson test -C build database-manager itunes-sync-pass --print-errorlogs`
Expected: both OK (`itunes-sync-pass` builds `DataBaseManager` too and must still compile with the default argument).

- [ ] **Step 6: Commit**

```bash
git add core/DatabaseInterface.vala src/DataBase/DataBaseManager.vala tests/database-manager.vala
git commit -F - <<'EOF'
DataBaseManager opens the open library's database

A library besides the main one has its database in libraries/<id>.db, with
beatbox.db attached as "shared" for radio and podcasts. Its first opening marks
podcasts and stations as known, so the first import never empties them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: BeatBox opens the library named in its options

**Files:**
- Modify: `src/BeatBox.vala:216` (`database = new DataBaseManager();`)
- Modify: `src/Libraries/StationLibrary.vala:32,59,125,192,258`
- Modify: `src/Libraries/PodcastLibrary.vala:32,74,140,207,273`
- Modify: `src/Core/LibraryManager.vala:57-66,101-115`
- Modify: `src/Libraries/SongLibrary.vala:66-67`
- Modify: `src/Core/ItunesSync.vala:25-30`
- Modify: `tests/smoke.py` (helpers; phases 4 and 5 after the itunes7 phase)

**Interfaces:**
- Consumes: `App.settings.main.library`, `App.settings.main.last_rowid` (Task 1); `DataBaseManager (string)`, `App.database.shared` (Task 2).
- Produces: nothing new for later tasks; after it, editing `beatbox.conf` (`library=<id>` + a `[library <id>]` group) and starting BeatBox opens that library.

- [ ] **Step 1: Write the failing test** — in `tests/smoke.py`, add after `song_row`:

```python
def table_rowids(db, table):
    try:
        with sqlite3.connect('file:%s?mode=ro' % db, uri=True, timeout=1) as c:
            return [r[0] for r in c.execute('SELECT rowid FROM %s ORDER BY rowid' % table)]
    except sqlite3.Error:
        return []


def insert_row(db, table, rowid, **values):
    """A whole row as BeatBox writes them: every TEXT column '' and every number 0 unless given"""
    with sqlite3.connect(db, timeout=5) as c:
        row = {r[1]: ('' if r[2] == 'TEXT' else 0) for r in c.execute('PRAGMA table_info(%s)' % table)}
        row.update(values)
        c.execute('INSERT INTO %s (rowid, %s) VALUES (?, %s)' % (table, ', '.join(row), ', '.join('?' * len(row))),
                  [rowid, *row.values()])


def conf_replace(conf, before, after):
    with open(conf) as f:
        text = f.read()
    if before not in text:
        fail('%r is not in beatbox.conf' % before)
    with open(conf, 'w') as f:
        f.write(text.replace(before, after, 1))


def make_song(path, freq):
    subprocess.run(['gst-launch-1.0', '-q', 'audiotestsrc', 'num-buffers=%d' % (SONG_SECONDS * 44100 // 1024),
                    'freq=%d' % freq, '!', 'audioconvert', '!', 'vorbisenc', '!', 'oggmux',
                    '!', 'filesink', 'location=' + path], check=True)
```

In `run`, replace the song loop body (the `subprocess.run(['gst-launch-1.0', ...` call) with `make_song(path, 330 + 110 * i)`.

After the itunes7 phase's `quit(proc)` (just before `finally:`), add:

```python
        # fourth run: a second library (docs/superpowers/specs/2026-10-11-multiple-libraries-design.md),
        # set up in beatbox.conf as "New Library..." leaves it. It has its own songs and play
        # counts; radio and podcasts stay the main library's, and media ids never collide.
        insert_row(db, 'stations', 900, uri='http://radio.invalid/live', title='Radio', mediatype=3)
        insert_row(db, 'podcasts', 901, uri='http://podcast.invalid/1.mp3', title='Episode', mediatype=1,
                   podcast_rss='http://podcast.invalid/feed')
        b_music = os.path.join(home, 'Music B')
        os.makedirs(b_music)
        for i in range(2):
            make_song(os.path.join(b_music, 'B %d.ogg' % (i + 1)), 550 + 110 * i)
        conf_replace(conf, '\nlibrary=\n', '\nlibrary=b\n')
        with open(conf, 'a') as f:
            f.write('\n[library b]\nlibrary-name=B\nmusic-folder=%s\n' % b_music)
        b_db = os.path.join(home, '.local', 'share', 'beatbox', 'libraries', 'b.db')
        proc = start(app, home, log)
        wait_for('the import of library B', lambda: len(songs(b_db)) == 2, 90)
        wait_for('playback in library B', play_from_top, 20)
        b_track = track()
        quit(proc)
        b_ids = [rowid for rowid, uri, count in songs(b_db)]
        if len(songs(db)) != SONGS:
            fail('library B changed the main one: %s' % songs(db))
        if not any(count for rowid, uri, count in songs(b_db)):
            fail('the play in library B was not counted: %s' % songs(b_db))
        if (table_rowids(db, 'stations'), table_rowids(db, 'podcasts')) != ([900], [901]):
            fail('radio or podcasts changed: %s %s' % (table_rowids(db, 'stations'), table_rowids(db, 'podcasts')))
        if set(b_ids) & {900, 901}:
            fail('a song of library B has the id of a station or podcast: %s' % b_ids)
        if b_track.rsplit('/', 1)[1] not in map(str, b_ids):
            fail('playing %s, not a song of library B %s' % (b_track, b_ids))
        with open(conf) as f:
            last = int(re.search(r'\nlast-rowid=(\d+)\n', f.read()).group(1))
        if last < max(b_ids + [900, 901] + [rowid for rowid, uri, count in songs(db)]):
            fail('last-rowid %d is behind the ids given' % last)
        print('library B: its own songs and play count; radio, podcasts and ids kept apart')

        # fifth run: beatbox.conf names a library that is gone: the main one opens
        conf_replace(conf, '\nlibrary=b\n', '\nlibrary=gone\n')
        proc = start(app, home, log)
        wait_for('playback in the main library', play_from_top, 20)
        main_tracks = ['/org/gnome/BeatBox/Track/%d' % rowid for rowid, uri, count in songs(db)]
        if track() not in main_tracks:
            fail('playing %s, not a song of the main library' % track())
        quit(proc)
        with open(conf) as f:
            if '\nlibrary=\n' not in f.read():
                fail('library=gone was kept')
        if os.path.exists(os.path.join(home, '.local', 'share', 'beatbox', 'libraries', 'gone.db')):
            fail('a database was made for the missing library')
        print('a library that is gone opens the main one')
```

- [ ] **Step 2: Run it to see it fail**

Run: `ninja -C build && meson test -C build smoke --print-errorlogs`
Expected: FAIL at `timed out waiting for the import of library B` (BeatBox still opens `beatbox.db`).

- [ ] **Step 3: Open the library's database** — in `src/BeatBox.vala` replace `database = new DataBaseManager();` with:

```vala
		database = new DataBaseManager(settings.main.library);
```

- [ ] **Step 4: Radio from the shared tables** — in `src/Libraries/StationLibrary.vala`:

Replace line 32 `const string LOAD_STATIONS_QUERY = "SELECT rowid,* FROM 'stations'";` with:

```vala
	// the main library's, also while another one is open (DataBaseManager.shared)
	string table { owned get { return App.database.shared + "stations"; } }
```

Replace `var results = App.database.execute(LOAD_STATIONS_QUERY);` with `var results = App.database.execute("SELECT rowid,* FROM " + table);`.

Replace the beginning of the INSERT, `transaction.prepare ("""INSERT INTO 'stations' ('rowid',` with `transaction.prepare ("INSERT INTO " + table + """ ('rowid',` (rest of the line and statement unchanged).

Replace the beginning of the UPDATE, `transaction.prepare("""UPDATE 'stations' SET uri=:uri,` with `transaction.prepare("UPDATE " + table + """ SET uri=:uri,` (rest unchanged).

Replace `transaction.prepare("DELETE FROM 'stations' WHERE uri=:uri");` with `transaction.prepare("DELETE FROM " + table + " WHERE uri=:uri");`.

- [ ] **Step 5: Podcasts from the shared tables** — in `src/Libraries/PodcastLibrary.vala`, the same five changes with `podcasts`:

```vala
	// the main library's, also while another one is open (DataBaseManager.shared)
	string table { owned get { return App.database.shared + "podcasts"; } }
```

replacing `const string LOAD_PODCASTS_QUERY = ...`; `App.database.execute(LOAD_PODCASTS_QUERY)` → `App.database.execute("SELECT rowid,* FROM " + table)`; `"""INSERT INTO 'podcasts' ('rowid',` → `"INSERT INTO " + table + """ ('rowid',`; `"""UPDATE 'podcasts' SET uri=:uri,` → `"UPDATE " + table + """ SET uri=:uri,`; `"DELETE FROM 'podcasts' WHERE uri=:uri"` → `"DELETE FROM " + table + " WHERE uri=:uri"`.

Check none is left: `grep -n "'stations'\|'podcasts'" src/Libraries/*.vala` prints nothing.

- [ ] **Step 6: One media numbering for every library** — in `src/Core/LibraryManager.vala`, in the constructor add before `load_known_libraries();`:

```vala
		// songs, podcasts and stations share one numbering, and every library shares the podcasts
		// and stations: ids go on from the highest given in any library
		top_id = App.settings.main.last_rowid;
```

and in `assign_id_to_media`, after the `if/else if` that sets `top_id`, add:

```vala
		if(top_id > App.settings.main.last_rowid)
			App.settings.main.last_rowid = top_id;
```

- [ ] **Step 7: A new library imports its own folder** — in `src/Libraries/SongLibrary.vala` replace the first line of the constructor (`_default_folder = File.new_for_path(Environment.get_user_special_dir(...`) with:

```vala
		// what a new database imports first (LibraryManager.add_library): the open library's
		// folder, or the user's Music folder on a first run
		var music = App.settings.main.music_folder;
		_default_folder = File.new_for_path(music != "" ? music : (Environment.get_user_special_dir(UserDirectory.MUSIC) ?? Path.build_filename(Environment.get_home_dir(), "Music")));
```

- [ ] **Step 8: itunes7 only with the main library** — in `src/Core/ItunesSync.vala` replace `if (App.settings.main.itunes7_sync)` in `setting_changed` with:

```vala
		// itunes7 reads beatbox.db, the main library's (the open library changes only with a restart)
		if (App.settings.main.itunes7_sync && App.settings.main.library == "")
```

- [ ] **Step 9: Run the tests**

Run: `ninja -C build && meson test -C build --print-errorlogs`
Expected: all OK; the smoke log shows `library B: its own songs and play count; radio, podcasts and ids kept apart` and `a library that is gone opens the main one`, then `OK`.

- [ ] **Step 10: A copy of the user's library opens unchanged** (spec test 5) — with the appendix helpers, scratch home `real`:

```bash
H=$S/h-real; mkdir -p $H/.local/share/beatbox $H/.config/beatbox $S/empty
sqlite3 -readonly ~/.local/share/beatbox/beatbox.db ".backup '$H/.local/share/beatbox/beatbox.db'"
BEFORE=$(sqlite3 $H/.local/share/beatbox/beatbox.db "SELECT count(*), max(rowid) FROM songs")
# never play or tag the user's files: no last song to resume, no cover downloads
grep -v -E "^(music-folder|podcast-folder|itunes7-sync|watch-music-folder|download-new-podcasts|last-media-playing|download-covers)=" ~/.config/beatbox/beatbox.conf > $H/.config/beatbox/beatbox.conf
sed -i "s|^\[settings\]|[settings]\nmusic-folder=$S/empty\npodcast-folder=$H/Podcasts\nitunes7-sync=false\nwatch-music-folder=false\ndownload-new-podcasts=false\nlast-media-playing=0\ndownload-covers=false|" $H/.config/beatbox/beatbox.conf
(bash $S/session.sh real &) ; bash $S/ready.sh real && sleep 5 && bash $S/quit.sh real; sleep 5
sqlite3 $H/.local/share/beatbox/beatbox.db "SELECT count(*), max(rowid) FROM songs"; echo "before: $BEFORE"
grep -E "^(library|library-name|last-rowid)=" $H/.config/beatbox/beatbox.conf; ls $H/.local/share/beatbox
rm -rf $H
```

Expected: the song count is the same as `before` (rowids unchanged); the conf gained `library=`, `library-name=` and `last-rowid=` at least the highest rowid of songs, podcasts and stations; there is no `libraries` folder. The user's own files are only read (`-readonly`, `grep`).

- [ ] **Step 11: Commit**

```bash
git add src/BeatBox.vala src/Libraries/StationLibrary.vala src/Libraries/PodcastLibrary.vala src/Core/LibraryManager.vala src/Libraries/SongLibrary.vala src/Core/ItunesSync.vala tests/smoke.py
git commit -F - <<'EOF'
BeatBox opens the library named in its options

With [settings] library=<id> BeatBox opens that library's database and
folder; radio and podcasts come from the main one. Media ids go on from a
shared last-rowid, so a podcast never takes the id of another library's song.
A new library's first import reads its own folder, and the itunes7 sync runs
only with the main library. The smoke test opens a second library and one
that is gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Switching from the app menu

**Files:**
- Create: `src/Core/LibrarySwitcher.vala`
- Modify: `src/BeatBox.vala` (static fields near line 100; `activate` after `actions = new Actions();` line 220; `main` line 79-80)
- Modify: `src/Core/LibraryWindow.vala:377` (app menu)
- Modify: `src/Views/SideTreeView.vala:94` (sidebar heading)
- Modify: `meson.build` (`app_sources`), `po/POTFILES`

**Interfaces:**
- Consumes: `Libraries.*` (Task 1), `App.settings.main.library`, `App.settings.main.library_name`.
- Produces: `App.libraries : LibrarySwitcher`; `App.restart_requested : bool`; `LibrarySwitcher.menu : GLib.Menu`; `LibrarySwitcher.switch_to (string id)`; `LibrarySwitcher.rename (string id, string name)`; `LibrarySwitcher.remove (string id)`; static `LibrarySwitcher.name_of (string id) : string`; static `LibrarySwitcher.all_ids () : string[]` (main library first, as `""`).

- [ ] **Step 1: Write `src/Core/LibrarySwitcher.vala`**

```vala
/*
 * The app menu's Library submenu: switch to another library (BeatBox restarts with it) or make
 * a new one from a name and a folder. Spec: docs/superpowers/specs/2026-10-11-multiple-libraries-design.md
 */
using Gtk;

public class BeatBox.LibrarySwitcher : Object {
	public GLib.Menu menu { get; private set; default = new GLib.Menu (); }
	SimpleAction switch_action;

	public LibrarySwitcher () {
		switch_action = new SimpleAction.stateful ("switch-library", VariantType.STRING, new Variant.string (App.settings.main.library));
		switch_action.activate.connect ((parameter) => switch_to (parameter.get_string ()));
		App.actions.group.add_action (switch_action);
		var create = new SimpleAction ("new-library", null);
		create.activate.connect (() => new_library ());
		App.actions.group.add_action (create);
		fill_menu ();
	}

	/** The main library ("") and the others */
	public static string[] all_ids () {
		string[] ids = { "" };
		foreach (var id in Libraries.ids ())
			ids += id;
		return ids;
	}

	/** A library's name for people: the main one is "Music" until renamed */
	public static string name_of (string id) {
		string name = (id == App.settings.main.library) ? App.settings.main.library_name : Libraries.option (id, "library-name");
		return (name != "") ? name : (id == "" ? _("Music") : id);
	}

	void fill_menu () {
		menu.remove_all ();
		var list = new GLib.Menu ();
		foreach (var id in all_ids ()) {
			var item = new GLib.MenuItem (name_of (id), null);
			item.set_action_and_target_value ("bb.switch-library", new Variant.string (id));
			list.append_item (item);
		}
		menu.append_section (null, list);
		var more = new GLib.Menu ();
		more.append (_("New Library…"), "bb.new-library");
		more.append (_("Manage Libraries…"), "bb." + App.actions.show_preferences.name); // Preferences opens on its Library page
		menu.append_section (null, more);
	}

	/** Restarts BeatBox with another library, once it has saved everything as when it quits */
	public void switch_to (string id) {
		if (id == App.settings.main.library)
			return;
		if (App.operations.doing_ops) {
			App.window.doAlert (_("Cannot Switch Libraries"), _("Wait until the current import or operation finishes."));
			return;
		}
		App.settings.main.library = id;
		App.restart_requested = true;
		App.window.destroy ();
	}

	public void rename (string id, string name) {
		if (id == App.settings.main.library)
			App.settings.main.library_name = name; // the open one's options go through the settings
		else
			Libraries.rename (id, name);
		fill_menu ();
	}

	public void remove (string id) {
		return_if_fail (id != "" && id != App.settings.main.library);
		Libraries.remove (id);
		fill_menu ();
	}

	void new_library () {
		var dialog = new Dialog.with_buttons (_("New Library"), (Gtk.Window) App.window,
		                                      DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
		                                      _("Cancel"), ResponseType.CANCEL, _("Create"), ResponseType.OK);
		var name = new Entry () { activates_default = true, placeholder_text = _("External Disk") };
		var folder = new FileChooserButton (_("Music Folder"), FileChooserAction.SELECT_FOLDER);
		var grid = new Grid () { row_spacing = 8, column_spacing = 8, margin = 12 };
		grid.attach (new Label (_("Name:")) { xalign = 1 }, 0, 0);
		grid.attach (name, 1, 0);
		grid.attach (new Label (_("Music folder:")) { xalign = 1 }, 0, 1);
		grid.attach (folder, 1, 1);
		var hint = new Label (_("BeatBox restarts with the new library and imports the folder."));
		hint.get_style_context ().add_class ("dim-label");
		grid.attach (hint, 0, 2, 2, 1);
		dialog.get_content_area ().add (grid);
		dialog.set_default_response (ResponseType.OK);
		var ok = dialog.get_widget_for_response (ResponseType.OK);
		ok.sensitive = false;
		name.changed.connect (() => { ok.sensitive = name.text.strip () != "" && folder.get_filename () != null; });
		folder.selection_changed.connect (() => { ok.sensitive = name.text.strip () != "" && folder.get_filename () != null; });
		dialog.show_all ();
		bool create = dialog.run () == ResponseType.OK;
		string library_name = name.text.strip ();
		string? music = folder.get_filename ();
		dialog.destroy ();
		if (create && music != null)
			switch_to (Libraries.create (library_name, music));
	}
}
```

Add `'src/Core/LibrarySwitcher.vala',` to `app_sources = files(` in `meson.build` next to the other `src/Core/` files, and `src/Core/LibrarySwitcher.vala` to `po/POTFILES` in its alphabetical place among the `src/Core/` lines.

- [ ] **Step 2: Restart and the App fields** — in `src/BeatBox.vala`, next to the other static members (after `public static BeatBox.PluginManager plugins { get; private set; }`), add:

```vala
	public static LibrarySwitcher libraries { get; private set; }
	/** Set when another library was picked: main() runs the program again once it has quit */
	public static bool restart_requested = false;
```

In `activate`, after `actions = new Actions();`, add `libraries = new LibrarySwitcher();`.

In `main`, replace `return app.run (args);` with:

```vala
	int status = app.run (args);
	if (BeatBox.App.restart_requested) {
		// another library was picked (LibrarySwitcher): the same program again, without the files it was given
		try {
			var self = FileUtils.read_link ("/proc/self/exe");
			Posix.execv (self, { args[0] });
			warning ("Could not restart %s: %s", self, Posix.strerror (Posix.errno));
		} catch (FileError err) {
			warning ("Could not restart: %s", err.message);
		}
	}
	return status;
```

- [ ] **Step 3: The submenu and the sidebar heading** — in `src/Core/LibraryWindow.vala`, before `settingsMenu.append(_("_Mini Player"), "bb.mini_player");` add:

```vala
		settingsMenu.append_submenu(_("_Library"), App.libraries.menu);
```

In `src/Views/SideTreeView.vala` replace `library_iter = addItem(null, null, null, null, null, _("Library"), null, false, false, false);` with:

```vala
		// headed by the open library's name (LibrarySwitcher)
		library_iter = addItem(null, null, null, null, null, LibrarySwitcher.name_of(App.settings.main.library), null, false, false, false);
		App.settings.main.notify["library-name"].connect(() => setName(library_iter, LibrarySwitcher.name_of(App.settings.main.library)));
```

- [ ] **Step 4: Build and run the automatic tests**

Run: `ninja -C build && meson test -C build --print-errorlogs`
Expected: all OK (nothing above changes what they check).

- [ ] **Step 5: GUI check, new library and restart** — with the helpers of the appendix (scratch home `lib`, its `beatbox.conf` with `music-folder` = a folder `A` of 3 generated songs; a folder `B` of 2 generated songs):
  1. `session.sh lib`, `ready.sh lib`, screenshot: the sidebar heading reads `MUSIC`.
  2. Click the round app menu (top right), screenshot: a `Library` item with a submenu; open it: `Music` (checked), `New Library…`, `Manage Libraries…`.
  3. Click `New Library…`; type `Disco B`; click the folder button, `Other…`, Ctrl+L, type the path of `B`, Enter, Enter; screenshot of the dialog with `Create` sensitive; click `Create`.
  4. Within 10 s: the window is back (same PID: `pgrep -f "build/beatbox"`), the sidebar heading reads `DISCO B`, the list shows B's 2 songs; `beatbox.conf` has `library=disco-b` and `[library disco-b]` with `music-folder=<B>`; `libraries/disco-b.db` exists.
  Expected: all four hold; `out.log` has no `CRITICAL`.

- [ ] **Step 6: GUI check, switch back and forth** (Review Focus 4) — in `Disco B` play the second song, seek to ~0:04 (MPRIS `SetPosition`), pause; app menu › Library › `Music`: BeatBox restarts showing A's songs; play A's third song, pause at ~0:03; switch to `Disco B` again.
  Expected: after each switch the library shows its own last song selected/resumed at its own position (`last-media-playing` / `last-media-position` in `[settings]` and `[library disco-b]` differ and match), and B's play count and A's play counts in their databases are unchanged by the other library.

- [ ] **Step 7: GUI check, switch during an import** (Review Focus 5) — generate 60 songs in a folder `C`, create library `C` from the dialog; as soon as the window is back (the import of C runs), open app menu › Library › `Music`.
  Expected: a `Cannot Switch Libraries` alert; BeatBox does not restart; `library=c` stays in `beatbox.conf`; once the import ends, switching works.

- [ ] **Step 8: Commit**

```bash
git add src/Core/LibrarySwitcher.vala src/BeatBox.vala src/Core/LibraryWindow.vala src/Views/SideTreeView.vala meson.build po/POTFILES
git commit -F - <<'EOF'
Switching libraries from the app menu

The app menu gets a Library submenu: the libraries (the open one checked),
New Library... (a name and a folder) and Manage Libraries.... Picking another
library saves everything as on quit and runs BeatBox again with it; the
sidebar's heading shows the open library's name.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Managing libraries in Preferences

**Files:**
- Modify: `src/Preferences/BehaviorPreferences.vala:73-90` (class `LibraryPreferences`)

**Interfaces:**
- Consumes: `LibrarySwitcher.all_ids ()`, `LibrarySwitcher.name_of (string)`, `App.libraries.rename (string, string)`, `App.libraries.remove (string)` (Task 4); `Libraries.option (string, string)` (Task 1).

- [ ] **Step 1: The Libraries section** — in `LibraryPreferences` add a field before the constructor:

```vala
	Box libraries = new Box(Orientation.VERTICAL, 6);
```

At the start of the constructor, before `add_heading(_("Library Management"));`, add:

```vala
		add_heading(_("Libraries"));
		add_row(libraries);
		fill_libraries();
```

After `itunes7.toggled.connect(...)` add:

```vala
		if (App.settings.main.library != "") { // itunes7 reads beatbox.db: the main library's
			itunes7.sensitive = false;
			itunes7.tooltip_text = _("Only with the main library open: itunes7 reads its database.");
		}
```

Add the methods after the constructor:

```vala
	void fill_libraries() {
		libraries.foreach((w) => w.destroy());
		foreach (var id in LibrarySwitcher.all_ids()) {
			var row = new Box(Orientation.HORIZONTAL, 8);
			var name = new Label("");
			string text = Markup.escape_text(LibrarySwitcher.name_of(id));
			name.set_markup(id == App.settings.main.library ? "<b>%s</b> %s".printf(text, Markup.escape_text(_("(open)"))) : text);
			var folder = new Label(Libraries.option(id, "music-folder"));
			folder.get_style_context().add_class("dim-label");
			folder.ellipsize = Pango.EllipsizeMode.START;
			folder.xalign = 0;
			folder.hexpand = true;
			row.add(name);
			row.add(folder);
			var rename = new Button.with_label(_("Rename…"));
			rename.clicked.connect(() => ask_rename(id));
			row.add(rename);
			if (id != "" && id != App.settings.main.library) { // never the main or the open one
				var remove = new Button.with_label(_("Remove…"));
				remove.clicked.connect(() => ask_remove(id));
				row.add(remove);
			}
			libraries.add(row);
		}
		libraries.show_all();
	}

	void ask_rename(string id) {
		var dialog = new Dialog.with_buttons(_("Rename Library"), (Gtk.Window) libraries.get_toplevel(),
		                                     DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
		                                     _("Cancel"), ResponseType.CANCEL, _("Rename"), ResponseType.OK);
		var entry = new Entry() { text = LibrarySwitcher.name_of(id), activates_default = true, margin = 12 };
		dialog.get_content_area().add(entry);
		dialog.set_default_response(ResponseType.OK);
		dialog.show_all();
		bool rename = dialog.run() == ResponseType.OK && entry.text.strip() != "";
		string name = entry.text.strip();
		dialog.destroy();
		if (rename) {
			App.libraries.rename(id, name);
			fill_libraries();
		}
	}

	void ask_remove(string id) {
		var dialog = new MessageDialog((Gtk.Window) libraries.get_toplevel(), DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
		                               MessageType.WARNING, ButtonsType.NONE, _("Remove the library “%s”?"), LibrarySwitcher.name_of(id));
		dialog.secondary_text = _("Its songs, play counts and playlists are removed from BeatBox; the music files stay where they are.");
		dialog.add_button(_("Cancel"), ResponseType.CANCEL);
		dialog.add_button(_("Remove"), ResponseType.OK);
		bool remove = dialog.run() == ResponseType.OK;
		dialog.destroy();
		if (remove) {
			App.libraries.remove(id);
			fill_libraries();
		}
	}
```

- [ ] **Step 2: Build and run the automatic tests**

Run: `ninja -C build && meson test -C build --print-errorlogs`
Expected: all OK.

- [ ] **Step 3: GUI check** — in the `lib` scratch home of Task 4 (libraries Music, Disco B, C; Disco B open): app menu › Library › `Manage Libraries…`.
  Expected: Preferences opens on `Library` with a `Libraries` section listing `Music`, `Disco B (open)` in bold and `C`, each with its folder; `Remove…` only on `C`; the itunes7 check is insensitive with the tooltip. `Rename…` on `Disco B` → `Disco Bis`: the sidebar heading becomes `DISCO BIS` and the submenu shows it; `Rename…` on `Music` → `Principal`: `[settings] library-name=Principal`. `Remove…` on `C` → confirm: `C` leaves the list and the submenu, `[library c]` and `libraries/c.db` are gone. Switch to `Principal`: the itunes7 check is sensitive again and `Remove…` appears on `Disco Bis` only.

- [ ] **Step 4: Commit**

```bash
git add src/Preferences/BehaviorPreferences.vala
git commit -F - <<'EOF'
Libraries are renamed and removed in Preferences

Preferences > Library lists the libraries with their folders; any of them can
be renamed, and the ones besides the main and the open one removed (their
database and options, never the music). The itunes7 option is off while a
library besides the main one is open.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: README and Spanish

**Files:**
- Modify: `README.md` (new section after "Sync with itunes7", before "Building")
- Modify: `po/es.po`

- [ ] **Step 1: README** — insert before the `Building` heading:

```markdown
Several libraries
-----------------

The app menu's Library submenu switches between music libraries: each one has
its own folder, songs, ratings, play counts and playlists, while radio stations
and podcasts are the same in all of them. "New Library…" asks for a name and a
folder. Switching restarts BeatBox with the other library (a second or two),
and the drive the library lives on is mounted when it is connected. The first
library is the one BeatBox always had (~/.local/share/beatbox/beatbox.db, the
one itunes7 syncs with); the others keep their database in
~/.local/share/beatbox/libraries. Preferences › Library renames and removes them.
```

- [ ] **Step 2: Spanish** — for each msgid below, check `grep -n 'msgid "<text>"' po/es.po`; add the missing ones by hand to `po/es.po` with a `#: <file>:<line>` reference line (as the existing entries do), following the file's existing style for quotes and accents (check how `“%s”` and "solo/sólo" are written in it and do the same):

| msgid | msgstr |
|---|---|
| `_Library` | `_Biblioteca` |
| `New Library…` | `Nueva biblioteca…` |
| `Manage Libraries…` | `Administrar bibliotecas…` |
| `Cannot Switch Libraries` | `No se puede cambiar de biblioteca` |
| `Wait until the current import or operation finishes.` | `Espera a que termine la importación u operación en curso.` |
| `New Library` | `Nueva biblioteca` |
| `Create` | `Crear` |
| `External Disk` | `Disco externo` |
| `Name:` | `Nombre:` |
| `Music folder:` | `Carpeta de música:` |
| `BeatBox restarts with the new library and imports the folder.` | `BeatBox se reinicia con la nueva biblioteca e importa la carpeta.` |
| `Libraries` | `Bibliotecas` |
| `(open)` | `(abierta)` |
| `Rename…` | `Renombrar…` |
| `Remove…` | `Eliminar…` |
| `Rename Library` | `Renombrar biblioteca` |
| `Rename` | `Renombrar` |
| `Remove the library “%s”?` | `¿Eliminar la biblioteca “%s”?` |
| `Its songs, play counts and playlists are removed from BeatBox; the music files stay where they are.` | `Sus canciones, reproducciones y listas se quitan de BeatBox; los archivos de música quedan donde están.` |
| `Remove` | `Eliminar` |
| `Only with the main library open: itunes7 reads its database.` | `Solo con la biblioteca principal abierta: itunes7 lee su base de datos.` |

Run: `msgfmt -c --statistics -o /dev/null po/es.po`
Expected: no errors; the untranslated count does not grow compared with `git stash; msgfmt ...; git stash pop`.

- [ ] **Step 3: Check the Spanish UI** — `ninja -C build`, then a headless start with `LANG=es_ES.UTF-8` (appendix helpers): the app menu shows `Biblioteca` › `Música`, `Nueva biblioteca…`, `Administrar bibliotecas…`; Preferences › Colección shows `Bibliotecas`.

- [ ] **Step 4: Commit**

```bash
git add README.md po/es.po
git commit -F - <<'EOF'
README and Spanish for several libraries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

## Appendix: driving BeatBox headless for the GUI checks

Put these in a scratch folder (`$S`), never in the repository. They give BeatBox a private Xvfb, D-Bus session and home (`$S/h-<name>`), refuse to run against the user's own display or bus, and click/type/screenshot with python-xlib.

`session.sh NAME` — starts Xvfb + `dbus-run-session` + BeatBox from `build/`, writing `$S/h-NAME/env`:

```bash
#!/bin/bash
S=${S:?set S to the scratch folder}
H=$S/h-$1
mkdir -p $H/.config/beatbox $H/run; chmod 700 $H/run; rm -f $H/env
[ -f $H/.config/beatbox/beatbox.conf ] || printf '[settings]\nskin=template\nmusic-folder=%s\n[savedstate]\nwindow-width=1100\nwindow-height=700\n' "$H/A" > $H/.config/beatbox/beatbox.conf
for DNUM in 91 92 93 94 95; do [ -e /tmp/.X$DNUM-lock ] || break; done
Xvfb :$DNUM -screen 0 1100x700x24 -nolisten tcp 2>/dev/null & XPID=$!
sleep 1
unset WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
export DISPLAY=:$DNUM GDK_BACKEND=x11 NO_AT_BRIDGE=1 HOME=$H XDG_CONFIG_HOME=$H/.config XDG_DATA_HOME=$H/.local/share \
  XDG_CACHE_HOME=$H/.cache XDG_RUNTIME_DIR=$H/run LANG=${LANG_TEST:-C.UTF-8} \
  GST_PLUGIN_FEATURE_RANK=pulsesink:NONE,pipewiresink:NONE,alsasink:NONE,jackaudiosink:NONE,osssink:NONE,oss4sink:NONE,openalsink:NONE
dbus-run-session -- bash -c 'env | grep -E "^(DISPLAY|DBUS_SESSION_BUS_ADDRESS|HOME)=" | sed "s/^/export /;s/=/=\"/;s/$/\"/" > $HOME/env.tmp && mv $HOME/env.tmp $HOME/env; /home/lchongv/Proyectos/beatbox-master/build/beatbox > $HOME/out.log 2>&1'
kill $XPID 2>/dev/null
```

`in.sh NAME command…` — runs a command inside that session:

```bash
#!/bin/bash
S=${S:?}; H=$S/h-$1; shift
for i in $(seq 60); do [ -f $H/env ] && break; sleep 0.5; done
source $H/env || exit 1
case "$DISPLAY" in :9?) ;; *) echo "bad DISPLAY $DISPLAY"; exit 1;; esac
[ -n "$DBUS_SESSION_BUS_ADDRESS" ] || { echo "no bus"; exit 1; }
export DISPLAY DBUS_SESSION_BUS_ADDRESS
"$@"
```

`ready.sh NAME` — waits for MPRIS: `for i in $(seq 120); do bash $S/in.sh $1 gdbus call --session --dest org.mpris.MediaPlayer2.beatbox --object-path /org/mpris/MediaPlayer2 --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 && exit 0; sleep 0.5; done; exit 1`

`quit.sh NAME` — `bash $S/in.sh $1 gdbus call --session --dest org.mpris.MediaPlayer2.beatbox --object-path /org/mpris/MediaPlayer2 --method org.mpris.MediaPlayer2.Quit`

`drive.py OUT step…` — steps `sleep:N shot:NAME click:X,Y rclick:X,Y dclick:X,Y key:Control_L+l type:TEXT`:

```python
import sys, time, subprocess
from Xlib import X, display, XK
from Xlib.ext import xtest
d = display.Display()
def move(x, y): xtest.fake_input(d, X.MotionNotify, x=x, y=y); d.sync()
def click(x, y, b=1):
    move(x, y); time.sleep(0.15); xtest.fake_input(d, X.ButtonPress, b); d.sync(); time.sleep(0.05); xtest.fake_input(d, X.ButtonRelease, b); d.sync()
def key(combo):
    codes = [d.keysym_to_keycode(XK.string_to_keysym(n)) for n in combo.split('+')]
    for c in codes: xtest.fake_input(d, X.KeyPress, c)
    d.sync(); time.sleep(0.05)
    for c in reversed(codes): xtest.fake_input(d, X.KeyRelease, c)
    d.sync()
out = sys.argv[1]
for step in sys.argv[2:]:
    k, _, v = step.partition(':')
    if k == 'sleep': time.sleep(float(v))
    elif k == 'shot': subprocess.run(['import', '-window', 'root', f'{out}-{v}.png'])
    elif k == 'click': click(*map(int, v.split(',')))
    elif k == 'rclick': click(*map(int, v.split(',')), b=3)
    elif k == 'dclick': x, y = map(int, v.split(',')); click(x, y); time.sleep(0.05); click(x, y)
    elif k == 'key': key(v)
    elif k == 'type':
        for ch in v:
            sym = {' ': 'space', ',': 'comma', '-': 'minus', '/': 'slash', '.': 'period', '_': 'underscore'}.get(ch, ch)
            key(('Shift_L+' if ch.isupper() else '') + sym)
    time.sleep(0.3)
```

Songs: `gst-launch-1.0 -q audiotestsrc num-buffers=344 freq=440 ! audioconvert ! vorbisenc ! oggmux ! filesink location=$H/A/Song1.ogg` (8 s each; vary `freq`). Never point a scratch home at the user's real music or `~/.config/beatbox`. After a session, check nothing is left: `pgrep -af "Xvfb :9"` must show only the grep itself.
