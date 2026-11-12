/*
 * projectM in the content area, where the lists are: the toolbar's visualizer button shows it.
 * It is built only with libprojectM 4 (meson: HAVE_PROJECTM). Its drawing and the sound's
 * samples run only while it is on screen.
 */

using Gtk;

#if HAVE_PROJECTM
public class BeatBox.Visualizer : GLArea {
	const int64 PRESET_SECONDS = 30;

	void* instance = null; // the projectM handle, from realize to unrealize
	string[] presets = {};
	int64 last_preset = 0;
	uint tick_id = 0;
	bool rendered = false;

	public Visualizer() {
		set_auto_render(false);
		set_required_version(3, 3);
		realize.connect(on_realize);
		unrealize.connect(on_unrealize);
		render.connect(on_render);
		resize.connect(on_resize);
		map.connect(on_map);
		unmap.connect(on_unmap);
		App.playback.pcm_ready.connect(on_samples);
	}

	void on_realize() {
		var error = get_error(); // GL context problems show up here, not as warnings of their own
		if (error != null)
			warning("Visualizer: no OpenGL context: %s", error.message);
		make_current();
		instance = ProjectM.create();
		if (instance == null)
			warning("Visualizer: projectM could not start");
		ProjectM.set_window_size(instance, get_allocated_width(), get_allocated_height());
		// the presets sample these pictures (noise, shapes); without them they draw noise
		var textures = Path.build_filename(Environment.get_user_data_dir(), "beatbox", "projectm-textures");
		ProjectM.set_texture_search_paths(instance, { textures }, 1);
		presets = find_presets();
		message("Visualizer: realized, %d presets", presets.length);
		next_preset();
	}

	void on_unrealize() {
		make_current();
		ProjectM.destroy(instance);
		instance = null;
	}

	void on_resize(int width, int height) {
		if (instance != null)
			ProjectM.set_window_size(instance, width, height);
	}

	bool on_render(Gdk.GLContext context) {
		if (instance != null)
			ProjectM.opengl_render_frame(instance);
		if (!rendered) {
			rendered = true;
			message("Visualizer: first frame drawn (%dx%d)", get_allocated_width(), get_allocated_height());
		}
		return true;
	}

	void on_map() {
		App.playback.want_pcm(true);
		tick_id = add_tick_callback((widget, clock) => {
			if (get_monotonic_time() - last_preset > PRESET_SECONDS * 1000000)
				next_preset();
			queue_render();
			return Source.CONTINUE;
		});
	}

	void on_unmap() {
		App.playback.want_pcm(false);
		remove_tick_callback(tick_id);
		tick_id = 0;
	}

	// the sound comes on its own thread: projectM is fed in the main loop, where it is drawn
	void on_samples(float[] samples) {
		Idle.add(() => {
			if (instance != null)
				ProjectM.pcm_add_float(instance, samples, (uint) (samples.length / 2), 2);
			return Source.REMOVE;
		});
	}

	void next_preset() {
		last_preset = get_monotonic_time();
		if (instance != null && presets.length > 0)
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
