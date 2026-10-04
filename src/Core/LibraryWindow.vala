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
using Gee;
using Notify;

public class BeatBox.LibraryWindow : Gtk.Window, BeatBox.LibraryWindowInterface {
	public static Granite.Application app { get; private set; }
	public BeatBox.MediaKeyListener mkl;

/** It is required to declare this globally, otherwise vala thinks there 
 * are 0 references to it and frees it, resulting in a quicklist with no events **/
#if HAVE_INDICATE
	private BeatBox.SoundMenuIntegration sound_menu;
#endif
#if HAVE_UNITY
	private UnityIntegration unity;
#endif
	
	public TopDisplayInterface top_display { get; protected set; }
	public NowPlayingViewInterface now_playing { get; protected set; }
	public ListSetupInterface setups { get; protected set; }
	
	public ulong video_area_xid {
		get { return ((NowPlayingView)now_playing).video_area_xid; }
	}
	
	public bool dragging_from_music { get; set; }
	public bool initializationFinished { get; private set; }
	
	 /* Window state properties */
    private bool window_maximized = false;
    private bool window_fullscreen = false;
	
	// Main containers
	Box verticalBox;
	ToolItem viewSelectorBin;
	ToolItem searchFieldBin;
	bool mini = false; // mini player: only the toolbar (controls and LCD) is left
	Notebook all_views { get; private set; } // mainViews, songInfo, possibly video later on
	public Notebook mainViews { get; private set; }
	public Gtk.Paned sourcesToMedias { get; private set; } //allows for draggable
	Box contentBox;
	Box sideBox;
	
	// Side box
	ScrolledWindow sideTreeScroll;
	public SideTreeView sideTree { get; private set; }
	Toolbar sideTreeBar;
	ToolButton sideTreeAdd;
	ToolButton sideTreeRemove;
	ToolButton sideTreeOptions;
	
	Gtk.Menu sideTreeAddMenu;
	Gtk.Menu sideTreeMenu;
	
	// File not found stuff
	InfoBar infoBar;
	Label infoBarLabel;
	LinkedList<Media> file_not_found_pileup;
	
	// The top bar
	Toolbar topControls;
	ToolButton previousButton;
	ToolButton playButton;
	ToolButton nextButton;
	Granite.Widgets.ModeButton viewSelector;
	ToggleButton showSongInfo;
	AdvancedSearchBox searchField;
	
	public StatusBar statusBar { get; private set; }
	
	// basic file stuff
	private Gtk.Menu settingsMenu;
	
	// state stuff
	private Gtk.Widget focusAfterSearch;
	private HashMap<Object, View> object_to_view;
	
	public Notify.Notification notification { get; private set; }

	public LibraryWindow(Granite.Application bb_app) {
		app = bb_app;
		
		// Init LibNotify
		Notify.init ("beatbox");
		
		//various objects
		mkl = new MediaKeyListener();
		
		// Always initialize MPRIS2
		debug("Initializing MPRIS 2.0\n");
		var mpris = new BeatBox.MPRIS();
		mpris.initialize();
		
#if HAVE_INDICATE
		debug("Initializing SoundMenu integration\n");
		sound_menu = new BeatBox.SoundMenuIntegration();
		sound_menu.initialize();
#endif
#if HAVE_UNITY
		debug("Initializing Unity integration\n");
		unity = new BeatBox.UnityIntegration();
		if(!unity.initialize()) {
			warning("Unity integration failed\n");
		}
#endif

		setups = new ListSetupManager();

		// This makes a very hefty assumption that the player will be
		// accessible to re-show through mpris clients (soundmenu). In the case
		// that there isn't, the player will reshow when user tries to open
		// it (app-uniqueness).
		this.delete_event.connect(on_delete);

		dragging_from_music = false;

		//FIXME? this.App.playback.player.media_not_found.connect(media_not_found);
		
		App.library.medias_imported.connect(medias_imported);
		App.library.medias_removed.connect(medias_removed);
		
		App.playback.media_played.connect(media_played);
		App.playback.start_playback_requested.connect(start_playback_requested);
		App.playback.playback_played.connect(playback_changed);
		App.playback.playback_paused.connect(playback_changed);
		App.playback.playback_stopped.connect(playback_stopped);
		App.playback.video_enabled.connect(video_enabled);
		
		App.playback.media_not_found.connect(media_not_found);
		App.playback.media_found.connect(media_found);
		
		App.operations.operation_started.connect(operation_started);
		App.operations.operation_finished.connect(operation_finished);
		
		App.devices.device_added.connect(device_added);
		App.devices.device_removed.connect(device_removed);
		
		App.playlists.playlist_added.connect(playlist_added);
		App.playlists.playlist_changed.connect(playlist_changed);
		App.playlists.playlist_removed.connect(playlist_removed);

		this.destroy.connect (on_quit);
		this.size_allocate.connect (() => {
			if (!(window_maximized || window_fullscreen || mini))
				get_size (out last_width, out last_height);
		});

		object_to_view = new HashMap<Object, View>();
	}

	/* The app icon cut into a circle that fills the round menu button.
	 * The icon is a rounded square with ~8 % margin, so it is drawn
	 * larger and its middle is clipped. */
	static Gdk.Pixbuf? round_app_icon (int size) {
		var big = App.icons.BEATBOX.render (null, null, (int)(size / 0.84));
		if (big == null)
			return null;
		var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, size, size);
		var cr = new Cairo.Context (surface);
		cr.arc (size / 2.0, size / 2.0, size / 2.0, 0, 2 * Math.PI);
		cr.clip ();
		Gdk.cairo_set_source_pixbuf (cr, big, (size - big.width) / 2.0, (size - big.height) / 2.0);
		cr.paint ();
		return Gdk.pixbuf_get_from_surface (surface, 0, 0, size, size);
	}

	public void build_ui() {
		message ("Building user interface\n");
		
		// Start by initializing the window and widgets to create the UI
		setup_window ();
        setup_widgets ();
        
        // We have all the widgets, so show to user even though most views aren't built yet
        this.show();
        
        // Load up the different views. Some loads are asynchronous.
		build_main_views ();
		load_playlists_async ();
		
		App.devices.load_pre_existing_devices();
		
		// Now that the important views are loaded and all widgets are
		// initialized, we can see that initialization is finished.
		initializationFinished = true;
		
		// Now that views can respond, set text
		// TODO: Idle's and async processes makes this not work. We need
		// to make sure that this is not called until the current view is opened and
		// it has media in it.
		// searchField.set_text(App.settings.main.search_string);
	}

	public static Gtk.Widget wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
		// padding as extra margins (Gtk.Alignment is deprecated)
		widget.margin_top += top;
		widget.margin_end += right;
		widget.margin_bottom += bottom;
		widget.margin_start += left;
		return widget;
	}
	
	// Initializes properties, values, and event handlers on the window itself
	private inline void setup_window () {
        debug ("setting up main window");

        this.height_request = 440;
        this.width_request = 750;
        this.window_position = Gtk.WindowPosition.CENTER;

        // set the size based on saved settings
        this.set_default_size (App.settings.saved_state.window_width, App.settings.saved_state.window_height);
		if(App.settings.saved_state.window_state == Settings.WindowState.MAXIMIZED) {
			window_maximized = true;
			this.maximize();
		}

        this.set_title ("BeatBox");
        // several sizes, for window lists that take the icon from the window itself (X11)
        var icons = new GLib.List<Gdk.Pixbuf> ();
        foreach (int px in new int[] { 16, 32, 48, 64, 128 })
            icons.append (App.icons.BEATBOX.render (null, null, px));
        this.set_icon_list (icons);

        // set up drag dest stuff
        Gtk.drag_dest_set (this, DestDefaults.ALL, {}, Gdk.DragAction.MOVE);
        Gtk.drag_dest_add_uri_targets (this);
        this.drag_data_received.connect (dragReceived);
		
        debug ("done with main window");
        
        this.key_press_event.connect (keyPressed);
        this.set_focus.connect(focused_widget_changed);
        this.window_state_event.connect(window_state_changed);
    }
    
    private inline void setup_widgets() {
		/* Initialize all components */
		all_views = new Notebook();
		verticalBox = new Box(Orientation.VERTICAL, 0);
		sourcesToMedias = new Gtk.Paned(Orientation.HORIZONTAL);
		contentBox = new Box(Orientation.VERTICAL, 0);
		mainViews = new Notebook ();
		now_playing = new NowPlayingView();
		sideBox = new Box(Orientation.VERTICAL, 0);

		sideTree = new SideTreeView();
		sideTreeScroll = new ScrolledWindow(null, null);
		sideTreeBar = new Toolbar();
		sideTreeAdd = new ToolButton(null, "Add...");
		sideTreeRemove = new ToolButton(null, "Remove...");
		sideTreeOptions = new ToolButton(null, "Options...");
		settingsMenu = new Gtk.Menu();
		topControls = new Toolbar();
		previousButton = new ToolButton(null, null);
		previousButton.icon_name = "media-skip-backward-symbolic";
		playButton = new ToolButton(null, null);
		playButton.icon_name = "media-playback-start-symbolic";
		nextButton = new ToolButton(null, null);
		nextButton.icon_name = "media-skip-forward-symbolic";
		top_display = new TopDisplay();
		viewSelector = new Granite.Widgets.ModeButton();
		showSongInfo = new ToggleButton();
		searchField = new AdvancedSearchBox();
		searchField.width_request = 250; // 1.5 × its natural width
		infoBarLabel = new Label("");
		infoBar = new InfoBar();
		file_not_found_pileup = new LinkedList<Media>();
		statusBar = new StatusBar();
		
		notification = new Notify.Notification ("", null, null);
		
		/* Toolbar with media controls, search, app menu, etc. */
		ToolItem top_displayBin = new ToolItem();
		viewSelectorBin = new ToolItem();
		ToolItem showSongInfoBin = new ToolItem();
		searchFieldBin = new ToolItem();
		
		showSongInfo.get_style_context().add_class("raised");
		showSongInfoBin.add(showSongInfo);
		showSongInfoBin.margin_start = 12;
		showSongInfo.set_image(App.icons.INFO.render_image (IconSize.MENU, viewSelector.get_style_context()));
		
		// The LCD is always visible; the app name fills it when idle
		var lcd = new Box(Orientation.HORIZONTAL, 0);
		lcd.get_style_context().add_class("lcd");
		var lcdCover = new LcdCover();
		var lcdCoverBox = new EventBox(); // an Image gets no clicks of its own
		lcdCoverBox.add(lcdCover);
		lcdCoverBox.button_press_event.connect(() => { lcdCover.show_full_size(this); return true; });
		lcd.pack_start(lcdCoverBox, false, false, 0); // thumbnail at the left edge (optional)
		var lcd_logo = new Label("BeatBox");
		lcd_logo.get_style_context().add_class("lcd-logo");
		lcd_logo.hexpand = true;
		lcd.pack_start(lcd_logo, true, true, 0);
		lcd.pack_start(top_display, true, true, 0);
		top_display.notify["visible"].connect(() => { lcd_logo.visible = !top_display.visible; });
		top_displayBin.add(lcd);
		top_displayBin.set_expand(true);
		top_displayBin.margin_start = 12;
		
		viewSelector.append(App.icons.VIEW_DETAILS.render_image (IconSize.MENU));
		viewSelector.append(App.icons.VIEW_ICONS.render_image (IconSize.MENU));
		viewSelector.append(new Image.from_resource ("/net/launchpad/beatbox/icons/16x16/actions/view-coverflow-symbolic.svg"));
		viewSelector.valign = showSongInfo.valign = Gtk.Align.CENTER;
		viewSelector.selected = App.settings.saved_state.view_mode;
		
		viewSelectorBin.margin_start = 12;
		viewSelectorBin.add(viewSelector);
		
		searchFieldBin.add(searchField);
		searchField.valign = Gtk.Align.CENTER; // half the height of the LCD, not the whole toolbar
		searchFieldBin.margin_start = 12;
		searchFieldBin.margin_end = 6;
		
		//settingsMenu.append(App.actions.menu_item(App.actions.import_folder));
		//settingsMenu.append(App.actions.menu_item(App.actions.rescan_music_folder));
		//settingsMenu.append(new SeparatorMenuItem());
		var miniItem = new Gtk.MenuItem.with_mnemonic(_("_Mini Player"));
		miniItem.activate.connect(toggle_mini);
		settingsMenu.append(miniItem);
		settingsMenu.append(App.actions.menu_item(App.actions.show_equalizer));
		settingsMenu.append(App.actions.menu_item(App.actions.show_preferences));
		settingsMenu.append(App.actions.menu_item(App.actions.exit));
		
		topControls.set_vexpand (false);
		topControls.set_hexpand (true);
		
		topControls.insert(previousButton, -1);
		topControls.insert(playButton, -1);
		topControls.insert(nextButton, -1);
		topControls.insert(viewSelectorBin, -1);
		// the "i" (now playing) toggle is gone: redundant; Ctrl+I still opens that view
		topControls.insert(top_displayBin, -1);
		topControls.insert(searchFieldBin, -1);
		var appmenu_button = new Gtk.MenuButton ();
		var appmenu_icon = new Gtk.Image.from_pixbuf (round_app_icon (38));
		appmenu_button.image = appmenu_icon;
		appmenu_button.get_style_context ().add_class ("round-menu");
		appmenu_button.set_size_request (40, 40);
		// the round button is 80 % of the LCD's height
		int appmenu_size = 0;
		lcd.size_allocate.connect ((alloc) => {
			int size = (int)(alloc.height * 0.8);
			if (size == appmenu_size || size < 16)
				return;
			appmenu_size = size;
			Idle.add (() => {
				appmenu_icon.pixbuf = round_app_icon (size - 2); // minus the 1px border
				appmenu_button.set_size_request (size, size);
				return false;
			});
		});
		appmenu_button.valign = appmenu_button.halign = Gtk.Align.CENTER;
		appmenu_button.popup = settingsMenu;
		settingsMenu.show_all ();
		var appmenu = new Gtk.ToolItem ();
		appmenu.add (appmenu_button);
		topControls.insert(appmenu, -1);
		
		// Info bar to give notices about file not found errors
		infoBar.set_message_type(Gtk.MessageType.ERROR);
		var action_hbox = new Box(Orientation.HORIZONTAL, 0);
		((Gtk.Container)infoBar.get_action_area()).add(action_hbox);
		var resolve_button = new Button.with_label(_("Resolve"));
		action_hbox.pack_start(resolve_button, false, true, 0);
		
		resolve_button.clicked.connect( () => { info_bar_response(Gtk.ResponseType.YES); });
		
		infoBarLabel.set_justify(Justification.LEFT);
		infoBarLabel.set_single_line_mode(true);
		infoBarLabel.ellipsize = Pango.EllipsizeMode.END;
		
		((Gtk.Container)infoBar.get_content_area()).add(infoBarLabel);
		
		// Side tree
		sideTreeScroll = new ScrolledWindow(null, null);
		sideTreeScroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		sideTreeScroll.get_style_context().add_class("sidebar-scroll");
		sideTreeScroll.add(sideTree);
		
		var side_add_image = App.icons.render_image ("list-add-symbolic", Gtk.IconSize.MENU);
		var side_remove_image = App.icons.render_image ("list-remove-symbolic", Gtk.IconSize.MENU);
		var side_options_image = App.icons.render_image ("document-properties-symbolic", Gtk.IconSize.MENU);
		
		sideTreeAdd.set_icon_widget(side_add_image);
		sideTreeRemove.set_icon_widget(side_remove_image);
		sideTreeOptions.set_icon_widget(side_options_image);
		
		sideTreeBar.get_style_context().add_class(STYLE_CLASS_INLINE_TOOLBAR);
		sideTreeBar.icon_size = Gtk.IconSize.MENU;
		
		var sideToolbarSeparator = new SeparatorToolItem();
		sideToolbarSeparator.expand = true;
		sideToolbarSeparator.vexpand = false;
		sideToolbarSeparator.draw = false;
		
		sideTreeBar.insert(sideTreeAdd, -1);
		sideTreeBar.insert(sideTreeRemove, -1);
		//sideTreeBar.insert(sideToolbarSeparator, -1);
		sideTreeBar.insert(sideTreeOptions, -1);
		
		sideBox.pack_start(sideTreeScroll, true, true, 0);
		//sideBox.pack_end(sideTreeBar, false, false, 0);
		
		sideTreeAddMenu = new Gtk.Menu();
		sideTreeAddMenu.append(App.actions.menu_item(App.actions.create_playlist));
		sideTreeAddMenu.append(App.actions.menu_item(App.actions.create_smart_playlist));
		sideTreeAddMenu.append(App.actions.menu_item(App.actions.import_playlist));
		sideTreeAddMenu.append(new SeparatorMenuItem());
		sideTreeAddMenu.append(App.actions.menu_item(App.actions.add_podcast_feed));
		sideTreeAddMenu.append(new SeparatorMenuItem());
		sideTreeAddMenu.append(App.actions.menu_item(App.actions.import_station));
		
		sideTreeMenu = new Gtk.Menu();
		sideTreeMenu.append(App.actions.menu_item(App.actions.show_duplicates));
		sideTreeMenu.append(App.actions.menu_item(App.actions.hide_duplicates));
		sideTreeMenu.append(new SeparatorMenuItem());
		sideTreeMenu.append(App.actions.menu_item(App.actions.refresh_podcasts));
		
		// Hide notebook tabs and border
		mainViews.show_tabs = false;
		mainViews.show_border = false;
		
		all_views.show_tabs = false;
		all_views.show_border = false;
		
		// Add the final boxes to the window
		all_views.append_page(mainViews);
		all_views.append_page(now_playing);
		
		contentBox.pack_start(infoBar, false, true, 0);
		contentBox.pack_start(all_views, true, true, 0);
		
		sourcesToMedias.position = App.settings.saved_state.sidebar_width;
		sourcesToMedias.pack1(sideBox, false, true);
		sourcesToMedias.pack2(contentBox, true, true);
		
		// TEMPORARY
		/*var my_menu = new GLib.Menu();
            
            var file_menu_item = new GLib.MenuItem("File", "file");
            var file_menu = new GLib.Menu();
            var import_item = new GLib.MenuItem("Import", "import");
            
            file_menu_item.set_submenu(file_menu);
            file_menu.append_item(import_item);
            my_menu.append_item(file_menu_item);
		var top_menu = new MenuBar.from_model(my_menu);
		
		verticalBox.pack_start(top_menu, false, true, 0);*/
		// The toolbar is the window's title bar: no separate system title bar,
		// traffic lights in the top-left corner, above the transport buttons
		var titlebar = new Overlay();
		titlebar.add(topControls);
		titlebar.add_overlay(create_traffic_lights());
		set_titlebar(titlebar);
		verticalBox.pack_start(sourcesToMedias, true, true, 0);
		verticalBox.pack_end(statusBar, false, true, 0);
		this.add(verticalBox);
		
		// Set theming
		topControls.get_style_context().add_class(STYLE_CLASS_PRIMARY_TOOLBAR);
		topControls.get_style_context().add_class("app-header");
		get_style_context().add_class("beatbox");
		previousButton.get_style_context().add_class("transport-button");
		playButton.get_style_context().add_class("transport-button");
		playButton.get_style_context().add_class("play");
		nextButton.get_style_context().add_class("transport-button");
		// Keep the toolbar from stretching them: square size => perfect circle
		foreach (var item in new ToolButton[] { previousButton, playButton, nextButton }) {
			var button = item.get_child ();
			int size = (item == playButton) ? 56 : 42;
			button.set_size_request (size, size);
			button.valign = button.halign = Align.CENTER;
			button.margin_top = 12; // room for the traffic lights above
		}
		searchField.get_style_context().add_class("search-bar");
		statusBar.get_style_context().add_class("app-statusbar");

		/* Top toolbar events */
		previousButton.clicked.connect(previousClicked);
		playButton.clicked.connect(playClicked);
		nextButton.clicked.connect(nextClicked);
		viewSelector.mode_changed.connect(view_selection_changed);
		showSongInfo.toggled.connect(showSongInfoToggled);
		searchField.changed.connect(search_field_changed);
		
		// Sidetoolbar events
		sideTreeAdd.clicked.connect(sideTreeAddClicked);
		sideTreeRemove.clicked.connect(sideTreeRemoveClicked);
		sideTreeOptions.clicked.connect(sideTreeOptionsClicked);
		
		show_all();
		lcd_logo.visible = !top_display.visible;
		infoBar.hide();
		update_sensitivities();
		hide_video_mode();
	}
	
	Widget create_traffic_lights() {
		var box = new Box(Orientation.HORIZONTAL, 8);
		box.halign = Align.START;
		box.valign = Align.START;
		box.margin_start = 8;
		box.margin_top = 6;
		string[] names = { "close", "minimize", "maximize" };
		string[] tips = { _("Close"), _("Minimize"), _("Maximize (Alt: mini player)") };
		for (int i = 0; i < 3; i++) {
			var button = new Button();
			button.get_style_context().add_class("traffic-light");
			button.get_style_context().add_class(names[i]);
			button.tooltip_text = tips[i];
			button.can_focus = false;
			button.valign = Align.CENTER;
			box.pack_start(button, false, false, 0);
			int which = i;
			button.clicked.connect(() => {
				if (which == 0) close();
				else if (which == 1) iconify();
				else if (mini || (get_current_event_state_mods() & Gdk.ModifierType.MOD1_MASK) != 0) toggle_mini(); // Alt+green, as in old players
				else if (window_maximized) unmaximize();
				else maximize();
			});
		}
		return box;
	}
	
	static Gdk.ModifierType get_current_event_state_mods() {
		Gdk.ModifierType state;
		Gtk.get_current_event_state(out state);
		return state;
	}
	
	/** Shrinks the window to its toolbar, and back to the saved size */
	public void toggle_mini() {
		mini = !mini;
		verticalBox.visible = viewSelectorBin.visible = searchFieldBin.visible = !mini;
		height_request = mini ? -1 : 440;
		if (mini) {
			if (window_maximized)
				unmaximize();
			resize(1, 1); // the toolbar's natural size
		} else {
			resize(last_width, last_height);
		}
	}
	
	public void setup_playback() {
		sideTree.reset_view();
		
		Idle.add( () => {
			var view = get_current_view();
			if(App.playback.media_active) {
				view.set_as_current_list(null);
			}
			
			return false;
		});
	}
	
	public void focused_widget_changed(Widget? w) {
		if (w != null && w != this.searchField) {
			focusAfterSearch = w;
			debug("Registered new widget to focus after search: %s", focusAfterSearch.name);
		}
	}
	
	// TODO: Make this properly recursive
	public void add_view (View view) {
		debug("Adding view %s\n", view.get_view_name());
		
		sideTree.add_view(view);
		
		// Add the main view
		mainViews.append_page(view);
		
		if(view.get_object() != null) {
			object_to_view.set(view.get_object(), view);
		}
		
		// Also add its sub views to the page. Side tree will handle adding 
		// all the side items
		if(view.get_sub_views() != null) {
			foreach(View sub_view in view.get_sub_views()) {
				mainViews.append_page(sub_view);
				
				if(view.get_object() != null) {
					object_to_view.set(view.get_object(), view);
				}
			}
		}
	}
	
	// TODO: Make this properly recursive
	public void remove_view(View view) {
		debug("Removing view %s\n", view.get_view_name());
		
		// Remove it from mainViews. Be careful here - if -1 is passed
		// to Notebook.remove_page, it will remove the last page which
		// would be bad.
		int page_to_remove = mainViews.page_num(view);
		if(page_to_remove != -1) {
			mainViews.remove_page(mainViews.page_num(view));
		}
		
		if(view.get_object() != null) {
			object_to_view.unset(view.get_object());
		}
		
		// Also remove its sub views. Side tree will handle removing 
		// all the side items
		if(view.get_sub_views() != null) {
			foreach(View sub_view in view.get_sub_views()) {
				mainViews.remove_page(mainViews.page_num(sub_view));
				
				if(sub_view.get_object() != null) {
					object_to_view.unset(sub_view.get_object());
				}
			}
		}
		
		sideTree.remove_view(view);
	}

	/**
	 * Sets the given view as the active item
	 */
	public void set_active_view (View view) {
		int view_index = mainViews.page_num (view);
		
		if (view_index < 0) {
			critical ("Cannot set " + view.get_view_name() + " as the active view");
			return;
		}
		
		// We need to set this view as the current page before even attempting to call
		// the set_as_current_view() method.
		view.show_all();
		mainViews.set_current_page (view_index);
		view.set_as_current_view();
		sideTree.select_view(view);
		
		// If in now_playing view, they probably don't want to be anymore
		showSongInfo.active = false;
		update_sensitivities();
		
		view_changed(view);
	}
	
	public View? get_view_from_object(GLib.Object object) {
		return object_to_view.get(object);
	}

	/**
	 * Builds and sets up the default BeatBox views. That includes main sidebar elements
	 * and categories, which at the same time wrap treeviews, icon views, welcome screens, etc.
	 */
	private void build_main_views () {
		debug ("Building main views ...");
		
		// Add Music Library View
		add_view (new MusicSourceView());

		// Add Podcast Library View
		add_view (new PodcastSourceView());
		
		// Add Internet Radio View
		add_view (new StationSourceView());

		// Add Similar playlist. FIXME: This is part of LastFM and shouldn't belong to the core in the future
		add_view (new SimilarSourceView());

		// Add Queue view
		add_view (new QueueSourceView());

		// Add History view
		add_view (new HistorySourceView());
		
		// Show something...
		sideTree.reset_view();

		debug ("Done with main views.");
	}
	
	private async void load_playlists_async () {
        Idle.add_full (Priority.DEFAULT_IDLE, load_playlists_async.callback);
        yield;

        debug ("Loading playlists");
        
        // load playlists.
        foreach (BasePlaylist p in App.playlists.playlists()) {
            playlist_added(p);
        }
		
        update_sensitivities ();

        debug ("Finished loading playlists");
    }
	
	public void set_statusbar_info(TreeViewSetup.Hint media_type, uint medias, uint64 size, uint seconds) {
		statusBar.set_info(media_type, medias, size, seconds);
	}
	
	public void add_statusbar_widget(Widget w, bool left_side) {
		statusBar.insert_widget(w, left_side);
	}
	
	/**
	 * This is handled more carefully inside each SourceView object.
	 */
	public void update_sensitivities() {
		if(!initializationFinished)
			return;
		
		bool haveMedias = App.library.media_count() > 0;
		bool doingOps = App.operations.doing_ops;
		bool mediaActive = App.playback.media_active;
		bool showingMediaList = (get_current_view() is SourceView);
		bool songsInList = showingMediaList ? (get_current_view() as SourceView).have_media : false;

		top_display.set_visible(mediaActive || doingOps);
		
		previousButton.set_sensitive(mediaActive || songsInList);
		playButton.set_sensitive(mediaActive || songsInList);
		nextButton.set_sensitive(mediaActive || songsInList);
		
		viewSelector.set_sensitive(get_current_view().supports_view_selector());
		searchField.set_sensitive(get_current_view().supports_search());

		sideTree.setVisibility(sideTree.playlists_iter, haveMedias);
		
		// Update if now_playing is showing or not
		if(!now_playing.has_content_to_show())
			showSongInfo.active = false;
		
		showSongInfo.set_sensitive(now_playing.has_content_to_show());
		showSongInfoToggled();
	}
	
	public void show_notification(string title, string sub_title, Gdk.Pixbuf? pixbuf) {
		try {
			if (Notify.is_initted ()) {
				notification.set_timeout(1);
				
				notification.update(title, sub_title, "beatbox");
				
				if(pixbuf != null)
					notification.set_image_from_pixbuf(pixbuf);
				else
					notification.set_image_from_pixbuf(App.icons.BEATBOX.render (Gtk.IconSize.DIALOG));
				
				notification.show();
				notification.set_timeout (Notify.EXPIRES_DEFAULT);
			}
		}
		catch(GLib.Error err) {
			warning("Could not show notification: %s\n", err.message);
		}
	}
	
	bool keyPressed(Gdk.EventKey event) {
		// These modifiers are taken into account when a key-pressed event is evaluated...
		int valid_mod_keys = Gdk.ModifierType.SHIFT_MASK 			// SHIFT_L and SHIFT_R
								| Gdk.ModifierType.CONTROL_MASK 	// CTR_L and CTRL_R
								| Gdk.ModifierType.MOD1_MASK		// ALT_L
								| Gdk.ModifierType.SUPER_MASK		// WIN or CMD
								| Gdk.ModifierType.META_MASK;		//ALT_GR or ALT_R
		int event_state = event.state & valid_mod_keys;
		
		if (event_state != 0) {
			if((event_state & Gdk.ModifierType.CONTROL_MASK) == event_state && event.keyval == Gdk.Key.q) {
				destroy();
			}
			else if((event_state & Gdk.ModifierType.CONTROL_MASK) == event_state && event.keyval == Gdk.Key.i) {
				showSongInfo.active = !showSongInfo.active;
			}
			else if((event_state & Gdk.ModifierType.CONTROL_MASK) == event_state && event.keyval == Gdk.Key.m) {
				toggle_mini();
			}
			else if((event_state & Gdk.ModifierType.CONTROL_MASK) == event_state && event.keyval == Gdk.Key.f) {
				if (searchField.sensitive && !searchField.has_focus) {
					searchField.grab_focus();
				}
			}
		}
		else if(Regex.match_simple("[a-zA-Z0-9]", event.str) && searchField.sensitive && !searchField.has_focus) {
			if(!(get_focus() is Gtk.Entry)) {
				searchField.grab_focus();
			}
		}
		else if(event.str == " " && App.playback.media_active && !searchField.has_focus) {
			playClicked ();
			return true;
		}
		else if(event.keyval == Gdk.Key.Escape && searchField.has_focus) {
			if (focusAfterSearch != null) {
				focusAfterSearch.grab_focus();
			}
		}

		return false;
	}

	void media_played(Media m, Media? old) {
		update_sensitivities();
		
		showSongInfo.set_image(App.icons.INFO.render_image (IconSize.MENU, viewSelector.get_style_context()));
	}
	
	void playback_changed() {
		if(!App.playback.media_active || (App.library.media_count() > 0 && !App.playback.playing)) {
			playButton.icon_name = "media-playback-start-symbolic";
		}
		else {
			playButton.icon_name = "media-playback-pause-symbolic";
		}
		
		update_sensitivities();
	}
	
	void playback_stopped(Media? was_playing) {
		playButton.icon_name = "media-playback-start-symbolic";
		
		update_sensitivities();
	}

	void previousClicked () {
		App.playback.request_previous();
	}
	
	void start_playback_requested() {
		View view = get_current_view ();
			
		if(view.can_set_as_current_list()) {
			view.play_first_media();
		}
	}
	
	void playClicked () {
		if(App.playback.playing) {
			App.playback.pause();
		}
		else {
			App.playback.play();
		}
	}

	void nextClicked() {
		App.playback.request_next();
	}
	
	// If user searches, hide the now playing view
	void search_field_changed() {
		showSongInfo.active = false;
	}
	
	void view_selection_changed() {
		get_current_view().view_selection_changed(viewSelector.selected);
		
		App.settings.saved_state.view_mode = viewSelector.selected;
		
		showSongInfo.active = false;
		update_sensitivities();
	}
	
	public void set_current_view_selection(int selected) {
		viewSelector.selected = selected;
	}
	
	public int get_current_view_selection() {
		return viewSelector.selected;
	}
	
	void medias_imported(Library library, FilesOperation.ImportType import_type, Collection<Media> new_medias, Collection<string> not_imported) {
		if(not_imported.size > 0) {
			NotImportedDialog nim = new NotImportedDialog(not_imported, library.folder.get_path());
			nim.show();
		}

		update_sensitivities();
		
		show_notification(_("Import Complete"), _("BeatBox has imported your %s library.").printf(library.name.down()), App.icons.BEATBOX.render (Gtk.IconSize.DIALOG));
	}

	void medias_removed(Collection<Media> removed) {
		update_sensitivities();
	}
	
	void device_added(Device d) {
		if(d.getContentType() == "cdrom") {
			add_view(new DeviceSourceView(d.get_medias(), new TreeViewSetup(MusicColumn.ARTIST, SortType.ASCENDING, TreeViewSetup.Hint.CDROM), d));
		}
		else {
			add_view(new DeviceView(d));
		}
	}
	
	void device_removed(Device d) {
		View device_view = object_to_view.get(d);
		
		if(device_view != null) {
			remove_view(device_view);
		}
		else {
			warning("Unknown device removed. Cannot remove it from sidebar");
		}
	}
	
	void playlist_added(BasePlaylist p) {
		if(p is StaticPlaylist) {
			add_view(new PlaylistSourceView((StaticPlaylist)p));
		}
		else if(p is SmartPlaylist) {
			add_view(new SmartPlaylistSourceView((SmartPlaylist)p));
		}
		else {
			error("Unknown playlist type added");
		}
	}
	
	// Definitely not the best way to do it, but for now if a playlist
	// is updated, remove it and then re-add it. This will sort it by
	// name like it should be
	void playlist_changed(BasePlaylist p) {
		View p_view = object_to_view.get(p);
		
		if(p_view != null) {
			// TODO: Fixme: By removing and the nadding, we either need to fully
			// destroy the last object or figure out a way to remove the tvc from old view
			// and add to new
			sideTree.update_view_position(p_view);
			set_active_view(object_to_view.get(p));
		}
		else {
			warning("Could not find view for playlist. Will not be in order");
		}
	}
	
	void playlist_removed(BasePlaylist p) {
		View p_view = object_to_view.get(p);
		
		if(p_view != null) {
			remove_view(p_view);
		}
		else {
			warning("Could not remove playlist view. Associated view not found in map.");
		}
	}
	
	// useful for determining popup locations
	public int get_sidebar_width() {
		return sourcesToMedias.position;
	}
	
	public void confirm_set_library_folder(Library lib, File folder) {
		if(App.operations.doing_ops)
			return;

		if(lib.media_count() > 0 || App.playlists.playlist_count() > 0) {
			var smfc = new SetLibraryFolderConfirmation(lib, folder);
			smfc.finished.connect( (cont) => {
				if(cont) {
					lib.set_local_folder(folder);
				}
			});
		}
		else {
			lib.set_local_folder(folder);
		}
	}

	public void media_not_found(Media m) {
		m.unique_status_image = App.icons.PROCESS_ERROR.render(Gtk.IconSize.MENU, ((SourceView)sideTree.getWidget(sideTree.library_music_iter)).list_view.get_style_context());
		file_not_found_pileup.add(m);
		infoBarLabel.set_markup(_("%s media files could not be found.").printf("<b>" + file_not_found_pileup.size.to_string() + "</b>"));
		infoBar.show_all();
	}
	
	public void media_found(Media m) {
		m.unique_status_image = null;
		file_not_found_pileup.remove(m);
		infoBarLabel.set_markup(_("%s media files could not be found.").printf("<b>" + file_not_found_pileup.size.to_string() + "</b>"));
		infoBar.set_visible(file_not_found_pileup.size > 0);
	}

	public View get_current_view () {
		return (View)mainViews.get_nth_page (mainViews.get_current_page());
	}

	void dragReceived(Gdk.DragContext context, int x, int y, Gtk.SelectionData data, uint info, uint timestamp) {
		if(dragging_from_music)
			return;

		var files_dragged = new LinkedList<File>();
		foreach (string uri in data.get_uris ()) {
			files_dragged.add(File.new_for_uri(uri));
		}
		
		warning("TODO: Fixme. How to know?");
		App.library.song_library.add_files(files_dragged, false);
	}

	public void doAlert(string title, string message) {
		var dialog = new MessageDialog(this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK,
				"%s", title);

		dialog.title = "BeatBox";
		dialog.secondary_text = message;
		dialog.secondary_use_markup = true;

		dialog.run();
		dialog.destroy();
	}
	
	void info_bar_response(int response_id) {
		if(response_id == Gtk.ResponseType.YES) {
			FileNotFoundDialog fnfd = new FileNotFoundDialog(file_not_found_pileup);
			fnfd.present();
			
			file_not_found_pileup = new LinkedList<Media>();
		}
		
		infoBar.hide();
	}
	
	void showSongInfoToggled() {
		if(showSongInfo.active)
			all_views.set_current_page(all_views.page_num(now_playing));
		else
			all_views.set_current_page(all_views.page_num(mainViews));
	}
	
	void video_enabled() {
		showSongInfo.set_image(App.icons.VIEW_VIDEO.render_image (IconSize.MENU, viewSelector.get_style_context()));
		showSongInfo.active = true;
	}
	
	public void show_video_mode() {
		//now_playing.show_video_mode();
		//warning("Fixme: show video");
		showSongInfo.set_image(App.icons.VIEW_VIDEO.render_image (IconSize.MENU, viewSelector.get_style_context()));
	}
	
	public void hide_video_mode() {
		//now_playing.hide_video_mode();
		//warning("FIXME: hide video");
		showSongInfo.set_image(App.icons.INFO.render_image (IconSize.MENU, viewSelector.get_style_context()));
	}
	
	bool window_state_changed(Gdk.EventWindowState event) {
		if((event.changed_mask & (Gdk.WindowState.MAXIMIZED | Gdk.WindowState.FULLSCREEN)) == 0)
			return false;
		
		window_maximized = ((event.new_window_state & (Gdk.WindowState.MAXIMIZED | Gdk.WindowState.FULLSCREEN)) != 0);
			
		return false;
	}
	
	void sideTreeAddClicked() {
		sideTreeAddMenu.show_all();
		sideTreeAddMenu.popup_at_pointer(null);
	}
	
	void sideTreeRemoveClicked() {
		//sideTree.playlistMenuRemoveClicked();
		warning("FIXME");
	}
	
	void sideTreeOptionsClicked() {
		sideTreeMenu.show_all();
		sideTreeMenu.popup_at_pointer(null);
	}
	
	public void set_search_string(string search) {
		searchField.set_text(search);
	}
	
	void operation_started() {
		update_sensitivities();
	}
	
	void operation_finished() {
		update_sensitivities();
	}
	
	bool on_delete() {
		bool hide_on_close = false;
		if (App.playback.playing) {
			this.hide();
			hide_on_close = true;
		}
		return hide_on_close;
	}

	int last_width;
	int last_height;
	
	void on_quit() {
		// Stop listening to window state changes
		this.window_state_event.disconnect(window_state_changed);
		App.settings.main.last_media_position = (int)((double)App.playback.get_position()/1000000000);
		if(App.playback.media_active) {
			App.playback.current_media.resume_pos = (int)((double)App.playback.get_position()/1000000000);
			App.library.update_media(App.playback.current_media, false, false, false);
		}
		
		App.playback.pause();

		// Terminate Libnotify
		Notify.uninit ();
		
		// Save UI Information
		if (window_maximized == true)
		    App.settings.saved_state.window_state = Settings.WindowState.MAXIMIZED;
		if(!(window_maximized || window_fullscreen)) {
			// The allocation is already gone during destroy: use the last known size
			App.settings.saved_state.window_width = last_width;
			App.settings.saved_state.window_height = last_height;
		}
		
		App.settings.main.search_string = searchField.get_text();
		App.settings.saved_state.sidebar_width = sourcesToMedias.position;
		App.settings.saved_state.view_mode = viewSelector.selected;
		
		// Periodic data is otherwise only written every 15 seconds, and
		// Both are otherwise written a little later: flush them before exiting.
		App.database.flush();
		ConfigSection.flush();
	}
}

