/*
 * Credits: the people, the libraries BeatBox is built on and the services it talks to, in a
 * window of its own that scrolls (Preferences › About › Credits).
 */

using Gtk;

public class BeatBox.CreditsWindow : Gtk.Window {
	Box content = new Box(Orientation.VERTICAL, 8);

	public CreditsWindow(Gtk.Window? parent) {
		title = _("Credits");
		transient_for = parent;
		modal = true;
		set_default_size(560, 560);

		content.margin_start = content.margin_end = 18;
		content.margin_top = content.margin_bottom = 14;

		heading(_("Authors"));
		row(text("Scott Ringwelski\nVictor Eduardo M."));
		heading(_("Contributions"));
		row(text(_("Di Weng (%s): shortening texts by characters instead of bytes").printf(link("https://github.com/w1ndy/beatbox", "w1ndy")), true));
		heading(_("Artwork"));
		row(text("Scott Ringwelski\nDanielle Foré"));
		heading(_("2026 update"));
		row(text(_("Ported to GTK 4, GStreamer 1.0 and libsoup 3, with a new look, Cover Flow, the inline cover grid, the column browser, internet radio and podcast directories, online album art, synced lyrics, the visualizer and skins.")));

		heading(_("Software Libraries")); // not "Libraries": that is what BeatBox calls music collections
		row(text(_("BeatBox is written in %s and built on these free libraries:").printf(link("https://vala.dev", "Vala")), true));
		library("GTK %u.%u.%u".printf(Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()),
		        "https://www.gtk.org", _("the interface"), "LGPL 2.1+");
		library("GLib / GIO %u.%u.%u".printf(GLib.Version.major, GLib.Version.minor, GLib.Version.micro),
		        "https://docs.gtk.org/glib/", _("files, settings, D-Bus and the main loop"), "LGPL 2.1+");
		library("Cairo, Pango, GdkPixbuf", "https://www.cairographics.org", _("drawing, text and pictures"), "LGPL 2.1+ / MPL 1.1");
		library("libgee", "https://gitlab.gnome.org/GNOME/libgee", _("collections"), "LGPL 2.1+");
		library(Gst.version_string(), "https://gstreamer.freedesktop.org",
		        _("playback, the equalizer and effects, audio CDs, recording radio, the spectrum"), "LGPL 2.1+");
		library("TagLib", "https://taglib.org", _("reading and writing tags and covers"), "LGPL 2.1 / MPL 1.1");
		library("libsoup 3", "https://libsoup.org", _("everything from the internet"), "LGPL 2.1+");
		library("JSON-GLib", "https://gitlab.gnome.org/GNOME/json-glib", _("the answers of the online services"), "LGPL 2.1+");
		library("libxml2", "https://gitlab.gnome.org/GNOME/libxml2", _("podcast feeds and iTunes libraries"), "MIT");
		library("SQLite %s".printf(Sqlite.libversion()), "https://sqlite.org", _("the library database"), _("public domain"));
		library("libnotify", "https://gitlab.gnome.org/GNOME/libnotify", _("desktop notifications"), "LGPL 2.1+");
#if HAVE_PROJECTM
		library("libprojectM 4", "https://github.com/projectM-visualizer/projectm", _("the MilkDrop presets of the visualizer"), "LGPL 2.1");
		library("EGL / OpenGL (Mesa)", "https://www.mesa3d.org", _("drawing the visualizer off screen"), "MIT");
#endif
#if HAVE_GPOD
		library("libgpod", "https://sourceforge.net/projects/gtkpod/", _("syncing iPods"), "LGPL 2.1+");
#endif
		library("Chromaprint (fpcalc)", "https://acoustid.org/chromaprint", _("identifying songs by their sound, when installed"), "LGPL 2.1+");

		heading(_("Services"));
		row(text(_("Internet radio stations: %s").printf(link("https://www.radio-browser.info", "radio-browser.info") + ", " + link("https://directory.shoutcast.com", "SHOUTcast")
		         + ", " + link("https://laut.fm", "laut.fm") + ", " + link("https://dir.xiph.org", "Icecast"))
		         + "\n" + _("Podcasts: %s").printf(link("https://podcasts.apple.com", "Apple Podcasts"))
		         + "\n" + _("Album art: %s, with %s as fallback").printf(link("https://musicbrainz.org", "MusicBrainz") + " / " + link("https://coverartarchive.org", "Cover Art Archive"), link("https://music.apple.com", "Apple Music"))
		         + "\n" + _("Lyrics: %s").printf(link("https://lrclib.net", "LRCLIB"))
		         + "\n" + _("Song identification: %s").printf(link("https://acoustid.org", "AcoustID"))
		         + "\n" + _("Scrobbling: %s").printf(link("https://www.last.fm", "Last.fm") + ", " + link("https://listenbrainz.org", "ListenBrainz")), true));

		var scroll = new ScrolledWindow();
		scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
		scroll.vexpand = true;
		scroll.set_child(content);

		var close = new Button.with_label(_("Close"));
		close.halign = Align.END;
		close.margin_top = close.margin_bottom = close.margin_end = 10;
		close.clicked.connect(() => destroy());

		var box = new Box(Orientation.VERTICAL, 0);
		box.append(AquaScroll.wrap(scroll));
		box.append(new Separator(Orientation.HORIZONTAL));
		box.append(close);
		set_child(box);

		var keys = new EventControllerKey();
		keys.key_pressed.connect((keyval, code, state) => {
			if (keyval == Gdk.Key.Escape) {
				destroy();
				return true;
			}
			return false;
		});
		((Widget) this).add_controller(keys);
	}

	void heading(string s) {
		var label = new Label("");
		label.xalign = 0.0f;
		label.margin_top = 6;
		label.set_markup("<b>" + Markup.escape_text(s) + "</b>");
		content.append(label);
	}

	void row(Widget w) {
		w.margin_start = 10;
		content.append(w);
	}

	// name (a link), what BeatBox uses it for, and its license
	void library(string name, string url, string use, string license) {
		row(text("%s — %s <span alpha='60%%'>(%s)</span>".printf(link(url, name), Markup.escape_text(use), Markup.escape_text(license)), true));
	}

	static string link(string url, string label) {
		return "<a href=\"%s\">%s</a>".printf(url, Markup.escape_text(label));
	}

	static Label text(string s, bool markup = false) {
		var label = new Label("");
		label.xalign = 0.0f;
		label.wrap = true;
		label.max_width_chars = 70;
		label.selectable = false;
		if (markup)
			label.set_markup(s);
		else
			label.label = s;
		return label;
	}
}
