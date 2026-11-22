/*
 * A choice among items (each with an id, a text and maybe an object), in place of
 * Gtk.ComboBox and Gtk.ComboBoxText (deprecated in GTK 4.10). It keeps their API, so the
 * code that used them reads the same: append, active, active_id, changed... (set_active_id is
 * select_id: a method and a property of one name can't both be in C)
 * - a menu: a Gtk.DropDown, separators included
 * - with_entry (): an entry the user types in, with the items that match it listed below
 *   (ComboBoxText.with_entry and an EntryCompletion did that before)
 */

[GIR (visible = false)] // internal: plugins don't see it
public class BeatBox.ChoiceItem : Object {
	public string? id;
	public string text;
	public Object? data;
	public bool separator;

	public ChoiceItem (string? id, string text, Object? data = null, bool separator = false) {
		this.id = id;
		this.text = text;
		this.data = data;
		this.separator = separator;
	}
}

[GIR (visible = false)]
public class BeatBox.ChoiceBox : Gtk.Box {
	/** The choice changed: picked, set from code, or (with an entry) typed over */
	public signal void changed ();
	/** The list is about to show (it can be filled now) */
	public signal void popup ();

	public bool has_entry { get; private set; }
	/** The entry of a ChoiceBox.with_entry (), or null */
	public Gtk.Entry? entry { get; private set; default = null; }

	GLib.ListStore items = new GLib.ListStore (typeof (ChoiceItem));
	Gtk.DropDown? dropdown = null;
	Gtk.Popover? suggestions = null;
	Gtk.ListBox? suggestion_list = null;
	int chosen = -1;      // the entry's item (with an entry; the dropdown keeps its own)
	bool quiet = false;   // set from code: the entry's text changes without a new search

	public ChoiceBox () {
		Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
		changed.connect (notify_choice);
		var factory = new Gtk.SignalListItemFactory ();
		factory.setup.connect ((obj) => {
			var label = new Gtk.Label (null);
			label.xalign = 0;
			label.ellipsize = Pango.EllipsizeMode.END;
			((Gtk.ListItem) obj).child = label;
		});
		factory.bind.connect ((obj) => {
			var li = (Gtk.ListItem) obj;
			((Gtk.Label) li.child).label = ((ChoiceItem) li.item).text;
		});
		// in the open list a separator is a line, and can't be chosen
		var list_factory = new Gtk.SignalListItemFactory ();
		list_factory.setup.connect ((obj) => {
			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
			var label = new Gtk.Label (null); // whole in the open list: it grows wider than the button
			label.xalign = 0;
			box.append (label);
			box.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
			((Gtk.ListItem) obj).child = box;
		});
		list_factory.bind.connect ((obj) => {
			var li = (Gtk.ListItem) obj;
			var item = (ChoiceItem) li.item;
			var label = (Gtk.Label) li.child.get_first_child ();
			label.label = item.text;
			label.visible = !item.separator;
			li.child.get_last_child ().visible = item.separator;
			li.selectable = li.activatable = !item.separator;
		});
		dropdown = new Gtk.DropDown (items, null);
		dropdown.factory = factory;
		dropdown.list_factory = list_factory;
		dropdown.hexpand = false; // as a ComboBox: as wide as its items, unless the box is told to expand
		dropdown.selected = Gtk.INVALID_LIST_POSITION;
		dropdown.notify["selected"].connect (() => changed ());
		// the list opens on a press: popup () lets it be filled first
		var press = new Gtk.GestureClick ();
		press.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
		press.pressed.connect (() => popup ());
		dropdown.add_controller (press);
		base.append (dropdown);
	}

	/** An entry to type in, suggesting the items that match */
	public ChoiceBox.with_entry () {
		Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
		changed.connect (notify_choice);
		has_entry = true;
		add_css_class ("linked");
		entry = new Gtk.Entry ();
		entry.hexpand = false;
		base.append (entry);
		var arrow = new Gtk.Button.from_icon_name ("pan-down-symbolic");
		arrow.tooltip_text = _("Show all");
		base.append (arrow);

		suggestion_list = new Gtk.ListBox ();
		suggestion_list.selection_mode = Gtk.SelectionMode.NONE;
		suggestion_list.activate_on_single_click = true;
		suggestion_list.row_activated.connect ((row) => {
			suggestions.popdown ();
			active = (int) row.get_data<uint> ("position");
		});
		var scroll = new Gtk.ScrolledWindow ();
		scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
		scroll.propagate_natural_width = true; // as wide as the longest item, not the entry
		scroll.propagate_natural_height = true;
		scroll.max_content_height = 300;
		scroll.child = suggestion_list;
		suggestions = new Gtk.Popover ();
		suggestions.child = scroll;
		suggestions.autohide = false; // typing goes on in the entry
		suggestions.has_arrow = false;
		suggestions.position = Gtk.PositionType.BOTTOM;
		suggestions.set_parent (entry);

		entry.changed.connect (() => {
			if (quiet)
				return;
			if (chosen >= 0 && entry.text != get_text (chosen)) {
				chosen = -1; // typed over the chosen item
				changed ();
			}
			show_suggestions (entry.text.strip (), false);
		});
		arrow.clicked.connect (() => {
			popup ();
			if (suggestions.visible)
				suggestions.popdown ();
			else
				show_suggestions ("", true);
		});
		var keys = new Gtk.EventControllerKey ();
		keys.key_pressed.connect ((keyval, code, state) => {
			if (keyval == Gdk.Key.Escape && suggestions.visible) {
				suggestions.popdown ();
				return true;
			}
			if (keyval == Gdk.Key.Down && suggestions.visible) {
				var first = suggestion_list.get_row_at_index (0);
				if (first != null)
					first.grab_focus ();
				return true;
			}
			return false;
		});
		entry.add_controller (keys);
		var focus = new Gtk.EventControllerFocus ();
		focus.leave.connect (() => {
			// a click in the list moves the focus there first: close only once it's gone elsewhere
			Idle.add (() => {
				if (!entry.has_focus && (suggestion_list.get_focus_child () == null))
					suggestions.popdown ();
				return false;
			});
		});
		entry.add_controller (focus);
		entry.activate.connect (() => suggestions.popdown ());
	}

	// bindings to active / active-id follow the choice
	void notify_choice () {
		notify_property ("active");
		notify_property ("active-id");
	}

	public override void dispose () {
		if (suggestions != null) {
			suggestions.unparent ();
			suggestions = null;
		}
		base.dispose ();
	}

	void show_suggestions (string typed, bool all) {
		Gtk.Widget? child;
		while ((child = suggestion_list.get_first_child ()) != null)
			suggestion_list.remove (child);
		string key = typed.casefold ();
		int shown = 0;
		for (uint i = 0; i < items.get_n_items () && shown < 200; i++) {
			var item = (ChoiceItem) items.get_item (i);
			if (item.separator || (!all && (key == "" || !item.text.casefold ().contains (key))))
				continue;
			var label = new Gtk.Label (item.text);
			label.xalign = 0;
			label.ellipsize = Pango.EllipsizeMode.END;
			label.margin_start = label.margin_end = 6;
			var row = new Gtk.ListBoxRow ();
			row.child = label;
			row.set_data<uint> ("position", i);
			suggestion_list.append (row);
			shown++;
		}
		if (shown > 0 && (all || entry.has_focus))
			suggestions.popup ();
		else
			suggestions.popdown ();
	}

	/* ---- the items ---- */

	public int n_items { get { return (int) items.get_n_items (); } }

	public new void append (string? id, string text, Object? data = null) {
		items.append (new ChoiceItem (id, text, data));
	}

	public void append_text (string text) {
		append (null, text);
	}

	public new void prepend (string? id, string text, Object? data = null) {
		insert (0, id, text, data);
	}

	public new void insert (int position, string? id, string text, Object? data = null) {
		items.insert (int.max (position, 0), new ChoiceItem (id, text, data));
		if (chosen >= position && chosen >= 0)
			chosen++;
	}

	public void insert_text (int position, string text) {
		insert (position, null, text);
	}

	/** A line between items (in the menu) */
	public void append_separator () {
		items.append (new ChoiceItem (null, "", null, true));
	}

	public new void remove (int position) {
		if (position < 0 || position >= n_items)
			return;
		bool was_active = (active == position);
		items.remove (position);
		if (has_entry) {
			if (was_active)
				chosen = -1;
			else if (chosen > position)
				chosen--;
		}
	}

	public void remove_all () {
		int before = active;
		chosen = -1;
		items.remove_all ();
		if (before >= 0 && has_entry)
			changed ();
	}

	public string? get_id (int position) {
		var item = (ChoiceItem?) items.get_item (position);
		return item != null ? item.id : null;
	}

	public string get_text (int position) {
		var item = (ChoiceItem?) items.get_item (position);
		return item != null ? item.text : "";
	}

	public Object? get_item_data (int position) {
		var item = (ChoiceItem?) items.get_item (position);
		return item != null ? item.data : null;
	}

	public void set_text (int position, string text) {
		var item = (ChoiceItem?) items.get_item (position);
		if (item == null)
			return;
		item.text = text;
		items.items_changed (position, 1, 1);
	}

	/* ---- the choice ---- */

	/** The position of the item chosen, or -1 */
	public int active {
		get {
			if (has_entry)
				return chosen;
			uint selected = dropdown.selected;
			return selected == Gtk.INVALID_LIST_POSITION ? -1 : (int) selected;
		}
		set {
			int position = (value >= 0 && value < n_items) ? value : -1;
			if (has_entry) {
				chosen = position;
				quiet = true;
				entry.text = position >= 0 ? get_text (position) : "";
				quiet = false;
				changed ();
				return;
			}
			dropdown.selected = position >= 0 ? (uint) position : Gtk.INVALID_LIST_POSITION;
		}
	}

	/** The id of the item chosen, or null */
	public string? active_id {
		owned get { return active >= 0 ? get_id (active) : null; }
		set { select_id (value); }
	}

	/** Chooses the item with this id: false (and nothing chosen) when there is none */
	public bool select_id (string? id) {
		for (int i = 0; i < n_items; i++) {
			if (get_id (i) == id) {
				active = i;
				return true;
			}
		}
		active = -1;
		return false;
	}

	public string? get_active_text () {
		if (has_entry)
			return entry.text;
		return active >= 0 ? get_text (active) : null;
	}

	public Object? get_active_data () {
		return active >= 0 ? get_item_data (active) : null;
	}
}
