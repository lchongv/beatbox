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
	public static Gtk.Application app { get; private set; }
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
	
	public bool dragging_from_music { get; set; }
	public bool initializationFinished { get; private set; }
	
	 /* Window state properties */
    private bool window_maximized = false;
    private bool window_fullscreen = false;
	
	// Main containers
	Box verticalBox;
	Widget viewSelectorBin;
	Widget searchFieldBin;
	int appmenu_size = 0; // the round menu button's size (see resize_appmenu)
	bool mini = false; // mini player: only the toolbar (controls and LCD) is left
	bool maximized_before_mini = false;
	Notebook all_views { get; private set; } // mainViews, songInfo, possibly video later on
	public Notebook mainViews { get; private set; }
	public Gtk.Paned sourcesToMedias { get; private set; } //allows for draggable
	Box contentBox;
	Gtk.Paned contentToReport; // the lists, and the report on the song playing at their right
	bool placing_report = false; // our own moves of that divider are not the user's
	int report_split_width = 0; // the window width the divider was last placed for
	TrackReport report;
	ToggleButton reportButton;
	Box sideBox;
	
	// Side box
	ScrolledWindow sideTreeScroll;
	public SideTreeView sideTree { get; private set; }
	
	// File not found stuff
	InfoBar infoBar;
	Label infoBarLabel;
	LinkedList<Media> file_not_found_pileup;
	
	// The top bar
	Box topControls;
	EventControllerKey key_bubble;
	Button previousButton;
	Button playButton;
	Image playIcon;
	Button nextButton;
	ModeButton viewSelector;
	Scale volumeScale;
	bool songInfoShown; // the now playing view in place of the lists (Ctrl+I)
	AdvancedSearchBox searchField;
	
	// GTK3 controllers need a reference
	EventControllerKey key_controller;
	GestureClick lcd_cover_gesture;
	bool cover_dragged = false; // the cover was dragged out since the press: the release does not enlarge it
	
	public StatusBar statusBar { get; private set; }
	
	// basic file stuff
	private GLib.Menu settingsMenu;
	
	// state stuff
	private Gtk.Widget focusAfterSearch;
	private HashMap<Object, View> object_to_view;
	
	public Notify.Notification notification { get; private set; }

	public LibraryWindow(Gtk.Application bb_app) {
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
		this.close_request.connect(on_delete);

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

		// GTK4: the window is not destroyed on quit by signal; the application's shutdown does it
		bb_app.shutdown.connect (on_quit);
		this.notify["default-width"].connect (track_size);
		this.notify["default-height"].connect (track_size);

		object_to_view = new HashMap<Object, View>();
	}

	/* The round menu button: 80 % of the LCD's height */
	void resize_appmenu (Gtk.Widget lcd, Gtk.Image icon, Gtk.MenuButton button) {
		int size = (int)(lcd.get_height() * 0.8);
		if (size == appmenu_size || size < 16)
			return;
		appmenu_size = size;
		Idle.add (() => {
			UI.show_pixbuf (icon, app_menu_icon (size - 2)); // minus the 1px border
			button.set_size_request (size, size);
			return false;
		});
	}

	/* The size to save and restore: the window's default size, kept up to date by the window itself.
	 * It counts the title bar, as set_default_size does (GTK3's get_size left it out, hence the old
	 * correction for a title bar that changed height) */
	void track_size (GLib.ParamSpec pspec) {
		if (!(window_maximized || window_fullscreen || mini)) {
			last_width = default_width;
			last_height = default_height;
		}
	}

	/* The app icon on the menu button: the round version (beatbox-round.svg), drawn to
	 * fill the round button exactly, or the square one in skins with MenuIcon=square */
	static Gdk.Pixbuf? app_menu_icon (int size) {
		var file = Skins.square_menu_icon ? "beatbox.svg" : "beatbox-round.svg";
		try {
			return new Gdk.Pixbuf.from_resource_at_scale ("/net/launchpad/beatbox/icons/128x128/apps/" + file, size, size, true);
		} catch (Error err) {
			warning ("Could not load the app icon %s: %s", file, err.message);
			return null;
		}
	}

	public void build_ui() {
		message ("Building user interface\n");
		
		// Start by initializing the window and widgets to create the UI
		insert_action_group ("bb", App.actions.group); // what GLib.Menu menus ("bb.<name>") call
		setup_window ();
        setup_widgets ();
        register_shortcuts ();
        
        // We have all the widgets, so show to user even though most views aren't built yet
        this.show();
        
        // Load up the different views. Some loads are asynchronous.
		build_main_views ();
		load_playlists_async.begin ();
		
		App.devices.load_pre_existing_devices();
		
		App.settings.main.notify["mini-keep-above"].connect(apply_keep_above);
		if (App.settings.saved_state.mini_player) {
			toggle_mini();
			maximized_before_mini = App.settings.saved_state.window_state == Settings.WindowState.MAXIMIZED;
		}
		
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

        // set the size based on saved settings
        this.set_default_size (App.settings.saved_state.window_width, App.settings.saved_state.window_height);
		// (starting as mini player: maximized again only when it is left)
		if(App.settings.saved_state.window_state == Settings.WindowState.MAXIMIZED && !App.settings.saved_state.mini_player) {
			window_maximized = true;
			this.maximize();
		}

        this.set_title ("BeatBox");
        // the app icon: a name in the icon theme (BeatBox.vala adds the resources to it)
        Gtk.Window.set_default_icon_name ("beatbox");

        // files dropped on the window are added to the library
        var dest = new Gtk.DropTarget (GLib.Type.INVALID, Gdk.DragAction.COPY);
        dest.set_gtypes ({ typeof (string), typeof (Gdk.FileList) });
        dest.drop.connect ((value, x, y) => {
            string[] uris = {};
            if (value.holds (typeof (Gdk.FileList))) {
                foreach (File f in ((Gdk.FileList) value.get_object ()).get_files ())
                    uris += f.get_uri ();
            }
            else
                uris = value.get_string ().split ("\n");
            dragReceived (uris);
            return true;
        });
        dest.motion.connect ((x, y) => Gdk.DragAction.COPY);
        ((Gtk.Widget) this).add_controller (dest);

        debug ("done with main window");

        // keys reach keyPressed before the focused widget, as with the window's own key handler
        key_controller = new EventControllerKey ();
        key_controller.propagation_phase = PropagationPhase.CAPTURE;
        key_controller.key_pressed.connect (keyPressed);
        ((Gtk.Widget) this).add_controller (key_controller);
        // the keys a focused text field left alone come here (bubble phase): see keyBubbled
        key_bubble = new EventControllerKey ();
        key_bubble.key_pressed.connect (keyBubbled);
        ((Gtk.Widget) this).add_controller (key_bubble);
        this.notify["focus-widget"].connect ((pspec) => focused_widget_changed (get_focus ()));
        this.notify["maximized"].connect (window_state_changed);
        this.notify["fullscreened"].connect (window_state_changed);
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
		sideTreeScroll = new ScrolledWindow();
		settingsMenu = new GLib.Menu();
		topControls = new Box(Orientation.HORIZONTAL, 0);
		topControls.add_css_class("toolbar");
		// own images: an icon_name would get the toolbar's icon size, too small for these buttons
		previousButton = new Button();
		previousButton.child = new Image.from_icon_name("media-skip-backward-symbolic");
		playIcon = new Image.from_icon_name("media-playback-start-symbolic");
		playButton = new Button();
		playButton.child = playIcon;
		nextButton = new Button();
		nextButton.child = new Image.from_icon_name("media-skip-forward-symbolic");
		top_display = new TopDisplay();
		viewSelector = new ModeButton();
		searchField = new AdvancedSearchBox();
		searchField.width_request = 250; // 1.5 × its natural width
		infoBarLabel = new Label("");
		infoBar = new InfoBar();
		file_not_found_pileup = new LinkedList<Media>();
		statusBar = new StatusBar();

		notification = new Notify.Notification ("", null, null);

		/* Toolbar with media controls, search, app menu, etc. */
		// The LCD is always visible; the app name fills it when idle
		var lcd = new Box(Orientation.HORIZONTAL, 0);
		lcd.add_css_class("lcd");
		var lcdCover = new LcdCover();
		lcdCover.tooltip_text = _("Click to enlarge; drag to copy it into another application or folder");
		// dragging the cover gives its file to other applications (as text/uri-list)
		var cover_drag = new Gtk.DragSource();
		cover_drag.actions = Gdk.DragAction.COPY;
		cover_drag.prepare.connect((x, y) => {
			var path = lcdCover.file_for_drag();
			if (path == null)
				return null;
			var uri = File.new_for_path(path).get_uri() + "\r\n";
			return new Gdk.ContentProvider.for_bytes("text/uri-list", new Bytes(uri.data));
		});
		cover_drag.drag_begin.connect((drag) => {
			cover_dragged = true;
			var icon = lcdCover.drag_icon();
			if (icon != null)
				cover_drag.set_icon(Gdk.Texture.for_pixbuf(icon), icon.width / 2, icon.height / 2);
		});
		lcdCover.add_controller(cover_drag);
		// a click (released without dragging) enlarges it. The press is claimed, as in GTK3, so the
		// title bar does not move the window (GTK 4 lets a drag start only after 100 ms held, the title
		// bar at once); grouped with the drag source, which the claim would otherwise cancel
		lcd_cover_gesture = new GestureClick();
		lcd_cover_gesture.button = 0;
		lcd_cover_gesture.group(cover_drag);
		lcd_cover_gesture.pressed.connect(() => {
			cover_dragged = false;
			lcd_cover_gesture.set_state(EventSequenceState.CLAIMED);
		});
		lcd_cover_gesture.released.connect(() => {
			if (lcd_cover_gesture.get_current_button() == 1 && !cover_dragged)
				lcdCover.show_full_size(this);
		});
		lcdCover.add_controller(lcd_cover_gesture);
		lcd.append(lcdCover); // thumbnail at the left edge (optional)
		var lcd_logo = new Label("BeatBox");
		lcd_logo.add_css_class("lcd-logo");
		lcd_logo.hexpand = true;
		lcd.append(lcd_logo);
		top_display.hexpand = true;
		lcd.append(top_display);
		top_display.notify["visible"].connect(() => { lcd_logo.visible = !top_display.visible; });
		// (the LCD used to be a ToolItem with this margin: it now sits in the toolbar itself)
		lcd.hexpand = true;
		lcd.margin_start = 12;

		viewSelector.append(App.icons.VIEW_DETAILS.render_image (Gtk.IconSize.NORMAL));
		viewSelector.append(App.icons.VIEW_ICONS.render_image (Gtk.IconSize.NORMAL));
		viewSelector.append(new Image.from_resource ("/net/launchpad/beatbox/icons/16x16/actions/view-coverflow-symbolic.svg"));
		viewSelector.valign = Gtk.Align.CENTER;
		viewSelector.selected = App.settings.saved_state.view_mode;

		// the volume slider sits under the view switcher
		volumeScale = new Scale.with_range(Orientation.HORIZONTAL, 0, 1, 0.05);
		volumeScale.draw_value = false;
		volumeScale.width_request = 90;
		volumeScale.set_value(App.playback.get_volume());
		volumeScale.value_changed.connect(() => {
			App.playback.set_volume(volumeScale.get_value());
			App.settings.equalizer.volume = (int)Math.round(volumeScale.get_value() * 100);
		});
		var viewBox = new Box(Orientation.VERTICAL, 0);
		viewBox.valign = Gtk.Align.CENTER;
		viewBox.append(viewSelector);
		viewBox.append(volumeScale);

		viewSelectorBin = viewBox;
		viewSelectorBin.margin_start = 12;

		searchFieldBin = searchField;
		searchField.valign = Gtk.Align.CENTER; // half the height of the LCD, not the whole toolbar
		searchField.margin_start = 12;
		searchField.margin_end = 6;

		var mini_player = new SimpleAction("mini_player", null);
		mini_player.activate.connect(toggle_mini);
		App.actions.group.add_action(mini_player);
		settingsMenu.append_submenu(_("_Library"), App.libraries.menu);
		settingsMenu.append(_("_Mini Player"), "bb.mini_player");
		settingsMenu.append_item(App.actions.model_item(App.actions.show_equalizer));
		settingsMenu.append_item(App.actions.model_item(App.actions.show_preferences));
		settingsMenu.append_item(App.actions.model_item(App.actions.exit));

		topControls.set_vexpand (false);
		topControls.set_hexpand (true);

		topControls.append(previousButton);
		topControls.append(playButton);
		topControls.append(nextButton);
		topControls.append(viewSelectorBin);
		// the visualizer's button, bottom left with the shuffle and repeat; the visualizer takes the lists' place while it is on
		var visualizer = new Visualizer();
		visualizer.visible = false; // hidden until its button turns it on
		var visualizerButton = new ToggleButton();
		var visualizerIcon = App.icons.VISUALIZER.render_image(Gtk.IconSize.NORMAL);
		StatusBar.follow_text_color(visualizerIcon); // dark on the bar, like the other icons there
		visualizerButton.child = visualizerIcon;
		visualizerButton.has_frame = false;
		visualizerButton.focus_on_click = false;
		visualizerButton.tooltip_text = _("Visualizer");
		visualizerButton.toggled.connect(() => {
			visualizer.visible = visualizerButton.active;
			all_views.visible = !visualizerButton.active;
		});
		statusBar.insert_widget(visualizerButton, true);
		// the "i" (now playing) toggle is gone: redundant; Ctrl+I still opens that view
		topControls.append(lcd);
		topControls.append(searchFieldBin);
		var appmenu_button = new Gtk.MenuButton ();
		var appmenu_icon = new Gtk.Image ();
		UI.show_pixbuf (appmenu_icon, app_menu_icon (38));
		appmenu_button.child = appmenu_icon;
		appmenu_button.add_css_class ("round-menu");
		appmenu_button.set_size_request (40, 40);
		// the round button is 80 % of the LCD's height. GTK4-PENDIENTE: a Box has no size-allocate signal, so this
		// is worked out when the LCD maps and when the top display shows or hides, not on every resize
		lcd.map.connect (() => { Idle.add (() => { resize_appmenu (lcd, appmenu_icon, appmenu_button); return false; }); });
		top_display.notify["visible"].connect (() => resize_appmenu (lcd, appmenu_icon, appmenu_button));
		// a skin picked in Preferences may want the other shape (after Skins.apply has run)
		App.settings.main.notify["skin"].connect (() => Idle.add (() => {
			UI.show_pixbuf (appmenu_icon, app_menu_icon ((appmenu_size > 0 ? appmenu_size : 40) - 2));
			return false;
		}));
		appmenu_button.valign = appmenu_button.halign = Gtk.Align.CENTER;
		appmenu_button.menu_model = settingsMenu;
		topControls.append(appmenu_button);

		// Info bar to give notices about file not found errors
		infoBar.set_message_type(Gtk.MessageType.ERROR);
		infoBar.add_button(_("Resolve"), Gtk.ResponseType.YES);
		infoBar.response.connect(info_bar_response);

		infoBarLabel.set_justify(Justification.LEFT);
		infoBarLabel.set_single_line_mode(true);
		infoBarLabel.ellipsize = Pango.EllipsizeMode.END;

		infoBar.add_child(infoBarLabel);

		// Side tree
		sideTreeScroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		sideTreeScroll.add_css_class("sidebar-scroll");
		sideTreeScroll.set_child(sideTree);
		sideTreeScroll.vexpand = true;
		sideBox.append(AquaScroll.wrap(sideTreeScroll));

		// Hide notebook tabs and border
		mainViews.show_tabs = false;
		mainViews.show_border = false;

		all_views.show_tabs = false;
		all_views.show_border = false;

		// Add the final boxes to the window
		all_views.append_page(mainViews);
		all_views.append_page(now_playing);

		contentBox.append(infoBar);
		all_views.vexpand = true;
		contentBox.append(all_views);
		visualizer.vexpand = true;
		contentBox.append(visualizer);

		sourcesToMedias.position = App.settings.saved_state.sidebar_width;
		sourcesToMedias.start_child = sideBox;
		sourcesToMedias.resize_start_child = false;
		sourcesToMedias.shrink_start_child = true;
		report = new TrackReport();
		report.visible = false;
		contentToReport = new Gtk.Paned(Orientation.HORIZONTAL);
		contentToReport.start_child = contentBox;
		contentToReport.resize_start_child = true;
		contentToReport.shrink_start_child = false;
		contentToReport.end_child = report;
		contentToReport.resize_end_child = false;
		contentToReport.shrink_end_child = false;
		sourcesToMedias.end_child = contentToReport;
		sourcesToMedias.resize_end_child = true;
		sourcesToMedias.shrink_end_child = true;
		// the report keeps the width it was left at: dragging the divider saves it, resizing the window does not change it
		contentToReport.notify["position"].connect(() => {
			if(report.visible && !placing_report && contentToReport.get_width() > 1)
				App.settings.saved_state.more_width = contentToReport.get_width() - contentToReport.position;
		});
		// Gtk.Paned has no size-allocate signal (GTK3 placed the divider on every allocation): it is
		// re-placed when the window width changes, once laid out (the report keeps its width maximized)
		this.notify["default-width"].connect(() => { Idle.add(() => { place_report_width(); return false; }); });

		reportButton = new ToggleButton();
		var info_image = App.icons.INFO.render_image(Gtk.IconSize.NORMAL);
		StatusBar.follow_text_color(info_image); // dark on the bar, like the other icons there
		reportButton.child = info_image;
		reportButton.has_frame = false;
		reportButton.focus_on_click = false;
		reportButton.tooltip_text = _("Information about the song playing (Ctrl+Shift+I)");
		reportButton.toggled.connect(() => show_report(reportButton.active));
		statusBar.insert_widget(reportButton, false);

		// The toolbar is the window's title bar: no separate system title bar,
		// traffic lights in the top-left corner, above the transport buttons
		var titlebar = new Overlay();
		titlebar.child = topControls;
		titlebar.add_overlay(create_traffic_lights());
		// the title bar is the zone that drags the window (its buttons keep their clicks)
		var titlebar_handle = new Gtk.WindowHandle();
		titlebar_handle.child = titlebar;
		set_titlebar(titlebar_handle);
		sourcesToMedias.vexpand = true;
		verticalBox.append(sourcesToMedias);
		verticalBox.append(statusBar);
		this.child = verticalBox;

		// Set theming
		topControls.add_css_class("primary-toolbar");
		topControls.add_css_class("app-header");
		add_css_class("beatbox");
		previousButton.add_css_class("transport-button");
		playButton.add_css_class("transport-button");
		playButton.add_css_class("play");
		nextButton.add_css_class("transport-button");
		// Keep the toolbar from stretching them: square size => perfect circle
		foreach (var button in new Button[] { previousButton, playButton, nextButton }) {
			int size = (button == playButton) ? 72 : 44;
			button.set_size_request (size, size);
			((Image)button.child).pixel_size = size * 2 / 5;
			button.valign = button.halign = Align.CENTER;
			button.margin_top = 12; // room for the traffic lights above
		}
		searchField.add_css_class("search-bar");
		statusBar.add_css_class("app-statusbar");

		/* Top toolbar events */
		previousButton.clicked.connect(previousClicked);
		playButton.clicked.connect(playClicked);
		nextButton.clicked.connect(nextClicked);
		viewSelector.mode_changed.connect(view_selection_changed);
		searchField.changed.connect(search_field_changed);

		reportButton.active = App.settings.saved_state.more_visible;
		lcd_logo.visible = !top_display.visible;
		infoBar.hide();
		update_sensitivities();
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
			button.add_css_class("traffic-light");
			button.add_css_class(names[i]);
			button.tooltip_text = tips[i];
			button.focusable = false;
			button.valign = Align.CENTER;
			box.append(button);
			// the Alt state is read at the press: the click itself comes at the release
			bool alt_pressed = false;
			var alt_state = new GestureClick();
			alt_state.pressed.connect((n, x, y) => {
				alt_pressed = (alt_state.get_current_event_state() & Gdk.ModifierType.ALT_MASK) != 0;
			});
			button.add_controller(alt_state);
			int which = i;
			button.clicked.connect(() => {
				if (which == 0) close();
				else if (which == 1) minimize();
				else if (mini || alt_pressed) toggle_mini(); // Alt+green, as in old players
				else if (window_maximized) unmaximize();
				else maximize();
			});
		}
		var name = new Label("BeatBox " + Build.VERSION); // the merged title bar has no title of its own
		name.add_css_class("app-name");
		name.margin_start = 4;
		box.append(name);
		return box;
	}

	/** Shrinks the window to its toolbar, and back to the saved size */
	public void toggle_mini() {
		mini = !mini;
		App.settings.saved_state.mini_player = mini;
		verticalBox.visible = viewSelectorBin.visible = searchFieldBin.visible = !mini;
		height_request = mini ? -1 : 440;
		if (mini) {
			maximized_before_mini = window_maximized;
			if (window_maximized)
				unmaximize();
			set_default_size (1, 1); // the toolbar's natural size
		} else {
			// last_width is only 0 when BeatBox started in mini mode
			set_default_size(last_width > 0 ? last_width : App.settings.saved_state.window_width,
			       last_height > 0 ? last_height : App.settings.saved_state.window_height);
			if (maximized_before_mini)
				maximize();
		}
		apply_keep_above();
	}

	/** GTK4 cannot keep a window above the others (Wayland never could): the window menu of the compositor offers "Always on Top" */
	public void apply_keep_above() {
	}

	public void setup_playback() {
		sideTree.reset_view();
		
		Idle.add( () => {
			var view = get_current_view();
			// a restored song gets the view as its list; songs opened at startup keep theirs
			var p = App.playback;
			if(p.media_active && p.media_from_playback_list_index(p.current_index) != p.current_media) {
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
		
		// Add the main view (before its side tree item: adding that one
		// may select it, and selecting it shows this page)
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
		
		sideTree.add_view(view);
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
				mainViews.set_current_page (view_index);
		view.set_as_current_view();
		sideTree.select_view(view);
		
		// If in now_playing view, they probably don't want to be anymore
		songInfoShown = false;
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
	
	/** The report panel at the right, as wide as it was left */
	void show_report(bool show) {
		App.settings.saved_state.more_visible = show;
		if(show) {
			report.set_size_request(200, -1);
			report.show();
			report_split_width = 0; // placed once laid out, from the saved width
			Idle.add(() => { place_report_width(); return false; });
		}
		else
			report.hide();
		if(reportButton.active != show)
			reportButton.active = show;
	}

	/** Moves the report's divider so the report keeps the width it was left at */
	void place_report_width() {
		int width = contentToReport.get_width();
		if(!report.visible || width <= 1 || width == report_split_width)
			return;
		report_split_width = width;
		placing_report = true;
		contentToReport.position = int.max(200, width - int.max(App.settings.saved_state.more_width, 200));
		placing_report = false;
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
		var source_view = get_current_view() as SourceView;
		bool songsInList = showingMediaList && source_view != null && source_view.have_media;

		top_display.set_visible(mediaActive || doingOps);
		
		previousButton.set_sensitive(mediaActive || songsInList);
		playButton.set_sensitive(mediaActive || songsInList);
		nextButton.set_sensitive(mediaActive || songsInList);
		
		viewSelector.set_sensitive(get_current_view().supports_view_selector());
		searchField.set_sensitive(get_current_view().supports_search());

		sideTree.setVisibility(sideTree.playlists_iter, haveMedias);
		
		// Update if now_playing is showing or not
		show_song_info(songInfoShown);
	}
	
	public void add_menu_action(string label, GLib.Action action) {
		App.actions.group.add_action(action);
		settingsMenu.insert(settingsMenu.get_n_items() - 2, label, "bb." + action.name); // above Preferences and Exit
	}
	
	public void remove_menu_action(GLib.Action action) {
		for(int i = 0; i < settingsMenu.get_n_items(); i++) {
			var target = settingsMenu.get_item_attribute_value(i, "action", VariantType.STRING);
			if(target != null && target.get_string() == "bb." + action.name) {
				settingsMenu.remove(i);
				break;
			}
		}
		App.actions.group.remove_action(action.name);
	}
	
	public void show_notification(string title, string sub_title, Gdk.Pixbuf? pixbuf) {
		try {
			if (Notify.is_initted ()) {
				notification.set_timeout(1);
				
				notification.update(title, sub_title, "beatbox");
				
				if(pixbuf != null)
					notification.set_image_from_pixbuf(pixbuf);
				else
					notification.set_image_from_pixbuf(App.icons.BEATBOX.render (null, null, 48));
				
				notification.show();
				notification.set_timeout (Notify.EXPIRES_DEFAULT);
			}
		}
		catch(GLib.Error err) {
			warning("Could not show notification: %s\n", err.message);
		}
	}
	
	/* The keyboard shortcuts (Preferences › Shortcuts), with their default keys */
	void register_shortcuts() {
		Shortcuts.init(App.settings.main.shortcuts, (list) => { App.settings.main.shortcuts = list; });
		Shortcuts.register("play-pause", _("Play / Pause"), "space", playClicked);
		Shortcuts.register("next", _("Next song"), "<Control>Right", nextClicked);
		Shortcuts.register("previous", _("Previous song"), "<Control>Left", previousClicked);
		Shortcuts.register("volume-up", _("Volume up"), "<Control>Up", () => { change_volume(0.1); });
		Shortcuts.register("volume-down", _("Volume down"), "<Control>Down", () => { change_volume(-0.1); });
		Shortcuts.register("mini-player", _("Mini player"), "<Control>m", toggle_mini);
		Shortcuts.register("search", _("Search"), "<Control>f", () => {
			if (searchField.sensitive)
				searchField.grab_focus();
		});
		Shortcuts.register("now-playing", _("Now playing"), "<Control>i", () => { show_song_info(!songInfoShown); });
		Shortcuts.register("song-report", _("Information panel"), "<Control><Shift>i", () => { show_report(!report.visible); });
		Shortcuts.register("equalizer", _("Equalizer"), "<Control>e", () => { App.actions.show_equalizer.activate(null); });
		Shortcuts.register("preferences", _("Preferences"), "<Control>comma", () => { App.actions.show_preferences.activate(null); });
		Shortcuts.register("quit", _("Quit"), "<Control>q", () => { destroy(); });
	}
	
	void change_volume(double delta) {
		// the slider's value_changed does the rest
		volumeScale.set_value((volumeScale.get_value() + delta).clamp(0.0, 1.0));
	}
	
	bool keyPressed(uint keyval, uint keycode, Gdk.ModifierType state) {
		var focus = get_focus();

		// Escape in the search box goes back to the list
		if(keyval == Gdk.Key.Escape && searchField.has_focus && focusAfterSearch != null) {
			focusAfterSearch.grab_focus();
			return true;
		}

		// a text field gets the key first: there Space types a space, Ctrl+Left moves by word...
		// (the keys it leaves go on to keyBubbled)
		if(focus is Gtk.Editable)
			return false;

		return handle_key(keyval, state, key_controller);
	}

	// the keys that a text field did not use: the window's shortcuts get them there
	bool keyBubbled(uint keyval, uint keycode, Gdk.ModifierType state) {
		return get_focus() is Gtk.Editable && handle_key(keyval, state, key_bubble);
	}

	bool handle_key(uint keyval, Gdk.ModifierType state, EventControllerKey controller) {
		var focus = get_focus();

		if(Shortcuts.activate(keyval, state))
			return true;

		// typing a letter or a digit anywhere starts a search
		var mods = state & Gtk.accelerator_get_default_mod_mask();
		var typed = ((unichar) Gdk.keyval_to_unicode(keyval)).to_string();
		if(mods == 0 && Regex.match_simple("^[a-zA-Z0-9]$", typed) && searchField.sensitive && !(focus is Gtk.Entry)) {
			searchField.grab_focus();
			// GTK 4 keeps sending the key to the old focus: hand it to the search box's text
			return controller.forward((Gtk.Widget) searchField.get_delegate());
		}

		return false;
	}

	void media_played(Media m, Media? old) {
		update_sensitivities();
	}
	
	void playback_changed() {
		if(!App.playback.media_active || (App.library.media_count() > 0 && !App.playback.playing)) {
			playIcon.icon_name = "media-playback-start-symbolic";
		}
		else {
			playIcon.icon_name = "media-playback-pause-symbolic";
		}
		
		update_sensitivities();
	}
	
	void playback_stopped(Media? was_playing) {
		playIcon.icon_name = "media-playback-start-symbolic";
		
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
		show_song_info(false);
	}
	
	void view_selection_changed() {
		get_current_view().view_selection_changed(viewSelector.selected);
		
		App.settings.saved_state.view_mode = viewSelector.selected;
		
		songInfoShown = false;
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
		
		show_notification(_("Import Complete"), _("BeatBox has imported your %s library.").printf(library.name.down()), App.icons.BEATBOX.render (null, null, 48));
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
		m.unique_status_image = App.icons.PROCESS_ERROR.render(Gtk.IconSize.NORMAL, ((SourceView)sideTree.getWidget(sideTree.library_music_iter)).list_view.get_style_context());
		file_not_found_pileup.add(m);
		infoBarLabel.set_markup(_("%s media files could not be found.").printf("<b>" + file_not_found_pileup.size.to_string() + "</b>"));
		infoBar.visible = true;
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

	void dragReceived(string[] uris) {
		if(dragging_from_music)
			return;

		var files_dragged = new LinkedList<File>();
		foreach (string uri in uris) {
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

		// GTK4 has no dialog.run (): the alert stays modal, and the callers do not wait for it anyway
		dialog.response.connect((id) => dialog.destroy());
		dialog.present();
	}

	void info_bar_response(int response_id) {
		if(response_id == Gtk.ResponseType.YES) {
			FileNotFoundDialog fnfd = new FileNotFoundDialog(file_not_found_pileup);
			fnfd.present();
			
			file_not_found_pileup = new LinkedList<Media>();
		}
		
		infoBar.hide();
	}
	
	// the now playing view, when there is something to show in it, or the lists
	void show_song_info(bool show) {
		songInfoShown = show && now_playing.has_content_to_show();
		if(songInfoShown)
			all_views.set_current_page(all_views.page_num(now_playing));
		else
			all_views.set_current_page(all_views.page_num(mainViews));
	}
	
	void video_enabled() {
		show_song_info(true);
	}
	
	void window_state_changed(GLib.ParamSpec pspec) {
		window_maximized = is_maximized() || fullscreened;
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
		this.notify["maximized"].disconnect(window_state_changed);
		this.notify["fullscreened"].disconnect(window_state_changed);
		if(App.playback.media_active) {
			App.settings.main.last_media_position = (int)((double)App.playback.get_position()/1000000000);
			App.playback.current_media.resume_pos = (int)((double)App.playback.get_position()/1000000000);
			App.library.update_media(App.playback.current_media, false, false, false);
		}
		
		App.playback.pause();
		StreamRecorder.get_default().stop_all(); // streamripper closes its files on its own after we are gone

		// Terminate Libnotify
		Notify.uninit ();
		
		// Save UI Information
		bool maximized = mini ? maximized_before_mini : window_maximized;
		App.settings.saved_state.window_state = maximized ? Settings.WindowState.MAXIMIZED : Settings.WindowState.NORMAL;
		if(!(window_maximized || window_fullscreen) && last_width > 0) {
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

