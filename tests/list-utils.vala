// meson test: ListUtils.move_to
string join (Gee.List<string> l) {
	var sb = new StringBuilder ();
	foreach (var s in l)
		sb.append (s);
	return sb.str;
}

Gee.LinkedList<string> make (string letters) {
	var l = new Gee.LinkedList<string> ();
	for (int i = 0; i < letters.length; i++)
		l.add (letters[i].to_string ());
	return l;
}

Gee.ArrayList<string> items (string letters) {
	var l = new Gee.ArrayList<string> ();
	for (int i = 0; i < letters.length; i++)
		l.add (letters[i].to_string ());
	return l;
}

void main () {
	var l = make ("abcde");
	BeatBox.ListUtils.move_to (l, items ("b"), 4);   // drop b before e
	assert (join (l) == "acdbe");
	l = make ("abcde");
	BeatBox.ListUtils.move_to (l, items ("d"), 0);   // to the front
	assert (join (l) == "dabce");
	l = make ("abcde");
	BeatBox.ListUtils.move_to (l, items ("bd"), 5);  // several, to the end, order kept
	assert (join (l) == "acebd");
	l = make ("abc");
	BeatBox.ListUtils.move_to (l, items ("xa"), 1);  // new item inserted, a moved
	assert (join (l) == "xabc");
	l = make ("abc");
	BeatBox.ListUtils.move_to (l, items ("cc"), 99); // duplicates ignored, index clamped
	assert (join (l) == "abc");
	l = make ("abc");
	BeatBox.ListUtils.move_to (l, items ("b"), 2);   // dropped right after itself: no change
	assert (join (l) == "abc");
}
