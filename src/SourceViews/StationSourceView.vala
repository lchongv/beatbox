/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 * 
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 */

using Gee;
using Gtk;

public class BeatBox.StationSourceView : SourceView {
	HashMap<int, Device> welcome_screen_keys;
	
	GLib.Menu radioMenu;
	
	public StationSourceView() {
		base(App.library.station_library.medias(), App.window.setups.get_setup(ListSetupInterface.STATION_KEY));
		
		media_representation = _("station");
		
		// Setup welcome screen
		welcome_screen = new Welcome(_("Turn up the Radio"), _("No Stations were found."));
		welcome_screen_keys = new HashMap<int, Device>();
		var station_icon = App.icons.STATION.render (IconSize.DIALOG, null);
		welcome_screen.append_with_pixbuf(station_icon, _("Find Stations"), _("Search thousands of stations on radio-browser.info."));
		welcome_screen.append("list-add", _("Add by Address"), _("Type the address of a station's stream."));
		welcome_screen.append("document-open", _("Import File"), _("Add the stations of a .pls or .m3u file."));
		welcome_screen.activated.connect(welcome_screen_activated);
		
		// Setup content widgets
		list_view = new RadioList(tvs);
		error_box = new EmbeddedAlert();
		pack_widgets();
		
		var find = action_button ("system-search-symbolic", _("Find Stations…"));
		var add = action_button ("list-add-symbolic", _("Add by Address…"));
		var import = action_button ("document-open-symbolic", _("Import File…"));
		find.clicked.connect (() => { new DirectoryDialog (DirectoryDialog.Kind.RADIO); });
		add.clicked.connect (() => { DirectoryDialog.add_station_by_url (); });
		import.clicked.connect (() => { App.actions.import_station.activate(null); });
		pack_action_bar ({ find, add, import });
		
		// Setup context menu
		radioMenu = new GLib.Menu();
		radioMenu.append(_("Find Stations…"), "view.find");
		add_context_action("find", () => { new DirectoryDialog (DirectoryDialog.Kind.RADIO); });
		radioMenu.append(_("Add by Address…"), "view.add-address");
		add_context_action("add-address", () => { DirectoryDialog.add_station_by_url (); });
		radioMenu.append_item(App.actions.model_item(App.actions.import_station));
		
		// Populate views
		set_media_sync(original_medias, false);
		
		// Setup signal handlers
		App.library.station_library.medias_updated.connect (update_medias);
		App.library.station_library.medias_added.connect (add_medias);
		App.library.station_library.medias_removed.connect (remove_medias);
	}
	
	protected override void pre_set_as_current_view() {
		
	}
	
	protected override void set_default_warning () {
		error_box.set_alert (_("No Internet Radio Stations Found"), _("Use “Find Stations…” above to search the radio-browser.info directory."), true, Gtk.MessageType.INFO);
	}
	
	void welcome_screen_activated(int index) {
		if(index == 0)
			new DirectoryDialog (DirectoryDialog.Kind.RADIO);
		else if(index == 1)
			DirectoryDialog.add_station_by_url ();
		else
			App.actions.import_station.activate(null);
	}
	
	/** Specific implementations for View interface **/
	public override View.ViewType get_view_type() {
		return View.ViewType.STATION;
	}
	
	public override Object? get_object() {
		return null;
	}
	
	public override Gdk.Pixbuf get_view_icon() {
		return App.icons.STATION.render(IconSize.MENU, null);
	}
	
	public override string get_view_name() {
		return _("Internet Radio");
	}
	
	public override GLib.MenuModel? get_context_menu() {
		return radioMenu;
	}
	
	public override bool can_receive_drop() {
		return false;
	}
	
	public override void drag_received(Gtk.SelectionData data) {
		
	}
	
	public override SideTreeCategory get_sidetree_category() {
		return SideTreeCategory.NETWORK;
	}
}
