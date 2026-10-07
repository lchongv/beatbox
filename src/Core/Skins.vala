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
