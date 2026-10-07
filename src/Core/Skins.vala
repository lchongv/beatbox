/*
 * Optional skins, installed like plugins: a folder holding
 *   skin.ini  — [Skin] Name=, Author=, Native=true
 *               (Native drops the built-in look and keeps only the GTK theme)
 *   skin.css  — GTK CSS laid over the built-in look
 *   preview.png — optional, a screenshot shown in Preferences
 * A skin can be as small as a few @define-color lines (see skins/README.md).
 *
 * Bundled skins live in the GResource; anyone can drop more into
 * ~/.local/share/beatbox/skins/<folder>/ (or <datadir>/beatbox/skins/).
 */

namespace BeatBox.Skins {
	public class Skin : Object {
		public string id;
		public string name;
		public string author;
		public File css;
		public File? preview; // preview.png, a screenshot
		public bool native;
		public string? theme; // a GTK theme to use instead of the system's (Theme=)
		public bool dark;     // its dark variant (Dark=true)
		public bool square_icon; // the app menu button shows the square app icon (MenuIcon=square)
	}

	/** The skin used when none was chosen: plain GTK with Adwaita */
	public const string DEFAULT = "adwaita";

	const string RESOURCE = "/net/launchpad/beatbox/skins";
	Gtk.CssProvider? provider = null;
	Gtk.CssProvider? base_look = null;
	/** Whether the skin applied last wants the square app icon on the menu button */
	public bool square_menu_icon = false;
	string? system_theme = null; // what the desktop asked for, restored by skins without Theme=
	bool system_dark;

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
		skin.author = "";
		skin.css = css;
		if (folder.get_child ("preview.png").query_exists ())
			skin.preview = folder.get_child ("preview.png");
		try {
			uint8[] data;
			folder.get_child ("skin.ini").load_contents (null, out data, null);
			var ini = new KeyFile ();
			ini.load_from_data ((string)data, data.length, KeyFileFlags.NONE);
			// Name[es]= and friends are honoured
			skin.name = ini.get_locale_string ("Skin", "Name");
			if (ini.has_key ("Skin", "Native"))
				skin.native = ini.get_boolean ("Skin", "Native");
			if (ini.has_key ("Skin", "Theme"))
				skin.theme = ini.get_string ("Skin", "Theme");
			if (ini.has_key ("Skin", "Dark"))
				skin.dark = ini.get_boolean ("Skin", "Dark");
			if (ini.has_key ("Skin", "MenuIcon"))
				skin.square_icon = ini.get_string ("Skin", "MenuIcon") == "square";
			if (ini.has_key ("Skin", "Author"))
				skin.author = ini.get_string ("Skin", "Author");
		} catch (Error err) {}
		return skin;
	}

	/** Whether the skin lives in the user's skins folder, so it can be saved in place */
	public bool is_user (Skin skin) {
		var path = skin.css.get_path ();
		return path != null && path.has_prefix (user_dir () + Path.DIR_SEPARATOR_S);
	}

	/** Shows css in place of the skin's own until the skin is applied again (the CSS editor).
	 * Returns the first error, if any; what parsed before it is shown anyway. */
	public string? preview_css (Skin skin, string css) {
		if (provider == null) {
			provider = new Gtk.CssProvider ();
			Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2);
		}
		// relative url("image.png") would be read from the working folder: point them at the skin's
		string data = css;
		try {
			data = /url\(\s*(["']?)(?![a-z]+:)([^"')]+)\1\s*\)/.replace (css, -1, 0, "url(\"%s/\\2\")".printf (skin.css.get_parent ().get_uri ()));
		} catch (RegexError err) {}
		string? first = null;
		ulong handler = provider.parsing_error.connect ((section, err) => {
			if (first == null)
				first = _("Line %u: %s").printf (section.get_start_line () + 1, err.message);
		});
		try {
			provider.load_from_data (data);
		} catch (Error err) {
			if (first == null)
				first = err.message;
		}
		provider.disconnect (handler);
		return first;
	}

	/** Saves css as the skin's: in place for a user skin, else as a new user skin
	 * "<name> (edited)" next to it. Returns the id of the skin saved. */
	public string save_css (Skin skin, string css) throws Error {
		var folder = skin.css.get_parent ();
		string id = skin.id;
		if (!is_user (skin)) {
			id = skin.id + "-edited";
			for (int n = 2; FileUtils.test (Path.build_filename (user_dir (), id), FileTest.EXISTS); n++)
				id = "%s-edited-%d".printf (skin.id, n); // never over an earlier copy
			var ini = new KeyFile ();
			try {
				uint8[] data;
				folder.get_child ("skin.ini").load_contents (null, out data, null);
				ini.load_from_data ((string)data, data.length, KeyFileFlags.NONE);
				foreach (var key in ini.get_keys ("Skin"))
					if (key.has_prefix ("Name["))
						ini.remove_key ("Skin", key);
			} catch (Error err) {} // a skin may have no skin.ini
			ini.set_string ("Skin", "Name", _("%s (edited)").printf (skin.name));
			folder = File.new_for_path (Path.build_filename (user_dir (), id));
			DirUtils.create_with_parents (folder.get_path (), 0755);
			FileUtils.set_contents (Path.build_filename (folder.get_path (), "skin.ini"), ini.to_data ());
		}
		FileUtils.set_contents (Path.build_filename (folder.get_path (), "skin.css"), css);
		return id;
	}

	/** Apply a skin: a native one replaces the built-in look, any other is laid over it.
	 * "" (never chosen) is the default skin; an unknown one leaves the built-in look alone. */
	public void apply (string id) {
		if (id == "" || id == "native") // Native was Adwaita under another name
			id = DEFAULT;
		var screen = Gdk.Screen.get_default ();
		var gtk = Gtk.Settings.get_default ();
		if (system_theme == null) {
			system_theme = gtk.gtk_theme_name;
			system_dark = gtk.gtk_application_prefer_dark_theme;
		}
		if (provider != null)
			Gtk.StyleContext.remove_provider_for_screen (screen, provider);
		provider = null;
		if (base_look == null) {
			base_look = new Gtk.CssProvider ();
			base_look.load_from_resource ("/net/launchpad/beatbox/theme.css");
		}
		Skin? found = null;
		foreach (var skin in available ())
			if (skin.id == id)
				found = skin;
		Gtk.StyleContext.remove_provider_for_screen (screen, base_look);
		if (found == null || !found.native)
			Gtk.StyleContext.add_provider_for_screen (screen, base_look, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
		string theme = (found != null && found.theme != null) ? found.theme : system_theme;
		if (gtk.gtk_theme_name != theme)
			gtk.gtk_theme_name = theme;
		gtk.gtk_application_prefer_dark_theme = (found != null && found.dark) || system_dark;
		square_menu_icon = found != null && found.square_icon;

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
