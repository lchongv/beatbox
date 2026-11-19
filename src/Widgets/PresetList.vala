/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
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
/** The equalizer's presets: Automatic, Delete Current (for a custom preset), the built-in
 *  presets, then the custom ones after a line */
public class BeatBox.PresetList : ChoiceBox {
	// the built-in preset names, for the translations (see Settings.Equalizer.default_presets)
	const string[] DEFAULT_NAMES = { N_("Flat"), N_("Classical"), N_("Club"), N_("Dance"), N_("Full Bass"),
		N_("Full Treble"), N_("Full Bass + Treble"), N_("Headphones"), N_("Large Hall"), N_("Live"), N_("Party"),
		N_("Pop"), N_("Reggae"), N_("Rock"), N_("Soft"), N_("Ska"), N_("Soft Rock"), N_("Techno") };

	public signal void preset_selected(EqualizerPreset p);
	public signal void automatic_preset_chosen();
	public signal void delete_preset_chosen();

	public bool automatic_chosen {
		get {
			return automatic_selected;
		}
	}

	public EqualizerPreset last_selected_preset;

	const string AUTOMATIC_ID = "automatic";
	const string DELETE_ID = "delete";

	Gee.List<EqualizerPreset> presets = new Gee.ArrayList<EqualizerPreset>();
	bool modifying_list = false;
	bool automatic_selected = false;
	bool show_delete = false; // a custom preset is chosen: it can be deleted

	public PresetList() {
		changed.connect(listSelectionChange);
		rebuild(null);
	}

	/** The items again, choosing `chosen` (the preset object), or Automatic for null */
	void rebuild(EqualizerPreset? chosen) {
		modifying_list = true;
		remove_all();
		append(AUTOMATIC_ID, _("Automatic"));
		append_separator();
		if (show_delete) {
			append(DELETE_ID, _("Delete Current"));
			append_separator();
		}
		bool custom_seen = false;
		foreach (var ep in presets) {
			if (ep.is_default)
				// the built-in presets keep their English names (saved, and matched against
				// genres in automatic mode); only the list shows them translated
				append(null, _(ep.name), ep);
		}
		foreach (var ep in presets) {
			if (ep.is_default)
				continue;
			if (!custom_seen) {
				append_separator();
				custom_seen = true;
			}
			append(null, ep.name, ep);
		}
		active = (chosen != null) ? position_of(chosen) : 0;
		modifying_list = false;
	}

	int position_of(EqualizerPreset ep) {
		for (int i = 0; i < n_items; i++)
			if (get_item_data(i) == ep)
				return i;
		return 0;
	}

	public void addPreset(EqualizerPreset ep) {
		presets.add(ep);
		automatic_selected = false;
		show_delete = !ep.is_default;
		last_selected_preset = ep;
		rebuild(ep);
		preset_selected(ep); // the one added is chosen, as before
	}

	public void removeCurrentPreset() {
		if (last_selected_preset != null && !last_selected_preset.is_default)
			presets.remove(last_selected_preset);
		show_delete = false;
		rebuild(null);
		selectAutomaticPreset();
	}

	void listSelectionChange() {
		if (modifying_list || active < 0)
			return;

		var o = get_active_data();
		if (o != null && o is EqualizerPreset) {
			var ep = (EqualizerPreset) o;
			last_selected_preset = ep;
			automatic_selected = false;
			if (show_delete != !ep.is_default) {
				show_delete = !ep.is_default; // Delete Current comes and goes with a custom preset
				Idle.add(() => { rebuild(ep); return false; }); // not while the menu is answering
			}
			preset_selected(ep);
			return;
		}

		switch (active_id) {
			case AUTOMATIC_ID:
				automatic_selected = true;
				if (show_delete) {
					show_delete = false;
					Idle.add(() => { rebuild(null); return false; });
				}
				automatic_preset_chosen();
				break;
			case DELETE_ID:
				delete_preset_chosen();
				break;
		}
	}

	public void selectAutomaticPreset() {
		automatic_selected = true;
		automatic_preset_chosen();
		modifying_list = true;
		active = 0;
		modifying_list = false;
	}

	public void selectPreset(string? preset_name) {
		if (!(preset_name == null || preset_name.length < 1)) {
			foreach (var ep in presets) {
				if (ep.name == preset_name) {
					automatic_selected = false;
					last_selected_preset = ep;
					show_delete = !ep.is_default;
					rebuild(ep);
					preset_selected(ep);
					return;
				}
			}
		}

		selectAutomaticPreset();
	}

	public EqualizerPreset? getSelectedPreset() {
		return get_active_data() as EqualizerPreset;
	}

	public Gee.Collection<EqualizerPreset> getPresets() {
		var rv = new Gee.LinkedList<EqualizerPreset>();
		rv.add_all(presets);
		return rv;
	}
}
