// meson test: TagGuess (tags from a song's path)
using BeatBox;

void check (string path, string artist, string album, uint track, string title, uint year = 0) {
	var g = TagGuess.from_path (path);
	if (g.artist != artist || g.album != album || g.track != track || g.title != title || g.year != year)
		error ("%s → artist '%s' album '%s' track %u title '%s' year %u", path, g.artist, g.album, g.track, g.title, g.year);
}

void main1 () {
	check ("Artist/Album/03 - Title.mp3", "Artist", "Album", 3, "Title");
	check ("Artist/Album/03. Title.mp3", "Artist", "Album", 3, "Title");
	check ("Artist/Album/1-07 Title.flac", "Artist", "Album", 7, "Title");
	check ("Artist - Album (1999)/03 Title.flac", "Artist", "Album", 3, "Title", 1999);
	check ("Artist/1999 - Album/03 Title.flac", "Artist", "Album", 3, "Title", 1999);
	check ("Album/03 - Title.mp3", "", "Album", 3, "Title");                 // nothing above the album
	check ("Singles/Artist - Title.mp3", "Artist", "", 0, "Title");          // a loose song: no album
	check ("Artist - Album/05 - Artist - Title.mp3", "Artist", "Album", 5, "Title");
	check ("Artist - Album/05 - Other - Title.mp3", "Artist", "Album", 5, "Other - Title"); // not the artist: part of the title
	check ("my_song_name.ogg", "", "", 0, "my song name");
	check ("Some Folder/Track_01.mp3", "", "", 0, "Track 01");
	check ("1979.mp3", "", "", 0, "1979");
	check ("Other - Album/1-07 My_Song.mp3", "Other", "Album", 7, "My Song");
	check ("Artista/Disco Prueba (2001)/01 - Cancion 1.mp3", "Artista", "Disco Prueba", 1, "Cancion 1", 2001);                                    // a number alone is a title

}

// Find and Replace in Tags
string rep (string text, string find, string replace, bool case_sensitive = false, bool regex = false, bool whole_word = false) {
	try {
		return TagReplace.apply (TagReplace.pattern (find, case_sensitive, regex, whole_word), text, replace, regex);
	} catch (RegexError err) {
		return "error";
	}
}

void main2 () {
	assert (rep ("Los Tres feat. X", "feat.", "ft.") == "Los Tres ft. X");       // the dot is a dot, not any character
	assert (rep ("Los Tres featX", "feat.", "ft.") == "Los Tres featX");
	assert (rep ("ROCK rock", "rock", "Pop") == "Pop Pop");
	assert (rep ("ROCK rock", "rock", "Pop", true) == "ROCK Pop");
	assert (rep ("Rock Rockabilly", "rock", "Pop", false, false, true) == "Pop Rockabilly");
	assert (rep ("Artist - Title", "(.+) - (.+)", "\\2 (\\1)", false, true) == "Title (Artist)");
	assert (rep ("a\\b", "x", "\\1") == "a\\b");                                // literal replace: no \1 expansion needed
	assert (rep ("ax", "x", "\\1") == "a\\1");
	assert (rep ("abc", "(", "x", false, true) == "error");
}

void main () {
	main1 ();
	main2 ();
}
