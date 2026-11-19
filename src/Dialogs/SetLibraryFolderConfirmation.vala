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

using Gtk;
using Gee;

public class BeatBox.SetLibraryFolderConfirmation : Window {
	Library lib;
	File folder;
	
	Box content;
	Box padding;
	
	Button savePlaylists;
	Button ok;
	Button cancel;
	
	Gtk.Image is_finished;
	Gtk.Spinner is_working;
	
	public signal void finished(bool response);
	
	public SetLibraryFolderConfirmation(Library lib, File folder) {
		this.lib = lib;
		this.folder = folder;
		
		this.set_title("BeatBox");
		
		// set the size based on saved gconf settings
		//this.window_position = WindowPosition.CENTER;
		this.set_modal(true);
		this.set_transient_for(App.window);
		this.destroy_with_parent = true;
		
		//set_default_size(250, -1);
		resizable = false;
		
		content = new Box(Orientation.VERTICAL, 10);
		padding = new Box(Orientation.HORIZONTAL, 10);
		
		// initialize controls
		Image warning = new Image.from_icon_name("dialog-warning");
		warning.pixel_size = 48;
		Label title = new Label("");
		Label info = new Label("");
		savePlaylists = new Button.with_label(_("Export Playlists"));
		ok = new Button.with_label(_("Set %s Folder").printf(lib.name));
		cancel = new Button.with_mnemonic (_("_Cancel"));
		is_finished = new Gtk.Image();
		is_working = new Gtk.Spinner();
		
		// pretty up labels
		title.xalign = 0.0f;
		title.set_markup("<span weight=\"bold\" size=\"larger\">%s</span>".printf(_("Set %s Folder?").printf(lib.name)));
		info.xalign = 0.0f;
		info.wrap = true;
		info.set_markup(_("Are you sure you want to set the %s folder to %s? This will reset your %s library.").printf("<b>" + lib.name + "</b>", "<b>" + Markup.escape_text(folder.get_path()) + "</b>", lib.name));
		
		/* set up controls layout */
		Box information = new Box(Orientation.HORIZONTAL, 0);
		Box information_text = new Box(Orientation.VERTICAL, 0);
		warning.margin_start = warning.margin_end = 10;
		information.append(warning);
		title.margin_top = title.margin_bottom = 10;
		information_text.append(title);
		information_text.append(info);
		information_text.hexpand = true;
		information_text.margin_start = information_text.margin_end = 10;
		information.append(information_text);
		
		// save playlist hbox
		Box playlistBox = new Box(Orientation.HORIZONTAL, 6);
		savePlaylists.hexpand = true;
		playlistBox.append(savePlaylists);
		playlistBox.append(is_working);
		playlistBox.append(is_finished);
		
		var bottomButtons = new Box(Orientation.HORIZONTAL, 6);
		playlistBox.hexpand = true;
		bottomButtons.append(playlistBox);
		bottomButtons.append(cancel);
		bottomButtons.append(ok);
		bottomButtons.set_spacing(6);
		
		content.append(information);
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.append(bottomButtons);
		
		content.hexpand = true;
		content.margin_start = content.margin_end = 10;
		padding.append(content);
		
		savePlaylists.set_sensitive(App.library.media_count() > 0 && App.playlists.playlist_count() > 0);
		
		savePlaylists.clicked.connect( () => savePlaylistsClicked.begin () );
		cancel.clicked.connect(cancel_clicked);
		ok.clicked.connect(ok_clicked);
		
		set_child(padding);
		present();
		
		is_working.visible = false;
	}
	
	public async void savePlaylistsClicked() {
		string folder = "";
		var chosen = yield UI.choose_folder (this, _("Choose Music Folder"));
		if (chosen != null && chosen.get_path() != null)
			folder = chosen.get_path();
		
		if(folder != "") {
			is_working.visible = true;
			is_finished.visible = false;
			
			// foreach playlist in App.library.playlists(), save to (p.name).m3u
			var success = true;
			foreach(var p in App.playlists.playlists()) {
				if(p is StaticPlaylist) {
					if(!PlaylistUtils.save_playlist_m3u((StaticPlaylist)p, folder)) {
						success = false;
					}
				}
			}
			
			is_working.visible = false;
			is_finished.visible = true;
			
			var process_completed_icon = App.icons.PROCESS_COMPLETED.render (null);
			var process_error_icon = App.icons.PROCESS_ERROR.render (null);
			
			UI.show_pixbuf (is_finished, success ? process_completed_icon : process_error_icon);
		}
	}
	
	public void cancel_clicked() {
		finished(false);
		
		this.destroy();
	}
	
	public void ok_clicked() {
		finished(true);
		
		this.destroy();
	}
}
