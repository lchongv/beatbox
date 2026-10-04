// meson test: String.ellipsize counts characters, not bytes
void main () {
	assert (BeatBox.String.ellipsize ("Ñandúes Ñandúes", 10) == "Ñandúes...");
	assert (BeatBox.String.ellipsize ("corto", 10) == "corto");
	assert (BeatBox.String.ellipsize ("áéíóúáéíóú", 10) == "áéíóúáéíóú");
	assert (BeatBox.String.ellipsize ("áéíóúáéíóúx", 10).validate ());
}
