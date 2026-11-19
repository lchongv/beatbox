/*
 * Preferences › Visualizer (a page shown with "Show advanced settings" on, see PreferencesWindow).
 * Every widget is bound to its option (BeatBox.Settings, visualizer_*): changes show at once in
 * the visualizer (Visualizer.setting_changed), and "Restore Defaults" moves the widgets back too.
 */

using Gtk;

public class BeatBox.VisualizerPreferences : SimplePreferences {
	delegate void Sync();
	public override string title { get { return _("Visualizer"); } }

	Settings.Settings s = App.settings.main;

	public VisualizerPreferences() {
		/* ---- Basic ---- */
		add_heading(_("Effects"));
#if HAVE_PROJECTM
		// without projectM there is nothing to choose: the visualizer shows the classic effects
		var classic = add_check(_("Use the classic effects instead of the MilkDrop presets"), s.visualizer_classic);
		bind("visualizer-classic", classic, "active");
		add_row(note(_("They need no OpenGL. The visualizer also turns to them when the MilkDrop presets can't start.")));
#endif

		var change = new CheckButton.with_label(_("Change the effect by itself every"));
		bind("visualizer-auto-change", change, "active");
		var seconds = new SpinButton.with_range(5, 600, 5);
		bind("visualizer-change-seconds", seconds, "value");
		change.bind_property("active", seconds, "sensitive", BindingFlags.SYNC_CREATE);
		var change_row = new Box(Orientation.HORIZONTAL, 8);
		change_row.append(change);
		change_row.append(seconds);
		change_row.append(new Label(_("seconds")));
		add_row(change_row);

		add_row(labelled(_("Classic effect to start with:"), choice("visualizer-style", Visualizer.STYLE_NAMES)));
		add_row(labelled(_("Colors to start with:"), choice("visualizer-palette", Visualizer.THEME_NAMES)));
		var logos = add_check(_("Show the logos and the album cover in the middle of the classic effects"), s.visualizer_logos);
		bind("visualizer-logos", logos, "active");

		add_heading(_("Sound"));
		add_row(labelled(_("Sensitivity:"), scale("visualizer-sensitivity", 25, 300, 5, "%d %%"), _("louder moves the effects more")));
		add_row(labelled(_("Smoothing:"), scale("visualizer-smoothing", 0, 95, 5, "%d %%"), _("how slowly the levels fall")));

		add_heading(_("Classic Effects"));
		add_row(labelled(_("Speed:"), scale("visualizer-speed", 25, 300, 5, "%d %%")));
		add_row(labelled(_("Frames per second:"), scale("visualizer-fps", 10, 60, 5, "%d")));
		var fade = scale("visualizer-transition-ms", 100, 5000, 100, "");
		fade.set_format_value_func((sc, v) => _("%.1f s").printf(v / 1000.0));
		add_row(labelled(_("Fade between two effects:"), fade));
		add_row(new Label(_("Effects the changes pick from:")) { xalign = 0 });
		add_row(mask_checks("visualizer-styles", Visualizer.STYLE_NAMES, 4));
		add_row(new Label(_("Colors the changes pick from:")) { xalign = 0 });
		add_row(mask_checks("visualizer-palettes", Visualizer.THEME_NAMES, 3));

#if HAVE_PROJECTM
		add_heading(_("MilkDrop Presets"));
		add_row(labelled(_("Beat sensitivity:"), scale("visualizer-pm-beat", 0, 500, 10, "%d %%")));
		var blend = scale("visualizer-pm-blend-seconds", 0, 15, 1, "");
		blend.set_format_value_func((sc, v) => _("%d s").printf((int) v));
		add_row(labelled(_("Fade between two presets:"), blend));
		var cuts = add_check(_("Cut to another preset on strong beats"), s.visualizer_pm_hard_cuts);
		bind("visualizer-pm-hard-cuts", cuts, "active");

		var width = new ChoiceBox();
		foreach (var w in new int[] { 640, 960, 1280, 1920, 2560 })
			width.append(w.to_string(), _("%d pixels wide").printf(w));
		bind_id("visualizer-pm-max-width", width);
		add_row(labelled(_("Drawn up to:"), width, _("wider views scale it up")));

		var mesh = new ChoiceBox();
		mesh.append("0", _("Low"));
		mesh.append("1", _("Normal"));
		mesh.append("2", _("High"));
		mesh.append("3", _("Very high"));
		bind_id("visualizer-pm-mesh", mesh);
		add_row(labelled(_("Detail of the motion:"), mesh));
		add_row(note(_("Higher values look smoother and cost more processor and graphics time.")
		             + " " + _("Presets go in %s.").printf(Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-presets"))));
#endif

		var reset = new Button.with_label(_("Restore Defaults"));
		reset.halign = Align.START;
		reset.clicked.connect(() => { s.reset_visualizer(); });
		add_row(reset);
	}

	// widget property ⇄ option, both ways, starting from the option
	void bind(string option, Object widget, string property) {
		s.bind_property(option, widget, property, BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE);
	}

	// a combo whose ids are the option's numbers
	void bind_id(string option, ChoiceBox combo) {
		s.bind_property(option, combo, "active-id", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE,
			(b, from, ref to) => { to.set_string(from.get_int().to_string()); return true; },
			(b, from, ref to) => {
				unowned string? id = from.get_string();
				if (id == null)
					return false;
				to.set_int(int.parse(id));
				return true;
			});
	}

	// "Any" (-1), then the names in order (0, 1...)
	ChoiceBox choice(string option, string[] names) {
		var combo = new ChoiceBox();
		combo.append("-1", _("Any (at random)"));
		for (int i = 0; i < names.length; i++)
			combo.append(i.to_string(), _(names[i]));
		bind_id(option, combo);
		return combo;
	}

	Scale scale(string option, double min, double max, double step, string format) {
		var sc = new Scale.with_range(Orientation.HORIZONTAL, min, max, step);
		sc.width_request = 220;
		sc.draw_value = true;
		sc.value_pos = PositionType.RIGHT;
		sc.digits = 0;
		if (format != "")
			sc.set_format_value_func((x, v) => format.printf((int) v));
		bind(option, sc.adjustment, "value");
		return sc;
	}

	// one check per name, in columns; bit n of the option is name n. At least one stays on
	Grid mask_checks(string option, string[] names, int columns) {
		var grid = new Grid();
		grid.column_spacing = 12;
		grid.row_spacing = 2;
		grid.margin_start = 12;
		var checks = new CheckButton[names.length];
		bool updating = false;
		for (int i = 0; i < names.length; i++) {
			int bit = i;
			var check = new CheckButton.with_label(_(names[i]));
			checks[i] = check;
			check.toggled.connect(() => {
				if (updating)
					return;
				int mask = 0;
				s.get(option, out mask);
				mask = check.active ? (mask | (1 << bit)) : (mask & ~(1 << bit));
				if (mask == 0) { // none would leave the changes nothing to pick
					check.active = true;
					return;
				}
				s.set(option, mask);
			});
			grid.attach(check, i % columns, i / columns);
		}
		// the checks follow the option (also after "Restore Defaults")
		Sync sync = () => {
			int mask = 0;
			s.get(option, out mask);
			updating = true;
			for (int i = 0; i < checks.length; i++)
				checks[i].active = (mask & (1 << i)) != 0;
			updating = false;
		};
		sync();
		s.notify[option].connect(() => sync());
		return grid;
	}

	static Label note(string text) {
		var label = new Label(text);
		label.xalign = 0.0f;
		label.wrap = true;
		label.max_width_chars = 60;
		label.add_css_class("dim-label");
		return label;
	}
}
