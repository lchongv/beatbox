// meson test: TimeUtils.from_rfc822 (podcast dates)
void main () {
	Intl.setlocale (LocaleCategory.ALL, ""); // English names in any locale
	assert (BeatBox.TimeUtils.from_rfc822 ("Tue, 06 Oct 2026 10:00:00 GMT") == 1791280800);
	assert (BeatBox.TimeUtils.from_rfc822 ("Tue, 06 Oct 2026 12:00:00 +0200") == 1791280800);
	assert (BeatBox.TimeUtils.from_rfc822 ("Tue, 06 Oct 2026 07:30:00 -0230") == 1791280800);
	assert (BeatBox.TimeUtils.from_rfc822 ("6 October 2026 10:00 GMT") == 1791280800); // no weekday, long month, no seconds
	assert (BeatBox.TimeUtils.from_rfc822 ("Tue, 06 Xyz 2026 10:00:00 GMT") == 0);
	assert (BeatBox.TimeUtils.from_rfc822 ("Tue, 31 Feb 2026 10:00:00 GMT") == 0);
	assert (BeatBox.TimeUtils.from_rfc822 ("") == 0);
}
