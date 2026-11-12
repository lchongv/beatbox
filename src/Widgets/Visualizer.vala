/*
 * The visualizer, in the content area where the lists are: the bottom bar's visualizer button
 * shows it. Two engines:
 * - projectM (MilkDrop presets), when BeatBox is built with libprojectM 4 (meson: HAVE_PROJECTM).
 *   It needs two things from the process (src/C/offscreen-gl.c): it always draws into
 *   framebuffer 0, so it gets an off-screen OpenGL context of its own whose pbuffer is that
 *   framebuffer (each frame is read back and painted with cairo; GTK itself uses no OpenGL),
 *   and it reads and writes numbers with C's functions, so around its calls this thread uses
 *   "C" numbers (the system's decimal comma made its scene black).
 * - The classic effects (src/C/classic-visualizer.c, cairo only): when chosen in Preferences ›
 *   Appearance, and as the fallback when projectM is missing, can't start or has no presets.
 * Right click: the effects menu; double click: the next effect. Everything exists only while
 * the visualizer is on screen.
 */

using Gtk;

[CCode (cname = "bb_classic_vis_new")]
extern void* classic_new();
[CCode (cname = "bb_classic_vis_free")]
extern void classic_free(void* vis);
[CCode (cname = "bb_classic_vis_tick")]
extern void classic_tick(void* vis, [CCode (array_length = false)] float[] bands);
[CCode (cname = "bb_classic_vis_draw")]
extern void classic_draw(void* vis, Cairo.Context cr, int width, int height);
[CCode (cname = "bb_classic_vis_next")]
extern void classic_next(void* vis);
[CCode (cname = "bb_classic_vis_get_style")]
extern int classic_get_style(void* vis);
[CCode (cname = "bb_classic_vis_get_theme")]
extern int classic_get_theme(void* vis);
[CCode (cname = "bb_classic_vis_set_style")]
extern void classic_set_style(void* vis, int style);
[CCode (cname = "bb_classic_vis_set_theme")]
extern void classic_set_theme(void* vis, int theme);
[CCode (cname = "bb_classic_vis_set_auto")]
extern void classic_set_auto(void* vis, bool auto_switch);
[CCode (cname = "bb_classic_vis_set_artwork")]
extern void classic_set_artwork(void* vis, Gdk.Pixbuf? cover);

#if HAVE_PROJECTM
[CCode (cname = "bb_offscreen_gl_new")]
extern void* offscreen_gl_new();
[CCode (cname = "bb_offscreen_gl_resize")]
extern bool offscreen_gl_resize(void* gl, int width, int height);
[CCode (cname = "bb_offscreen_gl_make_current")]
extern void offscreen_gl_make_current(void* gl);
[CCode (cname = "bb_offscreen_gl_read")]
extern void offscreen_gl_read(void* gl, uchar* pixels);
[CCode (cname = "bb_offscreen_gl_free")]
extern void offscreen_gl_free(void* gl);
[CCode (cname = "bb_c_numbers_begin")]
extern void* c_numbers_begin();
[CCode (cname = "bb_c_numbers_end")]
extern void c_numbers_end(void* previous);
#endif

public class BeatBox.Visualizer : DrawingArea {
	// in the order of classic-visualizer.c's styles and palettes
	const string[] STYLE_NAMES = { N_("Tunnel"), N_("Rays"), N_("Burst"), N_("Spectrum"), N_("Wave"),
	                               N_("Spectrogram"), N_("Stars"), N_("Lissajous"), N_("Flower"),
	                               N_("Grid"), N_("Fire"), N_("Circles") };
	const string[] THEME_NAMES = { N_("Amber"), N_("Ocean"), N_("Neon"), N_("Forest"), N_("Rainbow"), N_("Sunset") };

	bool auto_change = true; // the effects change by themselves (menu)
	Gtk.Menu? menu = null;
	GestureMultiPress press;

	// the classic effects
	void* classic = null;
	uint classic_tick_id = 0;
	float[] bands = new float[10]; // the spectrum as the classic effects read it
	int64 last_spectrum = 0;

	public Visualizer() {
		add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
		press = new GestureMultiPress(this);
		press.button = 0;
		press.pressed.connect(on_pressed);
		map.connect(start);
		unmap.connect(stop);
		App.playback.spectrum_update.connect(on_spectrum);
		App.playback.media_played.connect(() => update_artwork());
		App.covers.cover_changed.connect(() => update_artwork());
		App.settings.main.notify["visualizer-classic"].connect(() => {
			if (get_mapped()) { // the other engine at once
				stop();
				start();
			}
		});
#if HAVE_PROJECTM
		App.playback.pcm_ready.connect(on_samples);
#endif
	}

	void start() {
#if HAVE_PROJECTM
		if (!App.settings.main.visualizer_classic && start_projectm())
			return;
#endif
		start_classic();
	}

	void stop() {
		stop_classic();
#if HAVE_PROJECTM
		stop_projectm();
#endif
	}

	public override bool draw(Cairo.Context cr) {
		int width = get_allocated_width(), height = get_allocated_height();
		if (classic != null) {
			classic_draw(classic, cr, width, height);
			return true;
		}
#if HAVE_PROJECTM
		if (frame != null) {
			cr.translate(0, height); // upside down, and scaled when the view is wider than the frame
			cr.scale((double) width / frame.get_width(), -(double) height / frame.get_height());
			cr.set_source_surface(frame, 0, 0);
			cr.paint();
			return true;
		}
#endif
		cr.set_source_rgb(0, 0, 0);
		cr.paint();
		return true;
	}

	/* ---- Classic effects ---- */

	void start_classic() {
		classic = classic_new();
		classic_set_auto(classic, auto_change);
		update_artwork();
		App.playback.want_spectrum(true);
		classic_tick_id = Timeout.add(33, () => { // the steps the effects were made for (~30 fps)
			if (get_monotonic_time() - last_spectrum > 150000) // paused or stopped: they rest
				for (int i = 0; i < bands.length; i++)
					bands[i] *= 0.85f;
			classic_tick(classic, bands);
			queue_draw();
			return Source.CONTINUE;
		});
	}

	void stop_classic() {
		if (classic == null)
			return;
		Source.remove(classic_tick_id);
		classic_tick_id = 0;
		App.playback.want_spectrum(false);
		classic_free(classic);
		classic = null;
	}

	// The classic effects' input: 10 equal bands of 0 Hz – rate/2, dB clamped to -60..0 as
	// 0..1, rising at once and falling slowly. BeatBox's spectrum has 512 such bands: each of
	// the 10 sums the power of ~51 of them, as GStreamer's spectrum with bands=10 does.
	void on_spectrum(float[] magnitudes) {
		if (classic == null || magnitudes.length == 0)
			return;
		last_spectrum = get_monotonic_time();
		int n = magnitudes.length;
		for (int b = 0; b < bands.length; b++) {
			double power = 0;
			for (int i = b * n / bands.length; i < (b + 1) * n / bands.length; i++)
				power += Math.pow(10, magnitudes[i] / 10);
			double db = (10 * Math.log10(double.max(power, 1e-12))).clamp(-60, 0);
			float level = (float) ((db + 60) / 60);
			bands[b] = level > bands[b] ? level : bands[b] * 0.85f + level * 0.15f;
		}
	}

	// the cover of the song playing takes its turn in the middle
	void update_artwork() {
		if (classic == null)
			return;
		Gdk.Pixbuf? cover = null;
		if (App.playback.media_active) {
			var path = App.covers.get_cached_album_art_path(App.covers.get_media_coverart_key(App.playback.current_media));
			try {
				cover = new Gdk.Pixbuf.from_file_at_scale(path, 256, 256, true);
			} catch (Error err) {
				// no cover: the logos take turns alone
			}
		}
		classic_set_artwork(classic, cover);
	}

	/* ---- The menu and the clicks ---- */

	void on_pressed(int n_press, double x, double y) {
		uint button = press.get_current_button();
		if (button == Gdk.BUTTON_PRIMARY && n_press == 2)
			next_effect();
		else if (button == Gdk.BUTTON_SECONDARY)
			show_menu();
	}

	void next_effect() {
		if (classic != null)
			classic_next(classic);
#if HAVE_PROJECTM
		else if (instance != null)
			wanted_preset = random_preset();
#endif
	}

	void show_menu() {
		menu = new Gtk.Menu();
		menu.attach_to_widget(this, null);
		var current = new Gtk.MenuItem.with_label(current_effect_name());
		current.sensitive = false;
		var current_label = (Label) current.get_child();
		current_label.ellipsize = Pango.EllipsizeMode.END;
		current_label.max_width_chars = 48;
		menu.append(current);
		menu.append(new SeparatorMenuItem());
		var next = new Gtk.MenuItem.with_label(_("Next Effect"));
		next.activate.connect(next_effect);
		menu.append(next);
#if HAVE_PROJECTM
		if (instance != null) {
			var previous = new Gtk.MenuItem.with_label(_("Previous Effect"));
			previous.sensitive = history.size > 0;
			previous.activate.connect(() => {
				going_back = true;
				wanted_preset = history.remove_at(history.size - 1);
			});
			menu.append(previous);
		}
#endif
		var change = new CheckMenuItem.with_label(_("Change Effects by Themselves"));
		change.active = auto_change;
		change.toggled.connect(() => {
			auto_change = change.active;
			if (classic != null)
				classic_set_auto(classic, auto_change);
#if HAVE_PROJECTM
			last_preset = get_monotonic_time(); // a whole turn before the next change
#endif
		});
		menu.append(change);
		menu.append(new SeparatorMenuItem());
		if (classic != null)
			add_classic_items(menu);
#if HAVE_PROJECTM
		else if (instance != null)
			add_preset_items(menu, presets_root());
#endif
		menu.show_all();
		menu.popup_at_pointer(null);
	}

	string current_effect_name() {
		if (classic != null)
			return "%s · %s".printf(_(STYLE_NAMES[classic_get_style(classic)]), _(THEME_NAMES[classic_get_theme(classic)]));
#if HAVE_PROJECTM
		if (current_preset != null)
			return Path.get_basename(current_preset).replace(".milk", "");
#endif
		return _("Visualizer");
	}

	// the styles, then the palettes in a submenu
	void add_classic_items(Gtk.Menu menu) {
		unowned SList<RadioMenuItem>? styles = null;
		for (int i = 0; i < STYLE_NAMES.length; i++) {
			var item = new RadioMenuItem.with_label(styles, _(STYLE_NAMES[i]));
			styles = item.get_group();
			item.active = i == classic_get_style(classic);
			int style = i;
			item.toggled.connect(() => {
				if (item.active)
					classic_set_style(classic, style);
			});
			menu.append(item);
		}
		var colors = new Gtk.Menu();
		unowned SList<RadioMenuItem>? themes = null;
		for (int i = 0; i < THEME_NAMES.length; i++) {
			var item = new RadioMenuItem.with_label(themes, _(THEME_NAMES[i]));
			themes = item.get_group();
			item.active = i == classic_get_theme(classic);
			int theme = i;
			item.toggled.connect(() => {
				if (item.active)
					classic_set_theme(classic, theme);
			});
			colors.append(item);
		}
		var colors_item = new Gtk.MenuItem.with_label(_("Colors"));
		colors_item.submenu = colors;
		menu.append(new SeparatorMenuItem());
		menu.append(colors_item);
	}

#if HAVE_PROJECTM
	/* ---- projectM ---- */

	const int64 PRESET_SECONDS = 30;
	// ponytail: wider views get the frame scaled up; the read back costs per pixel, every frame
	const int MAX_WIDTH = 1280;

	void* gl = null;                  // the off-screen context, while on screen
	void* instance = null;            // projectM, while on screen
	Cairo.ImageSurface? frame = null; // the last frame, upside down (OpenGL's rows go bottom up)
	string[] presets = {};
	string? current_preset = null;    // kept across hiding: the same effect comes back
	string? wanted_preset = null;     // loaded at the next frame, with the context current
	Gee.ArrayList<string> history = new Gee.ArrayList<string>(); // for "Previous Effect"
	bool going_back = false;
	int64 last_preset = 0;
	uint tick_id = 0;

	// false (and nothing left) when projectM can't run: the classic effects take its place
	bool start_projectm() {
		var numbers = c_numbers_begin();
		bool ok = open_projectm();
		c_numbers_end(numbers);
		if (!ok) {
			stop_projectm();
			return false;
		}
		App.playback.want_pcm(true);
		tick_id = add_tick_callback(on_tick);
		return true;
	}

	bool open_projectm() {
		presets = find_presets();
		if (presets.length == 0) {
			message("Visualizer: no projectM presets in %s, the classic effects instead", presets_root());
			return false;
		}
		gl = offscreen_gl_new(); // it says why when there is none
		if (gl == null || !fit_frame())
			return false;
		instance = ProjectM.create();
		if (instance == null) {
			warning("Visualizer: projectM could not start, the classic effects instead");
			return false;
		}
		ProjectM.set_window_size(instance, frame.get_width(), frame.get_height());
		// the presets sample these pictures (noise, shapes); without them they draw noise
		var textures = Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-textures");
		ProjectM.set_texture_search_paths(instance, { textures }, 1);
		wanted_preset = current_preset ?? random_preset();
		return true;
	}

	void stop_projectm() {
		if (tick_id != 0) {
			remove_tick_callback(tick_id);
			tick_id = 0;
			App.playback.want_pcm(false);
		}
		if (instance != null) {
			offscreen_gl_make_current(gl);
			ProjectM.destroy(instance);
			instance = null;
		}
		if (gl != null) {
			offscreen_gl_free(gl);
			gl = null;
		}
		frame = null;
	}

	// the frame follows the view's size, up to MAX_WIDTH; a new size is a new pbuffer
	bool fit_frame() {
		int width = int.max(1, get_allocated_width()), height = int.max(1, get_allocated_height());
		if (width > MAX_WIDTH) {
			height = int.max(1, height * MAX_WIDTH / width);
			width = MAX_WIDTH;
		}
		if (frame != null && frame.get_width() == width && frame.get_height() == height)
			return true;
		if (!offscreen_gl_resize(gl, width, height))
			return false;
		frame = new Cairo.ImageSurface(Cairo.Format.RGB24, width, height);
		if (instance != null)
			ProjectM.set_window_size(instance, width, height);
		return true;
	}

	bool on_tick(Widget widget, Gdk.FrameClock clock) {
		if (instance == null)
			return Source.CONTINUE;
		var numbers = c_numbers_begin();
		if (fit_frame()) {
			offscreen_gl_make_current(gl); // every projectM call that draws or loads goes to its own context
			if (wanted_preset == null && auto_change && get_monotonic_time() - last_preset > PRESET_SECONDS * 1000000)
				wanted_preset = random_preset();
			if (wanted_preset != null) {
				show_preset(wanted_preset);
				wanted_preset = null;
			}
			ProjectM.opengl_render_frame(instance);
			frame.flush();
			offscreen_gl_read(gl, (uchar*) frame.get_data());
			frame.mark_dirty();
			queue_draw();
		}
		c_numbers_end(numbers);
		return Source.CONTINUE;
	}

	// with the off-screen context current and "C" numbers
	void show_preset(string path) {
		if (current_preset != null && !going_back) {
			history.add(current_preset);
			if (history.size > 50)
				history.remove_at(0);
		}
		going_back = false;
		current_preset = path;
		last_preset = get_monotonic_time();
		ProjectM.load_preset_file(instance, path, true);
	}

	string random_preset() {
		return presets[Random.int_range(0, presets.length)];
	}

	// the sound comes on its own thread: projectM is fed in the main loop, where it is drawn
	void on_samples(float[] samples) {
		Idle.add(() => {
			if (instance != null)
				ProjectM.pcm_add_float(instance, samples, (uint) (samples.length / 2), 2);
			return Source.REMOVE;
		});
	}

	/* The presets are .milk files in folders, under ~/.local/share/beatbox/projectm-presets.
	 * The menu shows those folders as submenus; a lone folder on the way (a pack's own
	 * folder) is skipped. */
	static string presets_root() {
		string dir = Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-presets");
		string[] folders, files;
		list_folder(dir, out folders, out files);
		while (folders.length == 1 && files.length == 0) {
			dir = Path.build_filename(dir, folders[0]);
			list_folder(dir, out folders, out files);
		}
		return dir;
	}

	// names, sorted: the subfolders and the .milk files
	static void list_folder(string dir, out string[] folders, out string[] files) {
		var dirs = new Gee.ArrayList<string>();
		var milks = new Gee.ArrayList<string>();
		try {
			var contents = Dir.open(dir);
			string? name;
			while ((name = contents.read_name()) != null) {
				if (FileUtils.test(Path.build_filename(dir, name), FileTest.IS_DIR))
					dirs.add(name);
				else if (name.has_suffix(".milk"))
					milks.add(name);
			}
		} catch (FileError err) {
			// no presets folder
		}
		CompareDataFunc<string> by_name = (a, b) => a.collate(b);
		dirs.sort(by_name);
		milks.sort(by_name);
		folders = dirs.to_array();
		files = milks.to_array();
	}

	// a folder's subfolders (filled when first pointed at: some hold hundreds) and presets
	void add_preset_items(Gtk.Menu menu, string dir) {
		string[] folders, files;
		list_folder(dir, out folders, out files);
		foreach (var folder in folders) {
			var item = new Gtk.MenuItem.with_label(folder);
			var submenu = new Gtk.Menu();
			item.submenu = submenu;
			string path = Path.build_filename(dir, folder);
			item.select.connect(() => {
				if (submenu.get_children() == null) {
					add_preset_items(submenu, path);
					submenu.show_all();
				}
			});
			menu.append(item);
		}
		foreach (var file in files) {
			var item = new Gtk.MenuItem.with_label(file.replace(".milk", ""));
			var label = (Label) item.get_child(); // some names are a sentence long: they differ at the end
			label.ellipsize = Pango.EllipsizeMode.MIDDLE;
			label.max_width_chars = 60;
			string path = Path.build_filename(dir, file);
			item.activate.connect(() => { wanted_preset = path; });
			menu.append(item);
		}
	}

	static string[] find_presets() {
		var found = new Gee.ArrayList<string>();
		collect(Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-presets"), found);
		return found.to_array();
	}

	static void collect(string dir, Gee.List<string> found) {
		string[] folders, files;
		list_folder(dir, out folders, out files);
		foreach (var folder in folders)
			collect(Path.build_filename(dir, folder), found);
		foreach (var file in files)
			found.add(Path.build_filename(dir, file));
	}
#endif
}
