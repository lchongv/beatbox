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
	
	const int LOGO = 128;
	FlowBox grid;
	HashMap<string, Gdk.Pixbuf> logos = new HashMap<string, Gdk.Pixbuf>(); // scaled, by stream address
	
	public StationSourceView() {
		base(App.library.station_library.medias(), App.window.setups.get_setup(ListSetupInterface.STATION_KEY));
		
		media_representation = _("station");
		
		// Setup welcome screen
		welcome_screen = new Welcome(_("Turn up the Radio"), _("No Stations were found."));
		welcome_screen_keys = new HashMap<int, Device>();
		var station_icon = App.icons.STATION.render (null, null, 48);
		welcome_screen.append_with_pixbuf(station_icon, _("Find Stations"), _("Search thousands of stations on radio-browser.info, SHOUTcast, laut.fm and Icecast."));
		welcome_screen.append("list-add", _("Add by Address"), _("Type the address of a station's stream."));
		welcome_screen.append("document-open", _("Import File"), _("Add the stations of a .pls or .m3u file."));
		welcome_screen.activated.connect(welcome_screen_activated);
		
		// Setup content widgets
		list_view = new RadioList(tvs);
		error_box = new EmbeddedAlert();
		
		// The grid: each station's logo and name, in the list's order and search
		grid = new FlowBox();
		grid.get_style_context().add_class("albumwall"); // the album grid's look
		grid.homogeneous = true;
		grid.valign = Align.START;
		grid.max_children_per_line = 64;
		grid.row_spacing = grid.column_spacing = 12;
		grid.margin_top = grid.margin_bottom = grid.margin_start = grid.margin_end = 18;
		grid.activate_on_single_click = false;
		grid.child_activated.connect((child) => play_row(child.get_index()));
		var grid_press = new GestureClick();
		grid_press.button = 3;
		grid_press.pressed.connect((n_press, x, y) => grid_clicked(x, y));
		grid.add_controller(grid_press);
		var grid_scroll = new ScrolledWindow();
		grid_scroll.hscrollbar_policy = PolicyType.NEVER;
		grid_scroll.get_style_context().add_class("albumwall");
		grid_scroll.set_child(grid);
		grid_page = AquaScroll.wrap(grid_scroll);
		list_view.visible_changed.connect(fill_grid);
		StationLogos.get_default().found.connect((uri) => { logos.unset(uri); fill_grid(); });
		StreamRecorder.get_default().changed.connect(() => fill_grid());
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
	
	void fill_grid() {
		UI.clear (grid);
		var table = list_view.get_visible_table();
		for (int i = 0; i < table.size(); i++) {
			var m = table.get(i);
			var box = new Box(Orientation.VERTICAL, 2);
			box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 6;
			box.tooltip_text = m.title;
			var logo = new Image();
			UI.show_pixbuf(logo, logo_for(m));
			box.append(logo);
			var name = new Label(m.title);
			name.ellipsize = Pango.EllipsizeMode.END;
			name.max_width_chars = 16;
			name.margin_top = 4;
			name.get_style_context().add_class("station-name");
			box.append(name);
			var genre = new Label(m.genre);
			genre.ellipsize = Pango.EllipsizeMode.END;
			genre.max_width_chars = 16;
			genre.get_style_context().add_class("dim-label");
			box.append(genre);
			if (StreamRecorder.get_default().is_recording(m.uri)) {
				var rec = new Label(null);
				rec.set_markup("<span foreground=\"#d33\" weight=\"bold\">● " + _("REC") + "</span>");
				box.append(rec);
			}
			grid.append(box);
		}
	}
	
	/** Right click on a station: choose its own image, or go back to the directory's */
	void grid_clicked(double x, double y) {
		var child = grid.get_child_at_pos((int)x, (int)y);
		var table = list_view.get_visible_table();
		if (child == null || child.get_index() >= table.size())
			return;
		var m = table.get(child.get_index());
		var logos = StationLogos.get_default();
		var menu = new PopMenu();
		var choose = new PopMenuItem.with_label(_("Choose Image…"));
		choose.clicked.connect(() => choose_logo.begin(m));
		menu.append(choose);
		var recorder = StreamRecorder.get_default();
		var record = new PopMenuItem.with_label(recorder.is_recording(m.uri) ? _("Stop Recording") : _("Record"));
		if (recorder.is_recording(m.uri))
			record.clicked.connect(() => recorder.stop(m.uri));
		else if (recorder.available())
			record.clicked.connect(() => {
				var folder = Path.build_filename(App.settings.main.recordings_path(), StreamRecorder.safe_name(m.title));
				if (!recorder.start(m.uri, folder, App.settings.main.recording_minutes * 60))
					App.window.doAlert(_("Could not record “%s”").printf(m.title), _("streamripper did not start."));
			});
		else {
			record.sensitive = false;
			record.tooltip_text = _("Needs streamripper (the streamripper package)");
		}
		menu.append(record);
		if (logos.has_custom(m.uri)) {
			var remove = new PopMenuItem.with_label(_("Remove Custom Image"));
			remove.clicked.connect(() => logos.clear_custom(m.uri));
			menu.append(remove);
		}
		menu.popup_at(grid, x, y);
	}
	
	async void choose_logo(Media m) {
		var chooser = new Gtk.FileChooserDialog(_("Image for “%s”").printf(m.title), App.window, Gtk.FileChooserAction.OPEN,
		                                       _("Cancel"), Gtk.ResponseType.CANCEL, _("Choose"), Gtk.ResponseType.ACCEPT);
		var images = new Gtk.FileFilter();
		images.set_filter_name(_("Images"));
		images.add_pixbuf_formats();
		chooser.add_filter(images);
		if ((yield UI.run_dialog (chooser)) == Gtk.ResponseType.ACCEPT) {
			var file = chooser.get_file();
			if (!StationLogos.get_default().set_custom(m.uri, file)) {
				var error = new Gtk.MessageDialog(App.window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE,
				                                  _("“%s” is not an image BeatBox can read."), file.get_basename());
				yield UI.run_dialog (error);
				error.destroy();
			}
		}
		chooser.destroy();
	}
	
	/** The station's logo scaled into a LOGO square, or a generic radio */
	Gdk.Pixbuf? logo_for(Media m) {
		var logo = logos.get(m.uri);
		if (logo != null)
			return logo;
		logo = StationLogos.get_default().lookup(m);
		if (logo == null)
			return StationLogos.generic(LOGO); // not kept: the real one may still come
		double k = double.min((double)LOGO / logo.width, (double)LOGO / logo.height);
		logo = logo.scale_simple(int.max(1, (int)(logo.width * k)), int.max(1, (int)(logo.height * k)), Gdk.InterpType.BILINEAR);
		logos.set(m.uri, logo);
		return logo;
	}
	
	protected override void pre_set_as_current_view() {
		
	}
	
	protected override void set_default_warning () {
		error_box.set_alert (_("No Internet Radio Stations Found"), _("Use “Find Stations…” above to search the radio-browser.info, SHOUTcast, laut.fm and Icecast directories."), true, Gtk.MessageType.INFO);
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
		return App.icons.STATION.render(null, null);
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
	
	public override void drag_received(string[] uris) {
		
	}
	
	public override SideTreeCategory get_sidetree_category() {
		return SideTreeCategory.NETWORK;
	}
}
