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

using Gtk;
using Gee;

public class BeatBox.SmartPlaylistEditor : Window {
	const int BUFFER_SPACE = 500;
	SmartPlaylist sp;
	
	Box content;
	Box padding;
	
	private  Label nameLabel;
	private Label rulesLabel;
	private Label optionsLabel;
	
	Gtk.Entry nameEntry;
	ChoiceBox comboMatch;
	
	bool is_in_scroll;
	Box no_scroll;
	Viewport scroll;
	ScrolledWindow scrolled_window;
	Widget scrolled_child; // scrolled_window with its Aqua bars, if any: it is what is shown or hidden
	Box vertQueries;
	Gee.ArrayList<SmartPlaylistEditorQuery> spQueries;
	
	Button addButton;
	CheckButton limitMedias;
	SpinButton mediaLimit;
	Button save;
	
	public signal void playlist_saved(SmartPlaylist sp);
	
	public SmartPlaylistEditor(SmartPlaylist sp) {
		this.sp = sp;
		
		this.title = _("Smart Playlist Editor");
		
		this.set_modal(true);
		this.set_transient_for(App.window);
		this.destroy_with_parent = true;
		
		content = new Box(Orientation.VERTICAL, 10);
		padding = new Box(Orientation.HORIZONTAL, 10);
		
		/* start out by creating all category labels */
		nameLabel = new Label(_("Name of Playlist"));
		rulesLabel = new Label(_("Rules"));
		optionsLabel = new Label(_("Options"));
		
		/* make them look good */
		nameLabel.xalign = 0.0f;
		rulesLabel.xalign = 0.0f;
		optionsLabel.xalign = 0.0f;
		nameLabel.set_markup("<b>%s</b>".printf(_("Name of Playlist")));
		rulesLabel.set_markup("<b>%s</b>".printf(_("Rules")));
		optionsLabel.set_markup("<b>%s</b>".printf(_("Options")));
		
		/* add the name entry */
		nameEntry = new Gtk.Entry() { placeholder_text = _("Playlist Title") };
		if(sp.name != "")
			nameEntry.set_text(sp.name);
		
		/* create match checkbox/combo combination */
		Box matchBox = new Box(Orientation.HORIZONTAL, 2);
		Label tMatch = new Label(_("Match"));
		comboMatch = new ChoiceBox();
		comboMatch.insert_text(0, _("any"));
		comboMatch.insert_text(1, _("all"));
		Label tOfTheFollowing = new Label(_("of the following:"));
		
		matchBox.append (tMatch);
		matchBox.append (comboMatch);
		matchBox.append (tOfTheFollowing);
		
		if(sp.conditional == SmartPlaylist.Conditional.ANY)
			comboMatch.active = 0;
		else
			comboMatch.active = 1;
		
		/* create rule list */
		spQueries = new Gee.ArrayList<SmartPlaylistEditorQuery>();
		vertQueries = new Box(Orientation.VERTICAL, 2);
		no_scroll = new Box(Orientation.VERTICAL, 0);
		// the wheel over the rules must not move the combos in them: this takes it first (was the EventBox)
		var wheel = new EventControllerScroll(EventControllerScrollFlags.BOTH_AXES);
		wheel.propagation_phase = PropagationPhase.CAPTURE;
		wheel.scroll.connect((dx, dy) => { return true; });
		no_scroll.add_controller(wheel);
		scroll = new Viewport(null, null);
		scrolled_window = new ScrolledWindow ();
		scrolled_window.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
		scrolled_window.set_size_request(-1, get_display().get_monitor_at_surface(App.window.get_surface()).get_geometry().height - BUFFER_SPACE);
		scrolled_window.set_child (scroll);
		
		// to start, put in no_scroll
		no_scroll.append(vertQueries);
		
		foreach(SmartQuery q in sp.queries) {
			SmartPlaylistEditorQuery speq = new SmartPlaylistEditorQuery(q);
			
			vertQueries.append (speq);
			spQueries.add(speq);
			speq.removed.connect(speq_removed);
		}
		
		if(sp.queries.size == 0) {
			addRow();
		}
		
		addButton = new Button.with_label(_("Add"));
		addButton.clicked.connect(addButtonClick);
		
		vertQueries.margin_end = addButton.margin_end = 6;
		
		/* create extra option: limiter */
		limitMedias = new CheckButton.with_label(_("Limit to"));
		mediaLimit = new SpinButton.with_range(0, 500, 10);
		Label limiterLabel = new Label(_("medias"));
		
		limitMedias.set_active(sp.limit);
		mediaLimit.set_value((double)sp.limit_amount);
		
		Box limiterBox = new Box(Orientation.HORIZONTAL, 2);
		limiterBox.append (limitMedias);
		limiterBox.append (mediaLimit);
		limiterBox.append (limiterLabel);
		
		/* add the Done button on bottom */
		var bottomButtons = new Box(Orientation.HORIZONTAL, 6);
		bottomButtons.halign = Align.END;
		save = new Button.with_label(_("Done"));
		var cancel = new Button.with_label(_("Cancel"));
		bottomButtons.append(cancel);
		bottomButtons.append(save);
		
		/* put it all together */
		content.append (UI.wrap_alignment(nameLabel, 10, 0, 0, 0));
		content.append (UI.wrap_alignment(nameEntry, 0, 10, 0, 10));
		content.append (rulesLabel);
		content.append (UI.wrap_alignment(matchBox, 0, 10, 0, 10) );
		content.append (UI.wrap_alignment(no_scroll, 0, 0, 0, 0));
		scrolled_child = AquaScroll.wrap(scrolled_window);
		content.append (UI.wrap_alignment(scrolled_child, 0, 0, 0, 0));
		content.append (UI.wrap_alignment(addButton, 0, 0, 0, 0));
		content.append (optionsLabel);
		content.append (UI.wrap_alignment(limiterBox, 0, 10, 0, 10));
		bottomButtons.margin_top = bottomButtons.margin_bottom = 10;
		content.append (bottomButtons);
		
		content.hexpand = true;
		padding.append (content);
		
		scrolled_child.visible = false;
		
		set_child(UI.wrap_alignment(padding, 0, 10, 0, 10));
		present();
		
		save.clicked.connect(saveClick);
		cancel.clicked.connect( () => { destroy(); } );
		nameEntry.changed.connect(nameChanged);
		
		scrolled_child.hide();
		resize_gui();
	}
	
	void nameChanged() {
		if(nameEntry.get_text() == "") {
			save.set_sensitive(false);
			return;
		}
		else {
			foreach(var p in App.playlists.playlists()) {
				if((sp == null || sp.id != p.id) && nameEntry.get_text() == p.name) {
					save.set_sensitive(false);
					return;
				}
			}
		}
		
		save.set_sensitive(true);
	}
	
	void addRow() {
		SmartPlaylistEditorQuery speq = new SmartPlaylistEditorQuery(new SmartQuery());
		
		vertQueries.append (speq);
		spQueries.add(speq);
		speq.removed.connect(speq_removed);
		resize_gui();
	}
	
	void addButtonClick() {
		addRow();
	}
	
	void speq_removed(SmartPlaylistEditorQuery query) {
		spQueries.remove(query);
		vertQueries.remove(query);
		query.destroy();
		
		resize_gui();
	}
	
	void resize_gui() {
		if(!get_realized()) // a row added while building the window: shown at its size anyway
			return;
		
		Requisition min_req = Requisition();
		Requisition natural_req = Requisition();
		get_preferred_size(out min_req, out natural_req);
		
		set_default_size(min_req.width, min_req.height);
		
		// Determine if we should move to scroll/out of scroll
		bool should_be_in_scroll = vertQueries.get_height() >= (get_display().get_monitor_at_surface(App.window.get_surface()).get_geometry().height - BUFFER_SPACE);
		if(is_in_scroll && !should_be_in_scroll) {
			scroll.set_child(null);
			scrolled_child.hide();
			no_scroll.append(vertQueries);
			no_scroll.show();
			is_in_scroll = false;
		}
		else if(!is_in_scroll && should_be_in_scroll) {
			no_scroll.remove(vertQueries);
			no_scroll.hide();
			scroll.set_child (vertQueries);
			scrolled_child.show();
			scroll.show();
			is_in_scroll = true;
		}
	}
	
	void saveClick() {
		sp.queries.clear();
		foreach(SmartPlaylistEditorQuery speq in spQueries) {
			sp.queries.add(speq.getQuery());
		}
		
		sp.name = nameEntry.text;
		sp.conditional = (SmartPlaylist.Conditional)comboMatch.active;
		sp.limit = limitMedias.get_active();
		sp.limit_amount = (int)mediaLimit.get_value();
		
		playlist_saved(sp);
		
		this.destroy();
	}
}

public class BeatBox.SmartPlaylistEditorQuery : Box {
	SmartQuery q;
	
	ChoiceBox field;
	ChoiceBox comparator; // the comparators that suit the field (see fill_comparators)
	ChoiceBox media_option;
	Entry entry;
	SpinButton spinbutton;
	
	Label units;
	Button removeButton;
	
	public signal void removed(SmartPlaylistEditorQuery query);
	
	public SmartPlaylistEditorQuery(SmartQuery q) {
		this.q = q;
		
		// Create drop downs (an item's id is its enum value)
		field = new ChoiceBox();
		foreach(SmartQuery.Field f in SmartQuery.Field.all())
			field.append(((int)f).to_string(), f.to_string());
		
		comparator = new ChoiceBox();
		
		entry = new Entry();
		spinbutton =  new SpinButton.with_range(0, 9999, 1);
		
		media_option = new ChoiceBox();
		// TODO: RE-implement MediaType.to_string()
		foreach(var type in new MediaType[] { MediaType.SONG, MediaType.PODCAST, MediaType.AUDIOBOOK, MediaType.STATION })
			media_option.append(((int)type).to_string(), type.to_string(1));
		
		units = new Label("");
		removeButton = new Button.with_label(_("Remove"));
		
		field.active = (int)q.field;
		fill_comparators();
		comparator.select_id(((int)q.comparator).to_string());
		
		entry.visible = false;
		media_option.visible = false;
		spinbutton.visible = false;
		
		comparator.set_size_request(160, -1);
		entry.set_size_request(200, -1);
		media_option.set_size_request(200, -1);
		spinbutton.set_size_request(200, -1);
		
		// Set the value
		if(q.field.is_string()) {
			entry.set_text(q.string_value);
			entry.show();
		}
		else if(q.field.is_type()) {
			media_option.active = q.int_value;
			media_option.show();
		}
		else if(q.field.is_int() || q.field.is_time()) {
			spinbutton.set_value(q.int_value);
			spinbutton.show();
		}
		
		append(field);
		append(comparator);
		entry.hexpand = true;
		append(entry);
		media_option.hexpand = true;
		append(media_option);
		spinbutton.hexpand = true;
		append(spinbutton);
		append(units);
		append(removeButton);
		
		
		removeButton.clicked.connect(removeClicked);
		field.changed.connect(fieldChanged);
	}
	
	public SmartQuery getQuery() {
		SmartQuery rv = new SmartQuery();
		
		rv.field = (SmartQuery.Field)field.active;
		rv.comparator = (SmartQuery.Comparator)int.parse(comparator.active_id ?? "0");
		
		if(rv.field.is_string())
			rv.string_value = entry.text;
		else if(rv.field.is_type())
			rv.int_value = (MediaType)media_option.active;
		else
			rv.int_value = (int)spinbutton.value;
		
		return rv;
	}
	
	/** The comparators that suit the field chosen */
	void fill_comparators() {
		comparator.remove_all();
		foreach(SmartQuery.Comparator com in SmartQuery.Comparator.all())
			if(comparator_fits((int)com))
				comparator.append(((int)com).to_string(), com.to_string());
	}
	
	bool comparator_fits(int id) {
		bool rv = false;
		
		SmartQuery.Field cur_field = (SmartQuery.Field)field.active;
		switch (id) {
			case SmartQuery.Comparator.IS:
				rv = cur_field.is_string() || cur_field.is_type(); // strings, mediatype,
				break;
			case SmartQuery.Comparator.IS_EXACTLY:
				rv = cur_field.is_int() || cur_field.is_time(); // ints, times
				break;
			case SmartQuery.Comparator.IS_NOT:
				rv = cur_field.is_type(); //mediatype
				break;
			case SmartQuery.Comparator.IS_AT_LEAST:
			case SmartQuery.Comparator.IS_AT_MOST:
				rv = cur_field.is_int(); // ints
				break;
			case SmartQuery.Comparator.IS_WITHIN:
			case SmartQuery.Comparator.IS_BEFORE:
				rv = cur_field.is_time(); // times
				break;
			case SmartQuery.Comparator.CONTAINS:
			case SmartQuery.Comparator.DOES_NOT_CONTAIN:
				rv = cur_field.is_string(); // strings
				break;
			default:
				rv = false;
				break;
		}
		
		return rv;
	}
	
	void fieldChanged() {
		if(((SmartQuery.Field)field.active).is_string()) {
			entry.show();
			media_option.hide();
			spinbutton.hide();
		}
		else if(((SmartQuery.Field)field.active).is_type()) {
			entry.hide();
			spinbutton.hide();
			media_option.show();
			media_option.active = q.int_value;
		}
		else {
			spinbutton.show();
			entry.hide();
			media_option.hide();
		}
		
		fill_comparators();
		comparator.active = 0;
		
		
		//helper for units
		if(((SmartQuery.Field)field.active) == SmartQuery.Field.LENGTH) {
			units.set_text(_("seconds"));
			units.show();
		}
		else if(((SmartQuery.Field)field.active).is_time()) {
			units.set_text(_("days ago"));
			units.show();
		}
		else if(((SmartQuery.Field)field.active) == SmartQuery.Field.BITRATE) {
			units.set_text(_("kbps"));
			units.show();
		}
		else
			units.hide();
	}
	
	void removeClicked() {
		removed(this);
	}
}
