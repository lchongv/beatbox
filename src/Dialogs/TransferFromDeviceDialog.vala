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

public class BeatBox.TransferFromDeviceDialog : Window {
	LinkedList<Media> medias;
	Device d;
	
	//for padding around notebook mostly
	private Box content;
	private Box padding;
	
	CheckButton transferAll;
	ScrolledWindow mediasScroll;
	SimpleTable medias_table; // check box, title, artist, album; the row's data is its Media
	Button transfer;
	
	LinkedList<Media> to_transfer;
	
	// TODO: Enable/disable sensitize based on operations
	public TransferFromDeviceDialog(Device d, LinkedList<Media> medias) {
		this.medias = medias;
		this.d = d;
		
		to_transfer = new LinkedList<Media>();
		
		this.set_title(_("Import from Device"));
		
		// set the size based on saved gconf settings
		//this.window_position = WindowPosition.CENTER;
		this.set_modal(true);
		this.set_transient_for(App.window);
		this.destroy_with_parent = true;
		
		set_default_size(550, -1);
		resizable = false;
		
		content = new Box(Orientation.VERTICAL, 10);
		padding = new Box(Orientation.HORIZONTAL, 20);
		
		// initialize controls
		Image warning = new Image.from_icon_name("dialog-question");
		warning.pixel_size = 48;
		Label title = new Label(_("Import medias from") + " " + d.getDisplayName());
		Label info = new Label(_("The following files were found on %s, but are not in your library. Check all files you would like to import.").printf(d.getDisplayName()));
		transferAll = new CheckButton.with_label(_("Import all medias"));
		mediasScroll = new ScrolledWindow();
		medias_table = new SimpleTable();
		transfer = new Button.with_label(_("Import"));
		Button cancel = new Button.with_label(_("Don't Import"));
		
		// pretty up labels
		string title_text = "";
		if(medias.size == 1)
			title_text = _("Import %s from %s").printf(medias.get(0).title, Markup.escape_text(d.getDisplayName()));
		else
			title_text = _("Import %d medias from %s").printf(medias.size, Markup.escape_text(d.getDisplayName()));
		
		title.set_markup("<span weight=\"bold\" size=\"larger\">" + title_text + "</span>");
		title.xalign = 0.0f;
		info.xalign = 0.0f;
		info.wrap = true;
		
		/* a check box, then title, artist and album */
		medias_table.add_check_column("");
		medias_table.add_column(_("Title"), 0).fixed_width = 300;
		medias_table.add_column(_("Artist"), 1).fixed_width = 125;
		medias_table.add_column(_("Album"), 2).fixed_width = 125;
		medias_table.check_toggled.connect(() => update_transfer());
		
		foreach(var m in medias)
			medias_table.add({ m.title, m.artist, m.album }, m);
		
		mediasScroll.set_child(medias_table.view);
		mediasScroll.set_policy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		
		transfer.set_sensitive(false);
		
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
		mediasScroll.vexpand = true;
		mediasScroll.margin_top = mediasScroll.margin_bottom = 5;
		listBox.append(AquaScroll.wrap(mediasScroll));
		
		Expander exp = new Expander(_("Select individual medias to import:"));
		exp.set_child(listBox);
		exp.expanded = false;
		
		var bottomButtons = new Box(Orientation.HORIZONTAL, 6);
		bottomButtons.halign = Gtk.Align.END;
		bottomButtons.append(cancel);
		bottomButtons.append(transfer);
		bottomButtons.set_spacing(6);
		
		content.append(information);
		content.append(UI.wrap_alignment(transferAll, 5, 0, 0, 75));
		exp.vexpand = true;
		content.append(UI.wrap_alignment(exp, 0, 0, 0, 75));
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.append(bottomButtons);
		
		content.hexpand = true;
		content.margin_start = content.margin_end = 10;
		padding.append(content);
		
		transfer.clicked.connect(transferClick);
		transferAll.toggled.connect(transferAllToggled);
		//mediasView.button_press_event.connect(mediasViewClick);
		cancel.clicked.connect( () => { destroy(); });
		exp.activate.connect( () => {
			if(exp.get_expanded()) {
				resizable = true;
				set_size_request(550, 180);
				set_default_size(475, 180);
				resizable = false;
			}
			else
				set_size_request(550, 500);
		});
		
		set_child(padding);
		present();
		
		App.operations.operation_started.connect(operation_started);
		App.operations.operation_finished.connect(operation_finished);
		transfer.set_sensitive(!App.operations.doing_ops);
	}
	
	/*public static int mediaCompareFunc(Media a, Media b) {
		if(a.artist == b.artist) {
			if(a.album == b.album)
				return (int)a.track - (int)b.track;
			else
				return (a.album > b.album) ? 1 : -1;
			
		}
		else
			return (a.artist > b.artist) ? 1 : -1;
	}*/
	
	/** Import only with some song ticked */
	void update_transfer() {
		bool any = false;
		for(uint i = 0; i < medias_table.size; i++)
			any = any || medias_table.get_row(i).checked;
		transfer.set_sensitive(any);
	}
	
	void transferAllToggled() {
		for(uint i = 0; i < medias_table.size; i++)
			medias_table.get_row(i).checked = transferAll.active;
		medias_table.rows.items_changed(0, medias_table.size, medias_table.size);
		medias_table.view.set_sensitive(!transferAll.active);
		transfer.set_sensitive(transferAll.active);
	}
	
	void transferClick() {
		to_transfer.clear();
		for(uint i = 0; i < medias_table.size; i++) {
			var row = medias_table.get_row(i);
			if(row.checked)
				to_transfer.add((Media) row.data);
		}
		
		if(App.operations.doing_ops) {
			App.window.doAlert(_("Cannot Import"), _("BeatBox is already doing file operations. Please wait until those finish to import from ") + Markup.escape_text(d.getDisplayName()));
		}
		else {
			d.transfer_to_library(to_transfer);
			this.destroy();
		}
	}
	
	void operation_started() {
		transfer.set_sensitive(false);
	}
	
	void operation_finished() {
		transfer.set_sensitive(true);
	}
}
