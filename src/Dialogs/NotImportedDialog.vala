/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originaly Written by Scott Ringwelski for BeatBox Music Player
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

public class BeatBox.NotImportedDialog : Window{
	Collection<string> _files;
	string music_folder;
	
	//for padding around notebook mostly
	private Box content;
	private Box padding;
	
	CheckButton trashAll;
	ScrolledWindow filesScroll;
	SimpleTable files_table; // a check box and the path of each file
	Button moveToTrash;
	
	public NotImportedDialog(Collection<string> files, string music) {
		if(files == null || files.size == 0)
			return;
		
		_files = files;
		this.music_folder = music;
		
		this.set_title(_("Not Imported Files"));
		
		// set the size based on saved gconf settings
		//this.window_position = WindowPosition.CENTER;
		this.set_modal(true);
		this.set_transient_for(App.window);
		this.destroy_with_parent = true;
		
		set_default_size(475, -1);
		resizable = false;
		
		content = new Box(Orientation.VERTICAL, 10);
		padding = new Box(Orientation.HORIZONTAL, 20);
		
		// initialize controls
		Image warning = new Image.from_icon_name("dialog-error");
		warning.pixel_size = 48;
		Label title = new Label("");
		Label info = new Label(ngettext("BeatBox could not read it. It may be damaged or not be audio.", "BeatBox could not read them. They may be damaged or not be audio.", files.size));
		trashAll = new CheckButton.with_label(_("Move all corrupted files to trash"));
		filesScroll = new ScrolledWindow();
		files_table = new SimpleTable();
		moveToTrash = new Button.with_label(_("Move to Trash"));
		Button okButton = new Button.with_label(_("Ignore"));
		
		// pretty up labels
		title.xalign = 0.0f;
		string TITLE_TEXT = ngettext("Could not import %d file", "Could not import %d files", files.size).printf(files.size);
		title.set_markup(("<span weight=\"bold\" size=\"larger\">%s</span>").printf(TITLE_TEXT));
		info.xalign = 0.0f;
		info.wrap = false;
		
		/* a check box column and the files */
		files_table.add_check_column(null);
		files_table.add_column(_("File Location"), 0);
		files_table.headers_visible = false;
		files_table.check_toggled.connect(() => update_move_to_trash());
		
		foreach(string file in files)
			files_table.add({ file.replace(music_folder, "") });
		
		filesScroll.set_child(files_table.view);
		filesScroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		
		moveToTrash.set_sensitive(false);
		
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
		
		Box listBox = new Box(Orientation.VERTICAL, 0);
		filesScroll.vexpand = true;
		filesScroll.margin_top = filesScroll.margin_bottom = 5;
		listBox.append(AquaScroll.wrap(filesScroll));
		
		Expander exp = new Expander(_("Select individual files to move to trash:"));
		exp.set_child(listBox);
		exp.expanded = false;
		
		var bottomButtons = new Box(Orientation.HORIZONTAL, 6);
		bottomButtons.halign = Gtk.Align.END;
		bottomButtons.append(moveToTrash);
		bottomButtons.append(okButton);
		bottomButtons.set_spacing(6);
		
		content.append(information);
		content.append(wrap_alignment(trashAll, 5, 0, 0, 75));
		exp.vexpand = true;
		content.append(wrap_alignment(exp, 0, 0, 0, 75));
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.append(bottomButtons);
		
		content.hexpand = true;
		content.margin_start = content.margin_end = 10;
		padding.append(content);
		
		moveToTrash.clicked.connect(moveToTrashClick);
		trashAll.toggled.connect(trashAllToggled);
		okButton.clicked.connect( () => { this.destroy(); });
		exp.activate.connect( () => {
			if(exp.get_expanded()) {
				resizable = true;
				set_size_request(475, 180);
				set_default_size(475, 180);
				resizable = false;
			}
			else
				set_size_request(475, 350);
		});
		
		set_child(padding);
		present();
	}
	
	public static Gtk.Widget wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
		// padding as extra margins (Gtk.Alignment is deprecated)
		widget.margin_top += top;
		widget.margin_end += right;
		widget.margin_bottom += bottom;
		widget.margin_start += left;
		return widget;
	}
	
	/** Move to Trash only with some file ticked */
	void update_move_to_trash() {
		bool any = false;
		for(uint i = 0; i < files_table.size; i++)
			any = any || files_table.get_row(i).checked;
		moveToTrash.set_sensitive(any);
	}
	
	void check_all(bool val) {
		for(uint i = 0; i < files_table.size; i++)
			files_table.get_row(i).checked = val;
		files_table.rows.items_changed(0, files_table.size, files_table.size);
	}
	
	 void trashAllToggled() {
		check_all(trashAll.active);
		files_table.view.set_sensitive(!trashAll.active);
		moveToTrash.set_sensitive(trashAll.active);
	}
	
	 void moveToTrashClick() {
		for(uint i = 0; i < files_table.size; i++) {
			var row = files_table.get_row(i);
			if(!row.checked)
				continue;
			string location = row.cells[0];
			try {
				var file = File.new_for_path(music_folder + location);
				file.trash();
			}
			catch(GLib.Error err) {
				stdout.printf("Could not move file %s to recycle: %s\n", location, err.message);
			}
		}
		this.destroy();
	}
}
