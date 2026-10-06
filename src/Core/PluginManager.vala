/*-
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

/** A plugin found on disk (see core/Plugin.vala for the layout) */
public class BeatBox.PluginInfo : Object {
	public string id;
	public string name;
	public string description;
	public string library;     // path of lib<id>.so
	public Plugin? instance;   // once loaded
	public bool active;
}

/** Finds the plugins, loads the ones turned on and turns them on and off */
public class BeatBox.PluginManager : Object {
	[CCode (has_target = false)]
	delegate Plugin CreateFunc();

	public Gee.List<PluginInfo> plugins = new Gee.ArrayList<PluginInfo>();
	PluginHost host;

	public PluginManager(PluginHost host) {
		this.host = host;
		foreach(var folder in folders())
			scan(folder);
		foreach(var p in plugins)
			if(p.id in App.settings.main.enabled_plugins)
				activate(p);
	}

	/** The user's first (so a copy there wins), then next to the program (the build
	 * tree, an AppImage or a portable bundle), then where meson installed them */
	static string[] folders() {
		string[] rv = { Path.build_filename(Environment.get_user_data_dir(), "beatbox", "plugins") };
		try {
			var exe_dir = Path.get_dirname(FileUtils.read_link("/proc/self/exe"));
			rv += Path.build_filename(exe_dir, "plugins");
			rv += Path.build_filename(Path.get_dirname(exe_dir), Build.PLUGIN_SUBDIR);
		} catch (FileError err) {}
		rv += Build.PLUGIN_DIR;
		return rv;
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
				var kf = new KeyFile();
				kf.load_from_file(info_file, KeyFileFlags.NONE);
				var p = new PluginInfo();
				p.id = kf.get_string("Plugin", "Module");
				if(plugins.any_match((other) => other.id == p.id))
					continue; // already found in a folder that comes first
				p.name = kf.get_locale_string("Plugin", "Name");
				p.description = kf.has_key("Plugin", "Description") ? kf.get_locale_string("Plugin", "Description") : "";
				p.library = Path.build_filename(folder, sub, "lib" + p.id + "." + Module.SUFFIX);
				plugins.add(p);
			} catch (Error err) {
				warning("Ignoring the plugin %s: %s", info_file, err.message);
			}
		}
	}

	bool load(PluginInfo p) {
		var module = Module.open(p.library, ModuleFlags.LAZY);
		void* create = null;
		if(module == null || !module.symbol("beatbox_plugin_create", out create)) {
			warning("Could not load the plugin %s: %s", p.id, Module.error());
			return false;
		}
		module.make_resident(); // its types stay registered: it can't go away
		p.instance = ((CreateFunc)create)();
		return true;
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
