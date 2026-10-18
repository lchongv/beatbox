# Several music libraries — design

Date: 2026-10-11. Status: approved in conversation, waiting for the review of this written spec.

## Goal

Separate music collections that live in different folders or on different drives
(an external disk mounted now and then, say), each with its own songs, ratings,
play counts and playlists, switched from the app menu. Internet radio and
podcasts are the same in every library.

Success: the user creates a library from a folder, switches between libraries
from the menu, each one keeps its statistics and playlists, radio and podcasts
are the same in all of them, and the drive a library lives on is mounted when
BeatBox opens it (if the drive is connected).

## Decisions taken

- Purpose: collections on different drives or folders (not one library per person or per kind of music).
- Radio stations and podcasts are shared by all the libraries.
- Switching restarts BeatBox (approach A). Rejected: a live switch without
  restarting (B: everything is built once at startup and holds the songs; much
  more code and risk of leaks and crashes) and one database with a library
  column (C: partner would see every library's songs mixed). A restart with the
  user's 1,142 songs takes about 1.5–2 s (measured headless: the window maps
  2.7 s after launch, Xvfb's start included).

## Data

**Main library**: what exists today, untouched and with no migration:
`~/.local/share/beatbox/beatbox.db` and the `[settings]` group of
`~/.config/beatbox/beatbox.conf`. partner keeps reading `beatbox.db`.

**Other libraries**: each one has an id (from its name, made unique: `disco-externo`, `disco-externo-2`) and

- its own database `~/.local/share/beatbox/libraries/<id>.db`, with the same
  schema: songs, playlists, smart playlists, list setups, the Last.fm info
  tables, devices, known_libraries;
- its own group `[library <id>]` in `beatbox.conf`.

**Options that belong to a library** (all the others stay shared):
`library-name`, `music-folder`, `music-mount-name`, `watch-music-folder`,
`last-media-playing`, `last-media-position` (group `settings`) and `queue`
(group `savedstate`). For the main library they stay in `[settings]` and
`[savedstate]` as today; while another library is active, they are read from
and written to `[library <id>]`. `ConfigSection` does this (a section lists
which of its keys belong to the library), so the code that reads
`App.settings.main.music_folder` and the rest does not change.

New keys in `[settings]`: `library` (id of the active library, empty = the main
one) and `library-name` (the main library's name, "Music" by default,
translated).

**Shared radio and podcasts**: while another library is active,
`DataBaseManager` opens its database and attaches `beatbox.db` as `shared`;
`StationLibrary` and `PodcastLibrary` (the only code that queries `stations`
and `podcasts`) prefix their tables with the schema `DataBaseManager` gives
(`shared.` or nothing).

**The podcast trap**: the first time a database opens, every library it does
not know (`known_libraries`) imports from its default folder, and that import
first empties the library. For podcasts that would delete the shared podcasts.
A new library's database is therefore created with the podcast and station
keys already in `known_libraries`; only the music library does its first
import (of the new library's folder).

**Media ids**: songs, podcasts and stations share one numbering (`rowid`,
given by `LibraryManager` from the highest id it has loaded). With several
databases that would collide: a podcast added in the main library could take
the number of a song in another one, and that library would mix the two up.
The highest id given in any library is therefore kept as a shared option,
`last-rowid` in `[settings]`, and every library goes on from it.

**First import of a new library**: `SongLibrary`'s default folder (the one a
database's first import reads) is the active library's `music-folder` when set,
and the user's Music folder (`XDG_MUSIC_DIR`) only when it is empty, as on a
first run.

**partner sync**: only while the main library is active (it compares with
`beatbox.db`, the file partner reads). With another library active the option
in Preferences › Library is insensitive, with a line saying why.

## Switching

- **Library** submenu in the app menu: the libraries as radio items (the active
  one checked), then "New Library…" and "Manage Libraries…".
- Choosing another library: refused with a message while an import or another
  operation runs; otherwise `[settings] library` is set, BeatBox quits the
  normal way (`LibraryWindow.on_quit` saves the playing position, the database
  and the options) and, once `app.run` returns in `main`, runs itself again
  (`execv` of `/proc/self/exe` with only `argv[0]`). The D-Bus name is released
  when the old connection closes at the exec. Files opened from the command
  line are not opened again.
- **New Library…**: a dialog with a name and a folder. It records the drive of
  the folder (below), creates the group and switches to the library, which
  imports the folder when it first opens.
- **Startup**: if `library` names a library without a group in the file, the
  main library opens and a warning is logged. A library whose database file is
  missing starts empty and imports its folder (first open).

## Drives

No new code: at startup `DeviceManager` goes through the mounts already there
and records, as `music-mount-name`, the volume of the one holding the music
folder (`mount_added`); at later startups it mounts that volume when it is
present and unmounted (`volume_added`). As `music-mount-name` belongs to the
library, each library remembers its own drive from its first open. If the drive
is not connected, the library opens anyway and its songs show as not found, as
today.

## Managing

- A **Libraries** section at the top of Preferences › Library (the page that
  already holds the library options; "Manage Libraries…" opens it): each
  library with its name and folder; Rename, and Remove (confirmation; deletes
  its database and its group). The main library and the active one cannot be
  removed. The active library's folder is still changed where it is today
  (Preferences › Music).
- The sidebar heading ("Library" today) shows the active library's name.

## Not included

- Moving or copying songs, playlists or statistics between libraries.
- Opening two libraries at once.
- Separate podcast folders, skins or plugins per library.

## Testing

Headless (Xvfb, private D-Bus, scratch home), with generated audio files only:

1. Main library with folder A (3 songs), one station and one podcast. Create
   library B (folder B, 2 songs) from the dialog: BeatBox restarts by itself and
   shows B's 2 songs and the same station and podcast.
2. Play and rate in B, switch back: A's play counts, ratings, queue and last song
   are intact; `stations` and `podcasts` in `beatbox.db` keep their rows.
3. Remove B: its database and group are gone; the main and the active library
   offer no Remove.
4. `library=` naming a missing library: the main one opens.
5. A read-only copy of the user's database opens unchanged as the main library,
   and the partner sync works with it.
6. `meson test smoke` passes.

7. The ids of library B's songs and of the shared stations and podcasts never
   coincide, and `last-rowid` is at least the highest of them.

Mounting a real drive cannot be done headless; the user checks it with a real drive.
