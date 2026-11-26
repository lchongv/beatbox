/*-
 * Column browser: Genre | Artist | Album, each column filtering the next one
 * (like the iTunes "Column Browser"). Every column takes several rows at once
 * (Ctrl and Shift click); nothing selected, or the "All" row, means no filter.
 */

using Gtk;
using Gee;

/** What a column of the browser lists: a name for the preferences and the value a song has for it */
public class BeatBox.BrowserCriterion : GLib.Object {
	public delegate string ValueFunc (Media m);

	public string id;
	public string label;
	public bool numeric;     // sorted by its number, not alphabetically
	public bool descending;  // numbers: the biggest first
	ValueFunc func;

	public BrowserCriterion (string id, string label, owned ValueFunc func, bool numeric = false, bool descending = false) {
		this.id = id;
		this.label = label;
		this.func = (owned) func;
		this.numeric = numeric;
		this.descending = descending;
	}

	public string value_of (Media m) {
		return func (m);
	}

	static ArrayList<BrowserCriterion>? all_criteria = null;

	/** Every criterion a column can use, in the order the preferences list them */
	public static Collection<BrowserCriterion> all () {
		if (all_criteria == null) {
			var l = new ArrayList<BrowserCriterion> ();
			l.add (new BrowserCriterion ("genre", _("Genre"), (m) => m.genre));
			l.add (new BrowserCriterion ("artist", _("Artist"), (m) => m.album_artist));
			l.add (new BrowserCriterion ("trackartist", _("Track Artist"), (m) => m.artist));
			l.add (new BrowserCriterion ("album", _("Album"), (m) => m.album));
			l.add (new BrowserCriterion ("year", _("Year"), (m) => m.year == 0 ? "" : m.year.to_string (), true, true));
			l.add (new BrowserCriterion ("decade", _("Decade"), (m) => m.year == 0 ? "" : "%us".printf (m.year / 10 * 10), true, true));
			l.add (new BrowserCriterion ("rating", _("Rating"), (m) => m.rating == 0 ? "" : "%u ★".printf (m.rating), true, true));
			l.add (new BrowserCriterion ("composer", _("Composer"), (m) => m.composer));
			l.add (new BrowserCriterion ("grouping", _("Grouping"), (m) => m.grouping));
			all_criteria = l;
		}
		return all_criteria;
	}

	public static BrowserCriterion? find (string id) {
		foreach (var c in all ()) {
			if (c.id == id)
				return c;
		}
		return null;
	}

	/** "genre,artist,album" from the options as criteria; a bad or empty list gives the default three */
	public static ArrayList<BrowserCriterion> parse (string ids) {
		var result = new ArrayList<BrowserCriterion> ();
		foreach (var id in ids.split (",")) {
			var c = find (id.strip ());
			if (c != null && !result.contains (c) && result.size < 4)
				result.add (c);
		}
		if (result.size == 0)
			return parse ("genre,artist,album");
		return result;
	}
}

/** One row of a column: a name (lower-cased as the key) and how many songs have it */
class BeatBox.BrowserItem : GLib.Object {
	public string name;   // as shown the first time it was seen; "" is "no value"
	public int count = 0;
	public bool is_all;

	public BrowserItem (string name, int count, bool is_all = false) {
		this.name = name;
		this.count = count;
		this.is_all = is_all;
	}
}

class BeatBox.BrowserColumn : Box {
	public signal void changed ();

	public string title { get; private set; }
	/** lower-cased values the user wants; the rows that are still there stay selected after a rebuild */
	public HashSet<string> wanted = new HashSet<string> ();

	GLib.ListStore store;
	MultiSelection selection;
	bool rebuilding = false;

	public BrowserCriterion criterion { get; private set; }

	public BrowserColumn (BrowserCriterion criterion) {
		Object (orientation: Orientation.VERTICAL, spacing: 0);
		this.criterion = criterion;
		this.title = criterion.label;
		this.all_text = _("All (%s)").printf (criterion.label);
		hexpand = true;
		add_css_class ("column-browser-column");

		var header = new Label (title);
		header.add_css_class ("column-browser-header");
		header.xalign = 0;
		header.hexpand = true;
		append (header);

		store = new GLib.ListStore (typeof (BrowserItem));
		selection = new MultiSelection (store);
		selection.selection_changed.connect (on_selection_changed);

		var factory = new SignalListItemFactory ();
		factory.setup.connect ((obj) => {
			var li = (ListItem) obj;
			var row = new Box (Orientation.HORIZONTAL, 6);
			row.add_css_class ("column-browser-row");
			var name = new Label ("");
			name.xalign = 0;
			name.hexpand = true;
			name.ellipsize = Pango.EllipsizeMode.END;
			var count = new Label ("");
			count.add_css_class ("dim-label");
			row.append (name);
			row.append (count);
			li.child = row;
		});
		factory.bind.connect ((obj) => {
			var li = (ListItem) obj;
			var item = (BrowserItem) li.item;
			var row = (Box) li.child;
			var name = (Label) row.get_first_child ();
			var count = (Label) row.get_last_child ();
			if (item.is_all)
				name.label = all_text;
			else
				name.label = (item.name == "") ? _("Unknown") : item.name;
			count.label = item.count.to_string ();
			name.remove_css_class ("browser-all");
			if (item.is_all)
				name.add_css_class ("browser-all");
		});

		var list = new ListView (selection, factory);
		list.add_css_class ("column-browser-list"); // zebra rows, see data/theme.css
		var scroll = new ScrolledWindow ();
		scroll.set_policy (PolicyType.NEVER, PolicyType.AUTOMATIC);
		scroll.vexpand = true;
		scroll.min_content_height = 40;
		scroll.set_child (list);
		append (scroll);
	}

	string all_text;

	/** Fills the column with the values and their song counts; the wanted ones stay selected */
	public void rebuild (HashMap<string, BrowserItem> items) {
		rebuilding = true;
		var sorted = new ArrayList<BrowserItem> ();
		sorted.add_all (items.values);
		sorted.sort ((a, b) => {
			if (a.name == "" && b.name != "") return 1;   // "no value" last
			if (a.name != "" && b.name == "") return -1;
			if (criterion.numeric) {
				int d = int.parse (a.name) - int.parse (b.name);
				return criterion.descending ? -d : d;
			}
			return a.name.collate_key_for_filename ().collate (b.name.collate_key_for_filename ());
		});

		int total = 0;
		foreach (var i in sorted)
			total += i.count;

		store.remove_all ();
		store.append (new BrowserItem ("", total, true));
		var kept = new HashSet<string> ();
		uint pos = 1;
		foreach (var i in sorted) {
			store.append (i);
			if (wanted.contains (i.name.down ())) {
				kept.add (i.name.down ());
				selection.select_item (pos, false);
			}
			pos++;
		}
		wanted = kept;
		rebuilding = false;
	}

	void on_selection_changed (uint position, uint n_items) {
		if (rebuilding)
			return;
		rebuilding = true;
		uint total = store.get_n_items ();
		bool all_now = selection.is_selected (0);
		if (all_now && position == 0) {
			// "All" just picked: the others are not wanted any more
			if (total > 1)
				selection.unselect_range (1, (uint) total - 1);
		} else if (all_now) {
			selection.unselect_item (0); // a real value picked: no longer "All"
		}
		wanted.clear ();
		for (uint i = 1; i < total; i++) {
			if (selection.is_selected (i))
				wanted.add (((BrowserItem) store.get_item (i)).name.down ());
		}
		rebuilding = false;
		changed ();
	}
}

public class BeatBox.ColumnBrowser : Box {
	/** The values chosen per criterion id, lower-cased; a missing or empty set is "no filter" */
	public signal void filters_changed (HashMap<string, HashSet<string>> filters);

	ArrayList<BrowserColumn> columns = new ArrayList<BrowserColumn> ();
	Collection<Media>? medias = null;
	string last_key = "";
	bool silent = false;

	public ColumnBrowser () {
		Object (orientation: Orientation.HORIZONTAL, spacing: 0);
		add_css_class ("column-browser");
	}

	/** Shows these criteria, one column each, with the values in `filters` chosen. Emits the filters that are left */
	public void set_criteria (Collection<BrowserCriterion> criteria, HashMap<string, HashSet<string>> filters) {
		Widget? w;
		while ((w = get_first_child ()) != null)
			remove (w);
		columns.clear ();

		foreach (var crit in criteria) {
			if (columns.size > 0)
				append (new Separator (Orientation.VERTICAL));
			var column = new BrowserColumn (crit);
			var chosen = filters.get (crit.id);
			if (chosen != null)
				column.wanted.add_all (chosen);
			int index = columns.size;
			column.changed.connect (() => { fill (index + 1); emit (); });
			columns.add (column);
			append (column);
		}
		fill (0);
		emit ();
	}

	public void set_medias (Collection<Media> all) {
		medias = all;
		fill (0);
		if (key () != last_key)
			emit ();
	}

	/** Shows these values as the chosen ones (the filters were set from elsewhere): does not emit */
	public void set_selection (HashMap<string, HashSet<string>> filters) {
		foreach (var c in columns) {
			c.wanted = new HashSet<string> ();
			var chosen = filters.get (c.criterion.id);
			if (chosen != null)
				c.wanted.add_all (chosen);
		}
		silent = true;
		fill (0);
		silent = false;
		last_key = key ();
	}

	/** Rebuilds the columns from index `from` on; a column lists what the chosen values of the ones before it leave */
	void fill (int from) {
		if (medias == null)
			return;
		int n = columns.size;
		var items = new ArrayList<HashMap<string, BrowserItem>> ();
		for (int i = 0; i < n; i++)
			items.add (new HashMap<string, BrowserItem> ());

		foreach (var m in medias) {
			for (int i = 0; i < n; i++) {
				string shown = columns[i].criterion.value_of (m);
				string k = shown.down ();
				if (i >= from)
					count (items[i], k, shown);
				if (columns[i].wanted.size > 0 && !columns[i].wanted.contains (k))
					break;
			}
		}

		// the wanted values of a column are trimmed to what is still there, which narrows the next one
		for (int i = from; i < n; i++) {
			columns[i].rebuild (items[i]);
		}
	}

	static void count (HashMap<string, BrowserItem> items, string key, string shown) {
		var item = items.get (key);
		if (item == null) {
			item = new BrowserItem (shown, 0);
			items.set (key, item);
		}
		item.count++;
	}

	string key () {
		var sb = new StringBuilder ();
		foreach (var c in columns) {
			sb.append (c.criterion.id).append ("=");
			sb.append (string.joinv ("\x01", sorted (c.wanted))).append ("\x02");
		}
		return sb.str;
	}

	static string[] sorted (HashSet<string> set) {
		var list = new ArrayList<string> ();
		list.add_all (set);
		list.sort ((a, b) => strcmp (a, b));
		return list.to_array ();
	}

	void emit () {
		last_key = key ();
		if (silent)
			return;
		var filters = new HashMap<string, HashSet<string>> ();
		foreach (var c in columns) {
			var copy = new HashSet<string> ();
			copy.add_all (c.wanted);
			filters.set (c.criterion.id, copy);
		}
		filters_changed (filters);
	}
}
