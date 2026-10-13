/*
 * The music libraries besides the main one (docs/superpowers/specs/2026-10-11-multiple-libraries-design.md).
 * The main library is what BeatBox always had: the [settings] options and beatbox.db. Each other
 * library has an id, a group "library <id>" in beatbox.conf with the options that belong to a
 * library (ConfigSection's library keys) and a database libraries/<id>.db.
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
