/*
 * A widget of our own around a scrollable view (Gtk.ListView, Gtk.ColumnView, Gtk.GridView):
 * those can't be subclassed as the old Gtk.TreeView and Gtk.IconView were, so the list,
 * grid and side bar classes hold one and pass it the scrolled window's adjustments. Put in
 * a Gtk.ScrolledWindow it scrolls as the view itself would, without a Gtk.Viewport.
 */
public abstract class BeatBox.ScrollableBin : Gtk.Widget, Gtk.Scrollable {
	Gtk.Widget? inner = null;
	Gtk.Adjustment? _hadjustment = null;
	Gtk.Adjustment? _vadjustment = null;
	Gtk.ScrollablePolicy _hscroll_policy = Gtk.ScrollablePolicy.MINIMUM;
	Gtk.ScrollablePolicy _vscroll_policy = Gtk.ScrollablePolicy.MINIMUM;

	static construct {
		set_layout_manager_type (typeof (Gtk.BinLayout));
	}

	/** The view inside: it must be Gtk.Scrollable */
	protected Gtk.Widget scroll_child {
		get { return inner; }
		set {
			if (inner != null)
				inner.unparent ();
			inner = value;
			inner.set_parent (this);
			inner.hexpand = inner.vexpand = true;
			var s = (Gtk.Scrollable) inner;
			s.hscroll_policy = _hscroll_policy;
			s.vscroll_policy = _vscroll_policy;
			if (_hadjustment != null)
				s.hadjustment = _hadjustment;
			if (_vadjustment != null)
				s.vadjustment = _vadjustment;
		}
	}

	public override void dispose () {
		if (inner != null) {
			inner.unparent ();
			inner = null;
		}
		base.dispose ();
	}

	public Gtk.Adjustment hadjustment {
		get { return inner != null ? ((Gtk.Scrollable) inner).hadjustment : _hadjustment; }
		set construct {
			_hadjustment = value;
			if (inner != null)
				((Gtk.Scrollable) inner).hadjustment = value;
		}
	}

	public Gtk.Adjustment vadjustment {
		get { return inner != null ? ((Gtk.Scrollable) inner).vadjustment : _vadjustment; }
		set construct {
			_vadjustment = value;
			if (inner != null)
				((Gtk.Scrollable) inner).vadjustment = value;
		}
	}

	public Gtk.ScrollablePolicy hscroll_policy {
		get { return _hscroll_policy; }
		set {
			_hscroll_policy = value;
			if (inner != null)
				((Gtk.Scrollable) inner).hscroll_policy = value;
		}
	}

	public Gtk.ScrollablePolicy vscroll_policy {
		get { return _vscroll_policy; }
		set {
			_vscroll_policy = value;
			if (inner != null)
				((Gtk.Scrollable) inner).vscroll_policy = value;
		}
	}

	public bool get_border (out Gtk.Border border) {
		if (inner != null)
			return ((Gtk.Scrollable) inner).get_border (out border);
		border = Gtk.Border ();
		return false;
	}
}
