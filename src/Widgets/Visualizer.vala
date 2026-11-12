/*
 * projectM in the content area, where the lists are: the bottom bar's visualizer button shows it.
 * Two things projectM 4.1 needs from the process (src/C/offscreen-gl.c):
 * - It always draws into framebuffer 0, whatever framebuffer is bound, so a GtkGLArea never gets
 *   its picture. It gets an off-screen OpenGL context of its own, whose pbuffer is that
 *   framebuffer 0; each frame is read back and painted with cairo. GTK itself uses no OpenGL.
 * - It reads and writes its numbers with C's functions: with the system's decimal comma its
 *   scene is black. Around its calls this thread uses "C" numbers.
 * The context, projectM and the sound's samples exist only while the visualizer is on screen.
 * Built only with libprojectM 4 (meson: HAVE_PROJECTM).
 */

using Gtk;

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

public class BeatBox.Visualizer : DrawingArea {
	const int64 PRESET_SECONDS = 30;
	// ponytail: wider views get the frame scaled up; the read back costs per pixel, every frame
	const int MAX_WIDTH = 1280;

	void* gl = null;                  // the off-screen context, while on screen
	void* instance = null;            // projectM, while on screen
	Cairo.ImageSurface? frame = null; // the last frame, upside down (OpenGL's rows go bottom up)
	string[] presets = {};
	int64 last_preset = 0;
	uint tick_id = 0;

	public Visualizer() {
		map.connect(start);
		unmap.connect(stop);
		App.playback.pcm_ready.connect(on_samples);
	}

	void start() {
		var numbers = c_numbers_begin();
		open_projectm();
		c_numbers_end(numbers);
		if (instance != null) {
			App.playback.want_pcm(true);
			tick_id = add_tick_callback(on_tick);
		}
	}

	void open_projectm() {
		gl = offscreen_gl_new(); // it says why when there is none
		if (gl == null || !fit_frame())
			return;
		instance = ProjectM.create();
		if (instance == null) {
			warning("Visualizer: projectM could not start");
			return;
		}
		ProjectM.set_window_size(instance, frame.get_width(), frame.get_height());
		// the presets sample these pictures (noise, shapes); without them they draw noise
		var textures = Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-textures");
		ProjectM.set_texture_search_paths(instance, { textures }, 1);
		presets = find_presets();
		next_preset();
	}

	void stop() {
		if (tick_id != 0) {
			remove_tick_callback(tick_id);
			tick_id = 0;
		}
		App.playback.want_pcm(false);
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
			if (get_monotonic_time() - last_preset > PRESET_SECONDS * 1000000)
				next_preset();
			ProjectM.opengl_render_frame(instance);
			frame.flush();
			offscreen_gl_read(gl, (uchar*) frame.get_data());
			frame.mark_dirty();
			queue_draw();
		}
		c_numbers_end(numbers);
		return Source.CONTINUE;
	}

	public override bool draw(Cairo.Context cr) {
		int width = get_allocated_width(), height = get_allocated_height();
		if (frame == null) {
			cr.set_source_rgb(0, 0, 0);
			cr.paint();
			return true;
		}
		cr.translate(0, height); // upside down, and scaled when the view is wider than the frame
		cr.scale((double) width / frame.get_width(), -(double) height / frame.get_height());
		cr.set_source_surface(frame, 0, 0);
		cr.paint();
		return true;
	}

	// the sound comes on its own thread: projectM is fed in the main loop, where it is drawn
	void on_samples(float[] samples) {
		Idle.add(() => {
			if (instance != null)
				ProjectM.pcm_add_float(instance, samples, (uint) (samples.length / 2), 2);
			return Source.REMOVE;
		});
	}

	// with the off-screen context current and "C" numbers
	void next_preset() {
		last_preset = get_monotonic_time();
		if (presets.length > 0)
			ProjectM.load_preset_file(instance, presets[Random.int_range(0, presets.length)], true);
	}

	// the presets are .milk files, in folders: ~/.local/share/beatbox/projectm-presets
	static string[] find_presets() {
		var found = new Gee.ArrayList<string>();
		collect(Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-presets"), found);
		return found.to_array();
	}

	static void collect(string dir, Gee.List<string> found) {
		try {
			var contents = Dir.open(dir);
			string? name;
			while ((name = contents.read_name()) != null) {
				var path = Path.build_filename(dir, name);
				if (FileUtils.test(path, FileTest.IS_DIR))
					collect(path, found);
				else if (name.has_suffix(".milk"))
					found.add(path);
			}
		} catch (FileError err) {
			// no presets folder: projectM draws its default
		}
	}
}
#endif
