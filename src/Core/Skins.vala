/*
 * Optional skins, installed like plugins: a folder holding
 *   skin.ini  — [Skin] Name=, Description=, Author=
 *   skin.css  — GTK CSS laid over the built-in iTunes look
 * A skin can be as small as a few @define-color lines (see skins/README.md).
 *
 * Bundled skins live in the GResource; anyone can drop more into
 * ~/.local/share/beatbox/skins/<folder>/ (or <datadir>/beatbox/skins/).
 */

namespace BeatBox.Skins {
	public class Skin : Object {
		public string id;
		public string name;
		public string description;
		public string author;
		public File css;
	}

	const string RESOURCE = "/net/launchpad/beatbox/skins";
	Gtk.CssProvider? provider = null;

	public string user_dir () {
		return Path.build_filename (Environment.get_user_data_dir (), "beatbox", "skins");
	}

	/** Every skin found, sorted by name. A user skin replaces a bundled one with the same folder name. */
	public Gee.List<Skin> available () {
		var found = new Gee.HashMap<string, Skin> ();
		try {
			foreach (var child in resources_enumerate_children (RESOURCE, ResourceLookupFlags.NONE)) {
				var id = child.replace ("/", "");
				var skin = load (id, File.new_for_uri ("resource://" + RESOURCE + "/" + id));
				if (skin != null)
					found[id] = skin;
			}
		} catch (Error err) {}

		string[] dirs = {};
		foreach (var d in Environment.get_system_data_dirs ())
			dirs += Path.build_filename (d, "beatbox", "skins");
		dirs += user_dir (); // last, so it wins
		foreach (var dir in dirs) {
			try {
				var e = File.new_for_path (dir).enumerate_children (FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = e.next_file ()) != null) {
					var skin = load (info.get_name (), File.new_for_path (dir).get_child (info.get_name ()));
					if (skin != null)
						found[skin.id] = skin;
				}
			} catch (Error err) {}
		}

		var list = new Gee.ArrayList<Skin> ();
		list.add_all (found.values);
		list.sort ((a, b) => a.name.collate (b.name));
		return list;
	}

	Skin? load (string id, File folder) {
		var css = folder.get_child ("skin.css");
		if (!css.query_exists ())
			return null;
		var skin = new Skin ();
		skin.id = id;
		skin.name = id;
		skin.description = "";
		skin.author = "";
		skin.css = css;
		try {
			uint8[] data;
			folder.get_child ("skin.ini").load_contents (null, out data, null);
			var ini = new KeyFile ();
			ini.load_from_data ((string)data, data.length, KeyFileFlags.NONE);
			// Name[es]= and friends are honoured
			skin.name = ini.get_locale_string ("Skin", "Name");
			if (ini.has_key ("Skin", "Description"))
				skin.description = ini.get_locale_string ("Skin", "Description");
			if (ini.has_key ("Skin", "Author"))
				skin.author = ini.get_string ("Skin", "Author");
		} catch (Error err) {}
		return skin;
	}

	/** Lay the skin over the base look; "" (or an unknown skin) goes back to plain iTunes */
	public void apply (string id) {
		var screen = Gdk.Screen.get_default ();
		if (provider != null)
			Gtk.StyleContext.remove_provider_for_screen (screen, provider);
		provider = null;
		if (id == "")
			return;

		foreach (var skin in available ()) {
			if (skin.id != id)
				continue;
			provider = new Gtk.CssProvider ();
			try {
				provider.load_from_file (skin.css);
			} catch (Error err) {
				warning ("Could not load skin %s: %s", id, err.message);
			}
			Gtk.StyleContext.add_provider_for_screen (screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2);
			return;
		}
		warning ("Skin %s not found", id);
	}
}
