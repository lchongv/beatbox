/* Scrollbars in the Mac OS X Tiger (Aqua) style, drawn by src/C/aqua-scrollbar.c.
 * Off by default: a scrolled window is returned as it is. */
namespace BeatBox.AquaScroll {
	[CCode (cname = "aqua_scrollbar_wrap")]
	extern Gtk.Widget aqua_scrollbar_wrap (Gtk.Widget scrolled_window);

	/** The widget to put where the scrolled window goes: the window itself, or the window with its Aqua bars */
	public Gtk.Widget wrap (Gtk.ScrolledWindow scroll) {
		if (!App.settings.main.aqua_scrollbars)
			return scroll;
		return aqua_scrollbar_wrap (scroll);
	}
}
