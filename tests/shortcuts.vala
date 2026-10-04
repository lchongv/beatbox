// meson test: Shortcuts matching, reassignment and saving
void main () {
	string[] stored = { "next=<Control>n" };
	int played = 0, nexted = 0;
	BeatBox.Shortcuts.init (stored, (list) => { stored = list; });
	var play = BeatBox.Shortcuts.register ("play", "Play", "space", () => { played++; });
	var next = BeatBox.Shortcuts.register ("next", "Next", "<Control>Right", () => { nexted++; });

	assert (next.accel == "<Control>n");                                  // the saved key wins over the default
	assert (BeatBox.Shortcuts.activate (Gdk.Key.space, 0) && played == 1);
	assert (BeatBox.Shortcuts.activate (Gdk.Key.N, Gdk.ModifierType.CONTROL_MASK) && nexted == 1); // case-insensitive
	assert (!BeatBox.Shortcuts.activate (Gdk.Key.n, 0));                  // modifiers must match
	assert (!BeatBox.Shortcuts.activate (Gdk.Key.space, Gdk.ModifierType.CONTROL_MASK));
	assert (BeatBox.Shortcuts.activate (Gdk.Key.space, Gdk.ModifierType.MOD2_MASK)); // NumLock doesn't count

	var taken = BeatBox.Shortcuts.set_accel (next, "space");                // taken from "play"
	assert (taken == play && play.accel == "" && next.accel == "space");
	assert (stored.length == 2 && stored[0] == "play=" && stored[1] == "next=space");
	BeatBox.Shortcuts.restore_defaults ();
	assert (play.accel == "space" && next.accel == "<Control>Right");
}
