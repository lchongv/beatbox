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

using Gee;
using Gtk;

public class BeatBox.PodcastSourceView : SourceView {
	HashMap<int, Device> welcome_screen_keys;
	
	// For View implementation
	GLib.Menu podcastMenu;
	
	public PodcastSourceView() {
		base(App.library.podcast_library.medias(), App.window.setups.get_setup(ListSetupInterface.PODCAST_KEY));
		
		media_representation = _("podcast");
		
		// Setup welcome screen
		welcome_screen = new Granite.Widgets.Welcome(_("Subscribe to Podcasts"), _("No Podcasts were found."));
		welcome_screen_keys = new HashMap<int, Device>();
		var podcast_icon = App.icons.PODCAST.render (IconSize.DIALOG, null);
		welcome_screen.append_with_pixbuf(podcast_icon, _("Find Podcasts"), _("Search the Apple Podcasts directory."));
		welcome_screen.append("list-add", _("Subscribe by Address"), _("Paste the address of a podcast RSS feed."));
		welcome_screen.activated.connect(welcome_screen_activated);
		
		list_view = new PodcastList (tvs);
		album_view = new AlbumGrid(this, tvs);
		error_box = new EmbeddedAlert();
		pack_widgets();
		
		var find = action_button ("system-search-symbolic", _("Find Podcasts…"));
		var subscribe = action_button ("list-add-symbolic", _("Subscribe by Address…"));
		var refresh = action_button ("view-refresh-symbolic", _("Download new Episodes"));
		find.clicked.connect (() => { new DirectoryDialog (DirectoryDialog.Kind.PODCAST); });
		subscribe.clicked.connect (() => { App.actions.add_podcast_feed.activate(null); });
		refresh.clicked.connect (() => { App.actions.refresh_podcasts.activate(null); });
		pack_action_bar ({ find, subscribe, refresh });
		
		// Setup context menu
		podcastMenu = new GLib.Menu();
		podcastMenu.append(_("Find Podcasts…"), "view.find");
		add_context_action("find", () => { new DirectoryDialog (DirectoryDialog.Kind.PODCAST); });
		podcastMenu.append_item(App.actions.model_item(App.actions.add_podcast_feed));
		podcastMenu.append_item(App.actions.model_item(App.actions.refresh_podcasts));
		
		// Populate views
		set_media_sync(original_medias, false);
		
		// Setup signal handlers
		App.library.podcast_library.medias_updated.connect (update_medias);
		App.library.podcast_library.medias_added.connect (add_medias);
		App.library.podcast_library.medias_removed.connect (remove_medias);
	}
	
	protected override void pre_set_as_current_view() {
		
	}
	
	protected override void set_default_warning () {
		error_box.set_alert (_("No Podcasts Found"), _("Use “Find Podcasts…” above to search the directory, or “Subscribe by Address…” to paste an RSS feed."), true, Gtk.MessageType.INFO);
	}
	
	void welcome_screen_activated(int index) {
		if(index == 0)
			new DirectoryDialog (DirectoryDialog.Kind.PODCAST);
		else
			App.actions.add_podcast_feed.activate(null);
	}
	
	/** Specific implementations for View interface **/
	public override View.ViewType get_view_type() {
		return View.ViewType.PODCAST;
	}
	
	public override Object? get_object() {
		return null;
	}
	
	public override Gdk.Pixbuf get_view_icon() {
		return App.icons.PODCAST.render(IconSize.MENU, null);
	}
	
	public override string get_view_name() {
		return _("Podcasts");
	}
	
	public override GLib.MenuModel? get_context_menu() {
		return podcastMenu;
	}
	
	public override bool can_receive_drop() {
		return false;
	}
	
	public override void drag_received(Gtk.SelectionData data) {
		
	}
	
	public override SideTreeCategory get_sidetree_category() {
		return SideTreeCategory.LIBRARY;
	}
	
	// podcast context menu
	public void podcastAddClicked() {
		AddPodcastWindow apw = new AddPodcastWindow();
		apw.show();
	}
	
	public void podcastRefreshClicked() {
		App.podcasts.find_new_podcasts();
	}
}

