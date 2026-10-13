/* The image a user picks for a station: kept scaled, apart from the cache, and removable */
void make_png (string path, int width, int height) {
	var pixbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, width, height);
	pixbuf.fill ((uint32) 0xff8800ff);
	try {
		pixbuf.save (path, "png");
	} catch (Error err) {
		assert_not_reached ();
	}
}

void main () {
	string dir = "";
	try {
		dir = DirUtils.make_tmp ("logoXXXXXX");
	} catch (Error err) {
		assert_not_reached ();
	}
	string uri = "http://example.org/stream";
	string big = Path.build_filename (dir, "big.png");
	make_png (big, 2000, 1000);
	string folder = Path.build_filename (dir, "custom");

	assert (BeatBox.StationLogoFiles.load (folder, uri) == null);
	assert (BeatBox.StationLogoFiles.path_for (folder, uri) == BeatBox.StationLogoFiles.path_for (folder, uri));
	assert (BeatBox.StationLogoFiles.path_for (folder, uri) != BeatBox.StationLogoFiles.path_for (folder, uri + "2"));

	// kept scaled to 512 px on its long side, proportions intact
	assert (BeatBox.StationLogoFiles.save (folder, uri, File.new_for_path (big)));
	var kept = BeatBox.StationLogoFiles.load (folder, uri);
	assert (kept != null && kept.width == 512 && kept.height == 256);

	// a small one is not enlarged, and replaces the first
	string small = Path.build_filename (dir, "small.png");
	make_png (small, 40, 30);
	assert (BeatBox.StationLogoFiles.save (folder, uri, File.new_for_path (small)));
	kept = BeatBox.StationLogoFiles.load (folder, uri);
	assert (kept.width == 40 && kept.height == 30);

	// something that isn't an image changes nothing
	string text = Path.build_filename (dir, "notes.png");
	try {
		FileUtils.set_contents (text, "not an image");
	} catch (Error err) {
		assert_not_reached ();
	}
	assert (!BeatBox.StationLogoFiles.save (folder, uri, File.new_for_path (text)));
	assert (!BeatBox.StationLogoFiles.save (folder, uri, File.new_for_path (Path.build_filename (dir, "missing.png"))));
	assert (BeatBox.StationLogoFiles.load (folder, uri).width == 40);

	// removing: true once, then there is nothing
	assert (BeatBox.StationLogoFiles.remove (folder, uri));
	assert (BeatBox.StationLogoFiles.load (folder, uri) == null);
	assert (!BeatBox.StationLogoFiles.remove (folder, uri));
	assert (!BeatBox.StationLogoFiles.exists (folder, uri));
}
