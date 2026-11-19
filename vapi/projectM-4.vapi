/* The part of libprojectM 4 (projectm.h) that BeatBox uses: the visualizer in src/Widgets/Visualizer.vala.
 * No distribution ships a vapi for projectM 4, so ours goes along with the sources. */

[CCode (cheader_filename = "projectM-4/projectM.h")]
namespace ProjectM {
	[CCode (cname = "projectm_create")]
	public void* create ();
	[CCode (cname = "projectm_destroy")]
	public void destroy (void* instance);
	[CCode (cname = "projectm_set_window_size")]
	public void set_window_size (void* instance, size_t width, size_t height);
	[CCode (cname = "projectm_set_texture_search_paths")]
	public void set_texture_search_paths (void* instance, [CCode (array_length = false)] string[] paths, size_t count);
	[CCode (cname = "projectm_load_preset_file")]
	public void load_preset_file (void* instance, string filename, bool smooth_transition);
	[CCode (cname = "projectm_pcm_add_float")]
	public void pcm_add_float (void* instance, [CCode (array_length = false)] float[] samples, uint count, int channels);
	[CCode (cname = "projectm_set_beat_sensitivity")]
	public void set_beat_sensitivity (void* instance, float sensitivity);
	[CCode (cname = "projectm_set_soft_cut_duration")]
	public void set_soft_cut_duration (void* instance, double seconds);
	[CCode (cname = "projectm_set_hard_cut_enabled")]
	public void set_hard_cut_enabled (void* instance, bool enabled);
	[CCode (cname = "projectm_set_hard_cut_duration")]
	public void set_hard_cut_duration (void* instance, double seconds);
	[CCode (cname = "projectm_set_preset_duration")]
	public void set_preset_duration (void* instance, double seconds);
	[CCode (cname = "projectm_set_mesh_size")]
	public void set_mesh_size (void* instance, size_t width, size_t height);
	[CCode (cname = "projectm_preset_switch_requested_event", has_target = false)]
	public delegate void SwitchRequested (bool is_hard_cut, void* user_data);
	[CCode (cname = "projectm_set_preset_switch_requested_event_callback")]
	public void set_preset_switch_requested_event_callback (void* instance, SwitchRequested? callback, void* user_data);
	[CCode (cname = "projectm_opengl_render_frame")]
	public void opengl_render_frame (void* instance);
}
