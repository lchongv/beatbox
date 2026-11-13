/*
 * Port a GTK4: carga cada CSS con el analizador de GTK 4 e imprime los errores
 * como archivo:línea: mensaje. Sale con 1 si hubo algún error.
 *   valac --pkg gtk4 -o build-gtk4/csscheck tools/gtk4-csscheck.vala
 *   xvfb-run -a build-gtk4/csscheck data/theme.css skins/<tema>/skin.css ...
 * Necesita pantalla: GTK la pide al iniciarse.
 */
int main (string[] args) {
	if (!Gtk.init_check ()) {
		stderr.printf ("sin pantalla: usa xvfb-run\n");
		return 2;
	}
	int errors = 0;
	for (int i = 1; i < args.length; i++) {
		var file = args[i];
		var provider = new Gtk.CssProvider ();
		provider.parsing_error.connect ((section, error) => {
			errors++;
			stdout.printf ("%s:%d: %s\n", file, (int) section.get_start_location ().lines + 1, error.message);
		});
		provider.load_from_path (file);
	}
	if (errors == 0)
		stdout.printf ("OK: %d archivo(s) sin errores\n", args.length - 1);
	return errors == 0 ? 0 : 1;
}
