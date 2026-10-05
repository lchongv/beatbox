/* JSON answers: what the directory, cover, lyrics and ListenBrainz code may get back */
void main () {
	assert (BeatBox.Http.json_objects ("") == null);
	assert (BeatBox.Http.json_objects ("<html>busy</html>") == null);
	assert (BeatBox.Http.json_objects ("{\"error\": \"rate limit\"}", "results") == null);
	assert (BeatBox.Http.json_objects ("{\"results\": 3}", "results") == null);
	assert (BeatBox.Http.json_objects ("[1, {\"a\": 2}, null]").size == 1);
	var results = BeatBox.Http.json_objects ("{\"results\": [{\"name\": \"x\"}]}", "results");
	assert (results.size == 1 && results[0].get_string_member ("name") == "x");

	assert (BeatBox.Http.json_object ("") == null);
	assert (BeatBox.Http.json_object ("[1]") == null);
	assert (BeatBox.Http.json_object ("{\"valid\": true}").get_boolean_member ("valid"));
}
