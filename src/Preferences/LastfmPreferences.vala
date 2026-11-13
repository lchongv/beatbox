/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 */

using Gtk;

public class BeatBox.LastfmPreferences : GLib.Object, PreferencesSection {
	public PreferencesSectionCategory category { get { return PreferencesSectionCategory.GENERAL; } }
	public string title { get { return _("Scrobbling"); } }
	public Gdk.Pixbuf? icon { get { return null; } }
	public Widget widget { get { return content; } }

	Box content;
	Label auth_info;
	Box login_box;
	Entry username;
	Entry password;
	Button login;
	Button logout;
	Gtk.Spinner is_working;

	Entry lb_token;
	Label lb_info;
	Button lb_connect;
	Button lb_disconnect;

	public LastfmPreferences() {
		content = new Box(Orientation.VERTICAL, 0);
		content.spacing = 10;

		auth_info = new Label("");
		username = new Entry();
		password = new Entry();
		login = new Button.with_label(_("Login"));
		logout = new Button.with_label(_("Logout"));
		is_working = new Gtk.Spinner();

		var auth_label = new Label("");

		// fancy up the category labels
		auth_label.xalign = 0.0f;
		auth_label.set_markup("<b>Last.fm</b>");

		auth_info.xalign = 0.0f;
		auth_info.wrap = true;
		password.set_visibility(false);

		// The login entry boxes
		login_box = new Box(Orientation.HORIZONTAL, 0);
		var left_box = new Box(Orientation.VERTICAL, 0);
		var right_box = new Box(Orientation.VERTICAL, 0);

		var username_label = new Label("");
		var password_label = new Label("");
		username_label.set_markup("<b>" + _("Username:") + "</b>");
		password_label.set_markup("<b>" + _("Password:") + "</b>");
		username_label.xalign = 0.0f;
		password_label.xalign = 0.0f;

		username_label.valign = Align.CENTER;
		left_box.append(username_label);
		password_label.valign = Align.CENTER;
		left_box.append(password_label);
		right_box.append(username);
		right_box.append(password);
		login_box.append(UI.wrap_alignment(left_box, 0, 4, 0, 0));
		right_box.hexpand = true;
		login_box.append(right_box);

		left_box.vexpand = true;
		left_box.homogeneous = true;
		login_box.vexpand = false;

		var button_box = new Box(Orientation.HORIZONTAL, 6);
		button_box.halign = Align.END;
		button_box.append(is_working);
		button_box.append(login);
		button_box.append(logout);

		// Pack all widgets
		content.append(auth_label);
		content.append(UI.wrap_alignment(auth_info, 0, 0, 0, 10));
		content.append(UI.wrap_alignment(login_box, 0, 0, 0, 10));
		content.append(UI.wrap_alignment(button_box, 0, 0, 0, 10));

		login.clicked.connect(login_click);
		logout.clicked.connect(logout_click);
		App.info.lastfm.login_returned.connect(login_returned);
		App.info.lastfm.logged_out.connect(logged_out);

		// the spinner stays hidden: it was never shown in GTK3 either (see login_click)
		is_working.visible = false;

		// the login and logout parts are shown or hidden by the show_*_gui methods
		if(!String.is_empty(App.info.lastfm.session_key)) {
			show_loggedin_gui();
		}
		else {
			show_loginprompt_gui();
		}

		build_listenbrainz();
		build_acoustid();
	}

	/* AcoustID: the application key the song editor's Identify button needs */
	void build_acoustid() {
		var heading = new Label("");
		heading.xalign = 0.0f;
		heading.set_markup("<b>AcoustID</b>");
		heading.margin_top = 12;
		content.append(heading);

		var info = new Label("");
		info.xalign = 0.0f;
		info.wrap = true;
		info.max_width_chars = 60;
		info.set_markup(_("To identify songs by their sound (Edit Song Info › Identify), register an application at %s and paste its key here.")
		                .printf("<a href=\"https://acoustid.org/new-application\">acoustid.org</a>"));
		content.append(UI.wrap_alignment(info, 0, 0, 0, 10));

		var key = new Entry();
		key.placeholder_text = _("Application key");
		key.text = App.settings.lastfm.acoustid_key;
		key.changed.connect(() => { App.settings.lastfm.acoustid_key = key.text.strip(); });
		content.append(UI.wrap_alignment(key, 0, 0, 0, 10));
	}

	/* ListenBrainz: the user token from listenbrainz.org/settings, checked before it is kept */
	void build_listenbrainz() {
		var heading = new Label("");
		heading.xalign = 0.0f;
		heading.set_markup("<b>ListenBrainz</b>");
		heading.margin_top = 12;
		content.append(heading);

		lb_info = new Label("");
		lb_info.xalign = 0.0f;
		lb_info.wrap = true;
		lb_info.max_width_chars = 60;
		content.append(UI.wrap_alignment(lb_info, 0, 0, 0, 10));

		lb_token = new Entry();
		lb_token.visibility = false;
		lb_token.placeholder_text = _("User token");
		lb_token.hexpand = true;
		lb_connect = new Button.with_label(_("Connect"));
		lb_disconnect = new Button.with_label(_("Disconnect"));
		var row = new Box(Orientation.HORIZONTAL, 6);
		row.append(lb_token);
		row.append(lb_connect);
		row.append(lb_disconnect);
		content.append(UI.wrap_alignment(row, 0, 0, 0, 10));

		lb_token.activate.connect(listenbrainz_connect);
		lb_connect.clicked.connect(listenbrainz_connect);
		lb_disconnect.clicked.connect(() => {
			App.settings.lastfm.listenbrainz_token = "";
			App.settings.lastfm.listenbrainz_user = "";
			show_listenbrainz();
		});
		// the preferences window shows everything: these are shown and hidden here
		show_listenbrainz();
	}

	void show_listenbrainz(string? problem = null) {
		bool connected = App.settings.lastfm.listenbrainz_token != "";
		lb_token.visible = lb_connect.visible = !connected;
		lb_disconnect.visible = connected;
		lb_token.sensitive = lb_connect.sensitive = true;
		if(connected)
			lb_info.set_markup(_("Your listens are sent to ListenBrainz as %s.").printf("<b>" + Markup.escape_text(App.settings.lastfm.listenbrainz_user) + "</b>"));
		else
			lb_info.set_markup((problem != null ? "<b>" + Markup.escape_text(problem) + "</b>\n" : "")
			                   + _("Paste the user token from %s to send your listens there.").printf("<a href=\"https://listenbrainz.org/settings/\">listenbrainz.org/settings</a>"));
	}

	void listenbrainz_connect() {
		string token = lb_token.text.strip();
		if(token == "")
			return;
		lb_token.sensitive = lb_connect.sensitive = false;
		ListenBrainz.validate(token, (valid, user) => {
			if(valid) {
				App.settings.lastfm.listenbrainz_user = user;
				App.settings.lastfm.listenbrainz_token = token;
				lb_token.text = "";
				show_listenbrainz();
			} else {
				show_listenbrainz(_("ListenBrainz didn't accept that token (or couldn't be reached)."));
			}
		});
	}

	void login_click() {
		// TODO: Show this once gtk gets its act together. (Also, need to force it to be smaller)
		is_working.start();

		App.info.lastfm.authenticate_user(username.get_text(), password.get_text());
	}

	void login_returned(bool success) {
		is_working.stop();

		if(success) {
			show_loggedin_gui();
		}
		else {
			show_loginfailed_gui();
		}
	}

	void logout_click() {
		App.info.lastfm.logout_user();
	}

	void logged_out() {
		show_loginprompt_gui();
	}

	void show_loginprompt_gui() {
		show_login(false);
	}

	void show_loggedin_gui() {
		auth_info.set_markup(_("You are logged in as %s.").printf("<b>" + Markup.escape_text(App.info.lastfm.username) + "</b>"));
		show_login(true, true);
	}

	void show_loginfailed_gui() {
		auth_info.set_markup(_("BeatBox was unable to log in as %s. Please try again.").printf("<b>" + Markup.escape_text(username.get_text()) + "</b>"));
		show_login(true);
	}

	/* the message above the form, and either the login form or the logout button */
	void show_login(bool info, bool logged_in = false) {
		auth_info.visible = info;
		login_box.visible = login.visible = !logged_in;
		logout.visible = logged_in;
	}

	public void save() {

	}

	public void cancel() {

	}
}
