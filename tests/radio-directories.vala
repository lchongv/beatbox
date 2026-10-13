/* The station directories: the searches built from the filters, and what is read from each answer */
using BeatBox.Radio;

void test_radio_browser_searches () {
	var q = new Query ();
	q.country = "CL";
	var urls = radio_browser_searches (q);
	assert (urls.length == 1);
	assert (urls[0].has_prefix ("/json/stations/search?"));
	assert ("hidebroken=true" in urls[0] && "countrycode=CL" in urls[0]);
	assert ("order=votes" in urls[0] && "reverse=true" in urls[0]);
	assert (!("name=" in urls[0]) && !("tag=" in urls[0]));

	// a word is looked up as a name and as a tag
	q = new Query ();
	q.text = "jazz fm";
	urls = radio_browser_searches (q);
	assert (urls.length == 2);
	assert ("name=jazz%20fm" in urls[0] && !("tag=" in urls[0]));
	assert ("tag=jazz%20fm" in urls[1] && !("name=" in urls[1]));

	// ...unless a genre is chosen
	q.text = "fm";
	q.genre = "rock";
	urls = radio_browser_searches (q);
	assert (urls.length == 1);
	assert ("name=fm" in urls[0] && "tag=rock&tagExact=true" in urls[0]);

	q = new Query ();
	q.state = "Valparaíso";
	q.language = "spanish";
	q.codec = "AAC+";
	q.min_bitrate = 128;
	q.https_only = true;
	q.order = "name";
	urls = radio_browser_searches (q);
	assert ("state=Valpara%C3%ADso&stateExact=true" in urls[0]);
	assert ("language=spanish&languageExact=true" in urls[0]);
	assert ("codec=AAC%2B" in urls[0] && "bitrateMin=128" in urls[0] && "is_https=true" in urls[0]);
	assert ("order=name" in urls[0] && !("reverse=" in urls[0]));
	assert (!("countrycode=" in urls[0]));
}

void test_parse_radio_browser () {
	assert (parse_radio_browser ("<html>busy</html>") == null);
	var found = parse_radio_browser ("""[
		{"name": " Radio Uno ", "url": "http://a/x.pls", "url_resolved": "http://a/stream", "country": "Chile",
		 "tags": "jazz,smooth jazz", "codec": "MP3", "bitrate": 128},
		{"name": "Two", "url": "http://b/", "url_resolved": "", "country": "", "tags": "", "codec": "AAC+", "bitrate": 0},
		{"name": "", "url": "http://c/", "url_resolved": "http://c/"}]""");
	assert (found.size == 2);
	assert (found[0].name == "Radio Uno" && found[0].url == "http://a/stream" && found[0].country == "Chile");
	assert (found[0].genre == "jazz" && found[0].tags == "jazz, smooth jazz");
	assert (found[0].codec == "MP3" && found[0].bitrate == 128);
	assert (found[1].url == "http://b/" && found[1].genre == "" && found[1].codec == "AAC+");
}

void test_parse_choices () {
	assert (parse_choices ("", "name", null) == null);
	var countries = parse_choices ("""[{"name": "Chile", "iso_3166_1": "CL", "stationcount": 512},
		{"name": "", "iso_3166_1": "XX", "stationcount": 3}]""", "iso_3166_1", "stationcount");
	assert (countries.size == 1);
	assert (countries[0].name == "Chile" && countries[0].value == "CL" && countries[0].count == 512);
	var genres = parse_choices ("""[{"name": "Pop", "score": 3229.0}]""", "name", null);
	assert (genres[0].name == "Pop" && genres[0].value == "Pop" && genres[0].count == 0);
}

void test_shoutcast () {
	string form;
	var q = new Query ();
	assert (shoutcast_request (q, out form) == "https://directory.shoutcast.com/Home/Top" && form == "");
	q.genre = "R&B and Urban";
	assert (shoutcast_request (q, out form) == "https://directory.shoutcast.com/Home/BrowseByGenre");
	assert (form == "genrename=R%26B%20and%20Urban");
	q.text = "jazz";
	assert (shoutcast_request (q, out form) == "https://directory.shoutcast.com/Search/UpdateSearch" && form == "query=jazz");

	var found = parse_shoutcast ("""[
		{"ID": 99426190, "Name": "BEST SMOOTH JAZZ", "Format": "audio/mpeg", "Bitrate": 128, "Genre": "Smooth Jazz", "Listeners": 346},
		{"ID": 2, "Name": "AAC one", "Format": "audio/aacp", "Bitrate": 64, "Genre": "Pop"}]""");
	assert (found.size == 2);
	assert (found[0].name == "BEST SMOOTH JAZZ" && found[0].url == "https://yp.shoutcast.com/sbin/tunein-station.m3u?id=99426190");
	assert (found[0].codec == "MP3" && found[0].bitrate == 128 && found[0].genre == "Smooth Jazz" && found[0].tags == "Smooth Jazz");
	assert (found[1].codec == "AAC+");
}

void test_lautfm () {
	string names = """["-001rock", "just-jazz-2", "jazzradio", "radiojustjazz", "justjazz"]""";
	var matches = lautfm_matches (names, "Just Jazz", 10);
	assert (matches.length == 3);
	assert (matches[0] == "justjazz" && matches[1] == "just-jazz-2" && matches[2] == "radiojustjazz");
	assert (lautfm_matches (names, "jazz", 2).length == 2);
	assert (lautfm_matches (names, "", 10).length == 0);

	var found = parse_lautfm ("""[{"name": "justjazz", "display_name": "Just Jazz",
		"stream_url": "https://justjazz.stream.laut.fm/justjazz", "genres": ["Jazz", "Lounge"], "location": "Deutschland"}]""");
	assert (found.size == 1);
	assert (found[0].name == "Just Jazz" && found[0].url == "https://justjazz.stream.laut.fm/justjazz");
	assert (found[0].country == "Deutschland" && found[0].genre == "Jazz" && found[0].tags == "Jazz, Lounge");
}

const string ICECAST = """<directory><entry><server_name>Jazz &amp; Blues</server_name><server_type>audio/aacp</server_type><bitrate>64</bitrate><samplerate>44100</samplerate><channels>2</channels><listen_url>http://x:8000/jazz</listen_url><current_song></current_song><genre>Jazz Blues</genre></entry><entry><server_name>No address</server_name><server_type>audio/mpeg</server_type><bitrate>128</bitrate><listen_url></listen_url><genre>Rock</genre></entry><entry><server_name>Ogg One</server_name><server_type>application/ogg</server_type><bitrate>Quality 6</bitrate><listen_url>http://y/ogg</listen_url><genre></genre></entry><entry><server_name>Rock Hits</server_name><server_type>audio/mpeg</server_type><bitrate>192</bitrate><listen_url>http://z/rock</listen_url><genre>Rock 80s</genre></entry></directory>""";

void test_icecast () {
	var all = parse_icecast (ICECAST);
	assert (all.size == 3);
	assert (all[0].name == "Jazz & Blues" && all[0].url == "http://x:8000/jazz");
	assert (all[0].codec == "AAC+" && all[0].bitrate == 64 && all[0].genre == "Jazz" && all[0].tags == "Jazz Blues");
	assert (all[1].codec == "OGG" && all[1].bitrate == 0);
	// a broken file gives what was read before the error
	assert (parse_icecast (ICECAST.substring (0, ICECAST.index_of ("<entry><server_name>Ogg"))).size == 1);

	var q = new Query ();
	assert (filter (all, q, 10).size == 3);
	assert (filter (all, q, 2).size == 2);
	q.text = "BLUES";
	assert (filter (all, q, 10).size == 1);
	q.text = "";
	q.genre = "rock";
	assert (filter (all, q, 10)[0].name == "Rock Hits");
	q.genre = "";
	q.codec = "MP3";
	q.min_bitrate = 128;
	assert (filter (all, q, 10).size == 1);
	q.codec = "";
	q.min_bitrate = 100;
	assert (filter (all, q, 10).size == 1);
}

void test_playlists () {
	assert (is_playlist ("https://yp.shoutcast.com/sbin/tunein-station.m3u?id=5"));
	assert (is_playlist ("http://x/listen.PLS"));
	assert (!is_playlist ("http://x/stream.mp3"));
	assert (!is_playlist ("http://x/live.m3u8"));
	assert (first_stream ("#EXTM3U\n#EXTINF:-1,(#1 - 346/1000) Jazz\nhttp://162.252.171.80:8002/stream\n") == "http://162.252.171.80:8002/stream");
	assert (first_stream ("[playlist]\r\nNumberOfEntries=1\r\nFile1=https://s/x\r\nTitle1=X\r\n") == "https://s/x");
	assert (first_stream ("<html>gone</html>") == "");
}

void main () {
	test_radio_browser_searches ();
	test_parse_radio_browser ();
	test_parse_choices ();
	test_shoutcast ();
	test_lautfm ();
	test_icecast ();
	test_playlists ();
}
