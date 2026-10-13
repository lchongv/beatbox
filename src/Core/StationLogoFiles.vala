/*
 * The image a user picks for a station, in a folder of its own (not the cache, which can be
 * emptied) under the md5 of the stream's address. The folder is a parameter so
 * tests/station-logo-files.vala can run it on a temporary one.
 */
namespace BeatBox.StationLogoFiles {
	const int MAX_SIZE = 512;

	public string path_for (string folder, string uri) {
		return Path.build_filename (folder, Checksum.compute_for_string (ChecksumType.MD5, uri));
	}

	public bool exists (string folder, string uri) {
		return FileUtils.test (path_for (folder, uri), FileTest.EXISTS);
	}

	public Gdk.Pixbuf? load (string folder, string uri) {
		try {
			return new Gdk.Pixbuf.from_file (path_for (folder, uri));
		} catch (Error err) {
			return null;
		}
	}

	/** Keeps source as the station's image, scaled down to MAX_SIZE; false (nothing changed) when it isn't an image */
	public bool save (string folder, string uri, File source) {
		try {
			var pixbuf = new Gdk.Pixbuf.from_file (source.get_path ());
			if (pixbuf.width > MAX_SIZE || pixbuf.height > MAX_SIZE) {
				double k = (double) MAX_SIZE / int.max (pixbuf.width, pixbuf.height);
				pixbuf = pixbuf.scale_simple (int.max (1, (int) (pixbuf.width * k)), int.max (1, (int) (pixbuf.height * k)), Gdk.InterpType.BILINEAR);
			}
			DirUtils.create_with_parents (folder, 0755);
			pixbuf.save (path_for (folder, uri), "png");
			return true;
		} catch (Error err) {
			warning ("Could not use %s as a station image: %s", source.get_parse_name (), err.message);
			return false;
		}
	}

	/** false when the station had none */
	public bool remove (string folder, string uri) {
		return FileUtils.unlink (path_for (folder, uri)) == 0;
	}
}
