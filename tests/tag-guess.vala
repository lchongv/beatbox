// meson test: TagGuess (tags from a song's path)
using BeatBox;

void check (string path, string artist, string album, uint track, string title, uint year = 0) {
	var g = TagGuess.from_path (path);
	if (g.artist != artist || g.album != album || g.track != track || g.title != title || g.year != year)
		error ("%s → artist '%s' album '%s' track %u title '%s' year %u", path, g.artist, g.album, g.track, g.title, g.year);
}

void main () {
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
