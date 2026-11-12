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
	[CCode (cname = "projectm_load_preset_file")]
	public void load_preset_file (void* instance, string filename, bool smooth_transition);
	[CCode (cname = "projectm_pcm_add_float")]
	public void pcm_add_float (void* instance, [CCode (array_length = false)] float[] samples, uint count, int channels);
	[CCode (cname = "projectm_opengl_render_frame")]
	public void opengl_render_frame (void* instance);
}
