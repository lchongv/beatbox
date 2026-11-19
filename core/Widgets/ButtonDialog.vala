/*
 * Dialogs without Gtk.Dialog, Gtk.MessageDialog and Gtk.FileChooserDialog (all deprecated in
 * GTK 4.10): a window with a row of buttons for the dialogs that hold widgets of their own, and
 * UI.alert / confirm / choose_folder / open_file... over Gtk.AlertDialog and Gtk.FileDialog.
 */

/** A window with its content and a row of buttons at the bottom right; each button answers
 *  with its number, as a Gtk.Dialog did (the same values as Gtk.ResponseType) */
[GIR (visible = false)] // internal: plugins don't see it
public class BeatBox.ButtonDialog : Gtk.Window {
	public const int NONE = -1;
	public const int ACCEPT = -3;
	public const int DELETE_EVENT = -4;
	public const int OK = -5;
	public const int CANCEL = -6;
	public const int CLOSE = -7;
	public const int YES = -8;
	public const int NO = -9;
	public const int APPLY = -10;

	/** Answered: a button, or CANCEL / DELETE_EVENT for Escape and the window's close button */
	public signal void response (int answer);

	public Gtk.Box content_area { get; private set; }
	public Gtk.Box action_area { get; private set; }
	Gee.HashMap<int, Gtk.Widget> buttons = new Gee.HashMap<int, Gtk.Widget> ();

	public ButtonDialog (string title, Gtk.Window? parent) {
		this.title = title;
		transient_for = parent;
		modal = true;
		destroy_with_parent = true;
		resizable = false;

		content_area = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
		content_area.margin_top = content_area.margin_start = content_area.margin_end = 12;
		content_area.vexpand = true;
		action_area = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
		action_area.halign = Gtk.Align.END;
		action_area.margin_top = action_area.margin_bottom = 12;
		action_area.margin_start = action_area.margin_end = 12;
		var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		box.append (content_area);
		box.append (action_area);
		child = box;

		close_request.connect (() => {
			response (DELETE_EVENT);
			return false;
		});
		var keys = new Gtk.EventControllerKey ();
		keys.key_pressed.connect ((keyval, code, state) => {
			if (keyval != Gdk.Key.Escape)
				return false;
			response (CANCEL);
			return true;
		});
		((Gtk.Widget) this).add_controller (keys);
	}

	public Gtk.Button add_button (string label, int answer) {
		var button = new Gtk.Button.with_mnemonic (label);
		button.clicked.connect (() => response (answer));
		add_action_widget (button, answer);
		return button;
	}

	public void add_action_widget (Gtk.Widget widget, int answer) {
		action_area.append (widget);
		buttons[answer] = widget;
	}

	public Gtk.Widget? get_widget_for_response (int answer) {
		return buttons[answer];
	}

	/** The button Enter presses (in an entry with activates_default) */
	public void set_default_response (int answer) {
		var button = buttons[answer];
		if (button != null)
			default_widget = button;
	}

	public void set_response_sensitive (int answer, bool sensitive) {
		var button = buttons[answer];
		if (button != null)
			button.sensitive = sensitive;
	}

	/** Shows it and waits for the answer; the dialog stays open: destroy it when done */
	public async int run () {
		int answer = NONE;
		ulong id = response.connect ((r) => {
			answer = r;
			Idle.add (run.callback);
		});
		present ();
		yield;
		disconnect (id);
		return answer;
	}
}

[GIR (visible = false)]
namespace BeatBox.UI {
	/** A message with an OK button; it doesn't wait */
	public void alert (Gtk.Window? parent, string heading, string? detail = null) {
		var dialog = new Gtk.AlertDialog ("%s", heading);
		dialog.detail = detail;
		dialog.modal = true;
		dialog.show (parent);
	}

	/** A question with Cancel and accept_label: true for accept_label (false when dismissed) */
	public async bool confirm (Gtk.Window? parent, string heading, string? detail, string accept_label) {
		return (yield choose (parent, heading, detail, { _("Cancel"), accept_label }, 0, 1)) == 1;
	}

	/** A question with these buttons: the number of the one pressed, or cancel_button when dismissed */
	public async int choose (Gtk.Window? parent, string heading, string? detail, string[] buttons,
	                         int cancel_button, int default_button) {
		var dialog = new Gtk.AlertDialog ("%s", heading);
		dialog.detail = detail;
		dialog.modal = true;
		dialog.buttons = buttons;
		dialog.cancel_button = cancel_button;
		dialog.default_button = default_button;
		try {
			return yield dialog.choose (parent, null);
		} catch (Error err) {
			return cancel_button;
		}
	}

	Gtk.FileDialog file_dialog (string title, Gtk.FileFilter[]? filters, File? initial_folder) {
		var dialog = new Gtk.FileDialog ();
		dialog.title = title;
		dialog.modal = true;
		if (initial_folder != null)
			dialog.initial_folder = initial_folder;
		if (filters != null && filters.length > 0) {
			var list = new GLib.ListStore (typeof (Gtk.FileFilter));
			foreach (var filter in filters)
				list.append (filter);
			dialog.filters = list;
			dialog.default_filter = filters[0];
		}
		return dialog;
	}

	/** A folder chosen by the user, or null */
	public async File? choose_folder (Gtk.Window? parent, string title, File? initial_folder = null) {
		try {
			return yield file_dialog (title, null, initial_folder).select_folder (parent, null);
		} catch (Error err) {
			return null; // dismissed
		}
	}

	/** Several folders, or none */
	public async Gee.List<File> choose_folders (Gtk.Window? parent, string title, File? initial_folder = null) {
		var chosen = new Gee.ArrayList<File> ();
		try {
			var files = yield file_dialog (title, null, initial_folder).select_multiple_folders (parent, null);
			for (uint i = 0; files != null && i < files.get_n_items (); i++)
				chosen.add ((File) files.get_item (i));
		} catch (Error err) {
			// dismissed
		}
		return chosen;
	}

	/** A file to open, or null */
	public async File? open_file (Gtk.Window? parent, string title, Gtk.FileFilter[]? filters = null, File? initial_folder = null) {
		try {
			return yield file_dialog (title, filters, initial_folder).open (parent, null);
		} catch (Error err) {
			return null;
		}
	}

	/** Several files to open, or none */
	public async Gee.List<File> open_files (Gtk.Window? parent, string title, Gtk.FileFilter[]? filters = null, File? initial_folder = null) {
		var chosen = new Gee.ArrayList<File> ();
		try {
			var files = yield file_dialog (title, filters, initial_folder).open_multiple (parent, null);
			for (uint i = 0; files != null && i < files.get_n_items (); i++)
				chosen.add ((File) files.get_item (i));
		} catch (Error err) {
			// dismissed
		}
		return chosen;
	}

	/** Where to save a file, or null */
	public async File? save_file (Gtk.Window? parent, string title, string? initial_name = null, File? initial_folder = null, Gtk.FileFilter[]? filters = null) {
		var dialog = file_dialog (title, filters, initial_folder);
		if (initial_name != null)
			dialog.initial_name = initial_name;
		try {
			return yield dialog.save (parent, null);
		} catch (Error err) {
			return null;
		}
	}
}

/** A bar over the content with a message and buttons, in place of Gtk.InfoBar (deprecated in GTK 4.10) */
[GIR (visible = false)]
public class BeatBox.MessageBar : Gtk.Box {
	const string CSS = """
		.bb-message-bar { padding: 6px 12px; border-bottom: 1px solid alpha(black, .15); }
		.bb-message-bar.warning { background-color: #fbe9b0; color: #3b2f00; }
		.bb-message-bar.error { background-color: #f2c4c0; color: #4a0d07; }
		.bb-message-bar.info { background-color: #cfe0f5; color: #0d2a4a; }
	""";

	public signal void response (int answer);

	Gtk.Box buttons;

	public MessageBar (Gtk.MessageType type) {
		Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
		UI.add_css (CSS);
		add_css_class ("bb-message-bar");
		message_type = type;
		buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
		buttons.valign = Gtk.Align.CENTER;
		append (buttons);
	}

	public Gtk.MessageType message_type {
		set {
			foreach (var kind in new string[] { "warning", "error", "info" })
				remove_css_class (kind);
			add_css_class (value == Gtk.MessageType.ERROR ? "error" : value == Gtk.MessageType.WARNING ? "warning" : "info");
		}
	}

	/** The message, before the buttons */
	public void add_child (Gtk.Widget child) {
		child.hexpand = true;
		insert_child_after (child, buttons.get_prev_sibling ());
	}

	public Gtk.Button add_button (string label, int answer) {
		var button = new Gtk.Button.with_mnemonic (label);
		button.clicked.connect (() => response (answer));
		buttons.append (button);
		return button;
	}
}
