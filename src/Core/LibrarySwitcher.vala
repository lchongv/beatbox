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
		((Gtk.Window) App.window).destroy ();
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
