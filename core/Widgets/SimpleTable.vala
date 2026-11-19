/*
 * The small tables of the dialogs (previews, file lists, search results) on Gtk.ColumnView:
 * Gtk.TreeView and its cell renderers are deprecated since GTK 4.10. A row holds its cells'
 * text, a check box and the object it stands for.
 */

/** One row: the text (or markup) of each column, its check box and what it stands for */
[GIR (visible = false)] // internal: plugins don't see it
public class BeatBox.TableRow : Object {
	public string[] cells;
	public bool checked { get; set; }
	public Object? data;

	public TableRow (string[] cells, Object? data = null) {
		this.cells = cells;
		this.data = data;
	}
}

[GIR (visible = false)]
public class BeatBox.SimpleTable : Object {
	public delegate void CellSetup (Gtk.ListItem item);
	public delegate void CellBind (Gtk.ListItem item, TableRow row);

	/** The table, to put in a scrolled window */
	public Gtk.ColumnView view { get; private set; }
	public GLib.ListStore rows { get; private set; }
	public Gtk.SelectionModel selection { get; private set; }

	/** A row was double-clicked or got Enter */
	public signal void activated (TableRow row);
	/** The user ticked or unticked a row's check box */
	public signal void check_toggled (TableRow row);

	public SimpleTable (bool multiple_selection = false) {
		rows = new GLib.ListStore (typeof (TableRow));
		if (multiple_selection)
			selection = new Gtk.MultiSelection (rows);
		else
			selection = new Gtk.SingleSelection (rows) { autoselect = false, can_unselect = true };
		view = new Gtk.ColumnView (selection);
		view.reorderable = false;
		view.activate.connect ((position) => activated ((TableRow) rows.get_item (position)));
	}

	/** GTK 3's tables could hide their titles: the header row is the view's first child */
	public bool headers_visible {
		set {
			var header = view.get_first_child ();
			if (header != null)
				header.visible = value;
		}
	}

	/** A column of text (markup if asked) from cell number `cell` of the rows */
	public Gtk.ColumnViewColumn add_column (string? title, int cell, bool markup = false, bool expand = true,
	                                       Pango.EllipsizeMode ellipsize = Pango.EllipsizeMode.END) {
		return add_custom_column (title, (item) => {
			var label = new Gtk.Label (null);
			label.xalign = 0;
			label.ellipsize = ellipsize;
			item.child = label;
		}, (item, row) => {
			var label = (Gtk.Label) item.child;
			string text = cell < row.cells.length ? row.cells[cell] : "";
			if (markup)
				label.set_markup (text);
			else
				label.label = text;
		}, expand);
	}

	/** A column of check boxes for the rows' `checked` */
	public Gtk.ColumnViewColumn add_check_column (string? title) {
		return add_custom_column (title, (item) => {
			var check = new Gtk.CheckButton ();
			item.child = check;
			check.toggled.connect (() => {
				var row = item.item as TableRow;
				if (row == null || row.checked == check.active)
					return; // being bound, or no change
				row.checked = check.active;
				check_toggled (row);
			});
		}, (item, row) => {
			((Gtk.CheckButton) item.child).active = row.checked;
		}, false);
	}

	/** A column whose cells this table's user makes (setup) and fills (bind) */
	public Gtk.ColumnViewColumn add_custom_column (string? title, owned CellSetup setup, owned CellBind bind, bool expand = true) {
		var factory = new Gtk.SignalListItemFactory ();
		factory.setup.connect ((obj) => setup ((Gtk.ListItem) obj));
		factory.bind.connect ((obj) => {
			var item = (Gtk.ListItem) obj;
			bind (item, (TableRow) item.item);
		});
		var column = new Gtk.ColumnViewColumn (title, factory);
		column.expand = expand;
		column.resizable = true;
		view.append_column (column);
		return column;
	}

	public TableRow add (string[] cells, Object? data = null) {
		var row = new TableRow (cells, data);
		rows.append (row);
		return row;
	}

	public void clear () {
		rows.remove_all ();
	}

	public uint size { get { return rows.get_n_items (); } }

	public TableRow get_row (uint position) {
		return (TableRow) rows.get_item (position);
	}

	/** Redraws a row whose cells changed */
	public void changed (uint position) {
		rows.items_changed (position, 1, 1);
	}

	public void select (uint position) {
		selection.select_item (position, true);
	}

	/** The selected rows, in order */
	public Gee.List<TableRow> selected_rows () {
		var chosen = new Gee.ArrayList<TableRow> ();
		for (uint i = 0; i < rows.get_n_items (); i++)
			if (selection.is_selected (i))
				chosen.add (get_row (i));
		return chosen;
	}

	/** The first selected row, or null */
	public TableRow? selected_row () {
		var chosen = selected_rows ();
		return chosen.size > 0 ? chosen[0] : null;
	}
}
