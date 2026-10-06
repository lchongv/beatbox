/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/** A plugin found on disk (see core/Plugin.vala and docs/plugins.md for the layout) */
public class BeatBox.PluginInfo : Object {
	public string id;
	public string name;
	public string description;
	public string folder;      // where its .plugin file is
	public string? loader;     // "python" for Python plugins, null for native ones
	public Plugin? instance;   // once loaded
	public bool active;

	public bool is_python { get { return loader != null && loader.has_prefix("python"); } }

	/** The code next to the .plugin file: lib<id>.so, or <id>.py / the <id> package */
	public string code_path() {
		if(!is_python)
			return Path.build_filename(folder, "lib" + id + (Exe.UNIX ? ".so" : ".dll"));
		var package = Path.build_filename(folder, id);
		return FileUtils.test(package, FileTest.IS_DIR) ? package : package + ".py";
	}
}

/** Finds the plugins, loads the ones turned on and turns them on and off.
 * Native plugins are loaded with GModule; Python ones through libpeas, when
 * BeatBox was built with it (-Dpython). */
public class BeatBox.PluginManager : Object {
	[CCode (has_target = false)]
	delegate Plugin CreateFunc();

	public Gee.List<PluginInfo> plugins = new Gee.ArrayList<PluginInfo>();
	PluginHost host;
#if HAVE_PEAS
	Peas.Engine? peas = null;
#endif

	public PluginManager(PluginHost host) {
		this.host = host;
		foreach(var folder in folders())
			scan(folder);
		foreach(var p in plugins)
			if(p.id in App.settings.main.enabled_plugins)
				activate(p);
	}

	/** Whether this build can run plugins written in Python */
	public static bool python_supported {
		get {
#if HAVE_PEAS
			return true;
#else
			return false;
#endif
		}
	}

	/** The user's first (so a copy there wins), then next to the program (the build
	 * tree, an AppImage or a portable bundle), then where meson installed them */
	static string[] folders() {
		string[] rv = { Path.build_filename(Environment.get_user_data_dir(), "beatbox", "plugins") };
		var exe_dir = Exe.dir();
		if(exe_dir != null) {
			rv += Path.build_filename(exe_dir, "plugins");
			rv += Path.build_filename(Path.get_dirname(exe_dir), Build.PLUGIN_SUBDIR);
		}
		rv += Build.PLUGIN_DIR;
		return rv;
	}

	/** Where Python finds BeatBox's typelib (the description of libbeatbox-core):
	 * the build tree, next to the program, or where meson installed it.
	 * Must run before anything loads Python. */
	public static void set_typelib_path() {
		string[] dirs = {};
		var exe_dir = Exe.dir();
		if(exe_dir != null) {
			dirs += exe_dir; // the build tree
			dirs += Path.build_filename(Path.get_dirname(exe_dir), Build.TYPELIB_SUBDIR);
		}
		dirs += Build.TYPELIB_DIR;
		var old = Environment.get_variable("GI_TYPELIB_PATH");
		if(old != null && old != "")
			dirs += old;
		Environment.set_variable("GI_TYPELIB_PATH", string.joinv(Path.SEARCHPATH_SEPARATOR_S, dirs), true);
	}

	void scan(string folder) {
		Dir dir;
		try {
			dir = Dir.open(folder);
		} catch (FileError err) {
			return; // no such folder
		}
		for(string? sub = dir.read_name(); sub != null; sub = dir.read_name()) {
			var info_file = Path.build_filename(folder, sub, sub + ".plugin");
			if(!FileUtils.test(info_file, FileTest.EXISTS))
				continue;
			try {
				var p = read_info(info_file);
				if(p.is_python && !python_supported)
					message("Skipping the Python plugin %s: this build has no Python support", p.id);
				else if(!plugins.any_match((other) => other.id == p.id)) // else found in a folder that comes first
					plugins.add(p);
			} catch (Error err) {
				warning("Ignoring the plugin %s: %s", info_file, err.message);
			}
		}
	}

	static PluginInfo read_info(string info_file) throws Error {
		var kf = new KeyFile();
		kf.load_from_file(info_file, KeyFileFlags.NONE);
		var p = new PluginInfo();
		p.id = kf.get_string("Plugin", "Module");
		if(p.id == "" || "/" in p.id || p.id.has_prefix("."))
			throw new KeyFileError.INVALID_VALUE(_("“%s” is not a valid plugin id").printf(p.id));
		p.name = kf.get_locale_string("Plugin", "Name");
		p.description = kf.has_key("Plugin", "Description") ? kf.get_locale_string("Plugin", "Description") : "";
		p.loader = kf.has_key("Plugin", "Loader") ? kf.get_string("Plugin", "Loader") : null;
		p.folder = Path.get_dirname(info_file);
		return p;
	}

	/** Copies a plugin (the chosen .plugin file and its code next to it) into the
	 * user's plugins folder. Returns the new entry, or null when a plugin with the same
	 * id is already loaded: its code can't be swapped, so the copy is used after a restart. */
	public PluginInfo? install(File info_file) throws Error {
		var p = read_info(info_file.get_path());
		if(p.is_python && !python_supported)
			throw new IOError.NOT_SUPPORTED(_("This copy of BeatBox can't run plugins written in Python."));
		var code = File.new_for_path(p.code_path());
		if(!code.query_exists())
			throw new IOError.NOT_FOUND(_("%s is missing next to %s").printf(code.get_basename(), info_file.get_basename()));

		var dest = File.new_for_path(Path.build_filename(Environment.get_user_data_dir(), "beatbox", "plugins", p.id));
		DirUtils.create_with_parents(dest.get_path(), 0755);
		var dest_info = dest.get_child(p.id + ".plugin");
		if(!info_file.equal(dest_info)) {
			info_file.copy(dest_info, FileCopyFlags.OVERWRITE);
			copy_tree(code, dest.get_child(code.get_basename()));
		}
		p.folder = dest.get_path();

		foreach(var other in plugins) {
			if(other.id != p.id)
				continue;
			if(other.instance != null)
				return null;
			plugins.remove(other); // not loaded yet: the new copy takes its place
			break;
		}
		plugins.add(p);
		return p;
	}

	/** A file, or a folder with everything in it (a Python package) */
	static void copy_tree(File from, File to) throws Error {
		if(from.query_file_type(FileQueryInfoFlags.NONE) != FileType.DIRECTORY) {
			from.copy(to, FileCopyFlags.OVERWRITE);
			return;
		}
		if(!to.query_exists())
			to.make_directory();
		var children = from.enumerate_children(FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
		FileInfo info;
		while((info = children.next_file()) != null)
			if(info.get_name() != "__pycache__")
				copy_tree(from.get_child(info.get_name()), to.get_child(info.get_name()));
	}

	bool load(PluginInfo p) {
		if(p.is_python)
			return load_python(p);
		var module = Module.open(p.code_path(), ModuleFlags.LAZY);
		void* create = null;
		if(module == null || !module.symbol("beatbox_plugin_create", out create)) {
			warning("Could not load the plugin %s: %s", p.id, Module.error());
			return false;
		}
		module.make_resident(); // its types stay registered: it can't go away
		p.instance = ((CreateFunc)create)();
		return true;
	}

	bool load_python(PluginInfo p) {
#if HAVE_PEAS
		if(peas == null) {
			peas = Peas.Engine.get_default();
			peas.enable_loader("python");
		}
		peas.add_search_path(p.folder, null);
		unowned Peas.PluginInfo? info = peas.get_plugin_info(p.id);
		if(info == null) {
			warning("Could not load the plugin %s: libpeas didn't find it in %s", p.id, p.folder);
			return false;
		}
		peas.load_plugin(info);
		if(!info.is_loaded()) {
			try {
				info.is_available();
				warning("Could not load the plugin %s", p.id);
			} catch (Error err) {
				warning("Could not load the plugin %s: %s", p.id, err.message);
			}
			return false;
		}
		if(!peas.provides_extension(info, typeof(Plugin))) {
			warning("The plugin %s has no class implementing BeatBox.Plugin", p.id);
			return false;
		}
		p.instance = (Plugin)peas.create_extension_with_properties(info, typeof(Plugin), {}, {});
		return p.instance != null;
#else
		return false;
#endif
	}

	void activate(PluginInfo p) {
		if(p.active || (p.instance == null && !load(p)))
			return;
		p.instance.activate(host);
		p.active = true;
	}

	public void set_enabled(PluginInfo p, bool enabled) {
		if(enabled) {
			activate(p);
		} else if(p.active) {
			p.instance.deactivate();
			p.active = false;
		}

		string[] ids = {};
		foreach(var other in plugins)
			if(other.active)
				ids += other.id;
		App.settings.main.enabled_plugins = ids;
	}
}
