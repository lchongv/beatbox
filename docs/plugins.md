# Writing BeatBox plugins

A plugin is code that BeatBox loads when the user turns it on in
Preferences › Plugins: a shared library written in Vala (or C) against
`libbeatbox-core`, the library BeatBox itself is built on, or a Python module.
Either way it gets the player, the library, the window and the settings to work
with.

Two complete, working examples are in this repository:
`plugins/nowplayingfile` (Vala) and `plugins/listeninglog` (Python). The
interface is in `core/Plugin.vala`.

## What a plugin is made of

A folder named after the plugin's id, with two files:

```
myplugin/
├── myplugin.plugin     description
└── libmyplugin.so      the code
```

`myplugin.plugin` is a key file:

```ini
[Plugin]
Module=myplugin
Name=My plugin
Name[es]=Mi complemento
Description=What it does, in one or two sentences.
Description[es]=Qué hace, en una o dos frases.
```

- `Module` is the id: the folder, the `.plugin` file and `lib<id>.so` all use it.
  Letters, digits, `-` and `_`.
- `Name` and `Description` are shown in Preferences; `Name[xx]=` and
  `Description[xx]=` translate them for the language `xx`.

## The code

The library implements `BeatBox.Plugin` and exports one function,
`beatbox_plugin_create`, that returns a new instance:

```vala
public class MyPlugin : Object, BeatBox.Plugin {
	BeatBox.PlaybackInterface? playback;

	public void activate(BeatBox.PluginHost host) {
		playback = host.playback;
		playback.media_played.connect(media_played);
	}

	public void deactivate() {
		playback.media_played.disconnect(media_played);
		playback = null;
	}

	void media_played(BeatBox.Media m, BeatBox.Media? old) {
		message("Now playing %s by %s", m.title, m.artist);
	}
}

// outside any namespace, so the C symbol is exactly beatbox_plugin_create
public BeatBox.Plugin beatbox_plugin_create() {
	return new MyPlugin();
}
```

`activate (PluginHost host)` is called when the plugin is turned on (also at
startup, if it was on when BeatBox closed). `host` has:

| Property | Type | What for |
| --- | --- | --- |
| `playback` | `PlaybackInterface` | the playing song (`current_media`), play/pause/next, and signals such as `media_played`, `playback_stopped`, `current_position_update` |
| `library` | `LibraryInterface` | the songs, podcasts and stations; `medias_added`, `medias_updated`, `medias_removed` |
| `window` | `LibraryWindowInterface` | the main window (a `Gtk.Window`): dialogs, `doAlert (title, text)` |
| `settings` | `Settings` | BeatBox's options (`settings.main`, `settings.lastfm`, …) |

The interfaces are in `core/` (`PlaybackInterface.vala`, `LibraryInterface.vala`,
`LibraryWindowInterface.vala`, `Media/Media.vala`, `Settings.vala`).

Rules:

- **`deactivate ()` undoes `activate ()`**: disconnect every signal, remove the
  widgets you added, stop timers. The user can turn the plugin off and on again
  without restarting, and the same instance is reused.
- **Everything runs on the main thread.** Long work goes to a thread, and its
  results come back with `Idle.add`, as in BeatBox itself.
- **A loaded plugin stays loaded** until BeatBox quits (its GObject types can't
  be unregistered). Installing a new version of a plugin that is in use takes
  effect after a restart.
- Use `message`, `warning` and `debug` for logging; run BeatBox with
  `G_MESSAGES_DEBUG=all` to see the debug messages.

## Building

### Outside BeatBox's tree (the usual way)

BeatBox installs what a plugin needs: `beatbox-core.pc`, `beatbox-core.vapi`
(with its `.deps`) and the header. With BeatBox installed in `/usr`:

```sh
valac --library=myplugin --pkg beatbox-core \
      -X -fPIC -X -shared -o libmyplugin.so MyPlugin.vala
```

or with meson:

```meson
project('myplugin', 'vala', 'c')
beatbox = dependency('beatbox-core')
plugindir = beatbox.get_variable(pkgconfig: 'plugindir')
shared_module('myplugin', 'MyPlugin.vala',
  dependencies: beatbox,
  install: true, install_dir: plugindir / 'myplugin')
install_data('myplugin.plugin', install_dir: plugindir / 'myplugin')
```

If BeatBox is installed somewhere else (for example `~/.local`), tell
pkg-config and valac where:

```sh
export PKG_CONFIG_PATH=~/.local/lib/pkgconfig
valac --vapidir ~/.local/share/vala/vapi --library=myplugin --pkg beatbox-core \
      -X -fPIC -X -shared -o libmyplugin.so MyPlugin.vala
```

### Inside BeatBox's tree

Put the folder in `plugins/` with a `meson.build` like
`plugins/nowplayingfile/meson.build`, and add `subdir('myplugin')` to
`plugins/meson.build`. It is built with BeatBox, runs from the build directory
and is installed and packaged with it.

## Installing

- From BeatBox: Preferences › Plugins › **Install Plugin…**, then choose the
  `.plugin` file. It and its code next to it (`lib<id>.so`, or the Python
  module) are copied to
  `~/.local/share/beatbox/plugins/<id>/`; then turn the plugin on.
- By hand: copy the folder to `~/.local/share/beatbox/plugins/`.

BeatBox looks for plugins, in this order (the first one found with an id wins):

1. `~/.local/share/beatbox/plugins/`
2. `plugins/` next to the program (the build directory, an AppImage, a portable bundle)
3. `lib/beatbox/plugins/` under the prefix it was installed to
   (`pkg-config --variable=plugindir beatbox-core`)

A plugin is built for one version of `libbeatbox-core`: rebuild it when
BeatBox's interfaces change. If it can't be loaded, the checkbox stays off and
the reason is in BeatBox's log (start it from a terminal).

## Python

BeatBox describes `libbeatbox-core` with GObject Introspection (the
`BeatBox-1.0` typelib) and loads Python plugins with libpeas. A build has
Python support when libpeas-2 and gobject-introspection were found
(`meson setup -Dpython=enabled` to require them); the Debian 13, Ubuntu 26.04,
Fedora and Arch packages have it. The AppImage (built on Ubuntu 22.04, which
has no libpeas-2) and the Ubuntu 24.04 package (its libpeas 2.0 has no Vala
bindings) don't: there Python plugins are skipped and Install Plugin… refuses
them.
At run time PyGObject is needed (`python3-gi`, `python3-gobject` or
`python-gobject`, depending on the distribution).

The folder holds the `.plugin` file with `Loader=python`, and the code as
`<id>.py` or as a package `<id>/__init__.py`:

```
myplugin/
├── myplugin.plugin
└── myplugin.py
```

```ini
[Plugin]
Module=myplugin
Loader=python
Name=My plugin
Description=What it does.
```

```python
import gi
gi.require_version('BeatBox', '1.0')
from gi.repository import BeatBox, GObject


class MyPlugin(GObject.Object, BeatBox.Plugin):

    def do_activate(self, host):
        self.playback = host.props.playback
        self.handler = self.playback.connect('media-played', self.media_played)

    def do_deactivate(self):
        self.playback.disconnect(self.handler)
        self.playback = None

    def media_played(self, playback, media, old):
        print('Now playing', media.props.title, 'by', media.props.artist)
```

- The class implements `BeatBox.Plugin` through `do_activate` and
  `do_deactivate`, with the same rules as in Vala.
- Properties are read with `.props` (`media.props.title`,
  `host.props.playback`); methods and signals keep their names
  (`playback.connect('media-played', …)`, `playback.get_current_media()`).
- `python3 -c "import gi; gi.require_version('BeatBox', '1.0')"` with
  `GI_TYPELIB_PATH` pointing to the typelib checks the setup outside BeatBox;
  BeatBox sets that path itself.
- Not every part of `libbeatbox-core` is visible from Python: the list and
  grid widgets, the operations and the database are internal.

Nothing is built: install it with Install Plugin… (choosing the `.plugin`
file; the `.py` file or the package folder next to it is copied too) or copy
the folder to `~/.local/share/beatbox/plugins/`.

## Compatibility

From BeatBox 1.0, `libbeatbox-core` is stable for the whole 1.x series: a
plugin built for 1.0 keeps working with every 1.x. What a plugin sees (the
classes and interfaces in `core/`, and `BeatBox-1.0` from Python) only grows:
nothing is removed or renamed, and no method changes its arguments. What is
hidden from plugins (marked internal in the code, or invisible from Python)
can change at any time.

BeatBox 2.0 will move to GTK 4. Plugins that build their own widgets will need
changes then; the others most likely won't.
