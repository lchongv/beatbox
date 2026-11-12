// meson test: BeatBox.UI.children and BeatBox.UI.clear
// Exits with 77 (skipped) when there is no display to run GTK on.
int main () {
	if (!Gtk.init_check ())
		return 77;

	var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
	for (int i = 0; i < 3; i++)
		box.append (new Gtk.Label ("label %d".printf (i)));

	assert (BeatBox.UI.children (box).length () == 3);

	BeatBox.UI.clear (box);
	assert (box.get_first_child () == null);
	return 0;
}
