#!/usr/bin/env python3
# Smoke test: BeatBox started for real, in a private X server, D-Bus session and home.
# It imports three short songs, plays the library from the top, goes Next and
# Previous, lets a song end, quits, and starts again with two of the songs opened
# as files: the library and the play count are kept, and Next goes from one to
# the other.
# Driven through MPRIS; nothing is heard (the real audio outputs are ranked out).
# Usage: smoke.py path/to/beatbox   (skipped, exit 77, without Xvfb, dbus-run-session
# or GStreamer's tools; a failure instead with SMOKE_REQUIRED=1)

import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

SKIP = 77
BUS = ['--session', '--dest', 'org.mpris.MediaPlayer2.beatbox', '--object-path', '/org/mpris/MediaPlayer2']
SONGS = 3
SONG_SECONDS = 8


def fail(why):
    print('FAIL:', why)
    sys.exit(1)


def wait_for(what, check, timeout):
    end = time.time() + timeout
    while time.time() < end:
        value = check()
        if value:
            return value
        time.sleep(0.5)
    fail('timed out waiting for ' + what)


def gdbus(method, *args):
    r = subprocess.run(['gdbus', 'call', *BUS, '--method', method, *args],
                       capture_output=True, text=True, timeout=30)
    return r.stdout if r.returncode == 0 else None


def prop(name):
    return gdbus('org.freedesktop.DBus.Properties.Get', 'org.mpris.MediaPlayer2.Player', name) or ''


def status():
    m = re.search(r"'(Playing|Paused|Stopped)'", prop('PlaybackStatus'))
    return m and m.group(1)


def track():
    m = re.search(r"'mpris:trackid': <objectpath '([^']+)'", prop('Metadata'))
    return m and m.group(1)


def position():
    m = re.search(r'<(?:int64 )?(\d+)>', prop('Position'))
    return int(m.group(1)) if m else -1


def player(method, *args):
    if gdbus('org.mpris.MediaPlayer2.Player.' + method, *args) is None:
        fail(method + ' failed')


def songs(db):
    try:
        with sqlite3.connect('file:%s?mode=ro' % db, uri=True, timeout=1) as c:
            return c.execute('SELECT rowid, uri, playcount FROM songs').fetchall()
    except sqlite3.Error:
        return []  # not there yet, or being written


def song_row(db, uri):
    try:
        with sqlite3.connect('file:%s?mode=ro' % db, uri=True, timeout=1) as c:
            return c.execute('SELECT playcount, rating FROM songs WHERE uri = ?', (uri,)).fetchone()
    except sqlite3.Error:
        return None  # not there yet, or being written


def table_rowids(db, table):
    try:
        with sqlite3.connect('file:%s?mode=ro' % db, uri=True, timeout=1) as c:
            return [r[0] for r in c.execute('SELECT rowid FROM %s ORDER BY rowid' % table)]
    except sqlite3.Error:
        return []


def insert_row(db, table, rowid, **values):
    """A whole row as BeatBox writes them: every TEXT column '' and every number 0 unless given"""
    with sqlite3.connect(db, timeout=5) as c:
        row = {r[1]: ('' if r[2] == 'TEXT' else 0) for r in c.execute('PRAGMA table_info(%s)' % table)}
        row.update(values)
        c.execute('INSERT INTO %s (rowid, %s) VALUES (?, %s)' % (table, ', '.join(row), ', '.join('?' * len(row))),
                  [rowid, *row.values()])


def conf_replace(conf, before, after):
    with open(conf) as f:
        text = f.read()
    if before not in text:
        fail('%r is not in beatbox.conf' % before)
    with open(conf, 'w') as f:
        f.write(text.replace(before, after, 1))


def make_song(path, freq):
    subprocess.run(['gst-launch-1.0', '-q', 'audiotestsrc', 'num-buffers=%d' % (SONG_SECONDS * 44100 // 1024),
                    'freq=%d' % freq, '!', 'audioconvert', '!', 'vorbisenc', '!', 'oggmux',
                    '!', 'filesink', 'location=' + path], check=True)


def start(app, home, log, files=()):
    proc = subprocess.Popen([app, *files], stdout=log, stderr=subprocess.STDOUT)
    wait_for('BeatBox on D-Bus', lambda: proc.poll() is None and
             gdbus('org.freedesktop.DBus.Peer.Ping') is not None or proc.poll() is not None, 90)
    if proc.poll() is not None:
        fail('BeatBox exited at startup with %d' % proc.returncode)
    return proc


def quit(proc):
    gdbus('org.mpris.MediaPlayer2.Quit')
    try:
        code = proc.wait(60)
    except subprocess.TimeoutExpired:
        proc.kill()
        fail('BeatBox did not quit')
    if code != 0:
        fail('BeatBox quit with %d' % code)


def track_of(db, path):
    uri = 'file://' + path.replace(' ', '%20')
    return ['/org/gnome/BeatBox/Track/%d' % rowid for rowid, u, count in songs(db) if u == uri][0]


def play_from_top():
    gdbus('org.mpris.MediaPlayer2.Player.Play')  # until the list shows the imported songs
    return status() == 'Playing'


def run(app, home):
    music = os.path.join(home, 'Music')
    os.makedirs(music)
    os.makedirs(os.path.join(home, '.config'))
    with open(os.path.join(home, '.config', 'user-dirs.dirs'), 'w') as f:
        f.write('XDG_MUSIC_DIR="%s"\n' % music)
    for i in range(SONGS):
        path = os.path.join(music, 'Song %d.ogg' % (i + 1))
        make_song(path, 330 + 110 * i)
    db = os.path.join(home, '.local', 'share', 'beatbox', 'beatbox.db')
    log = open(os.path.join(home, 'beatbox.log'), 'w')

    try:
        # first run: the music folder is imported
        proc = start(app, home, log)
        wait_for('the import', lambda: len(songs(db)) == SONGS, 90)
        print('imported', SONGS, 'songs')

        wait_for('playback', play_from_top, 20)
        a = track()
        p = position()
        wait_for('the position to move', lambda: position() > p, 10)
        print('playing', a)

        player('Next')
        b = wait_for('Next', lambda: track() not in (None, a) and track(), 10)
        wait_for('playback after Next', lambda: status() == 'Playing', 10)
        player('Previous')  # within 5 s of the start: the previous song, not a restart
        wait_for('Previous', lambda: track() == a, 10)
        print('Next went to', b, 'and Previous back')

        wait_for('the song to end and the next to start', lambda: track() not in (None, a), SONG_SECONDS + 15)
        wait_for('playback after the end', lambda: status() == 'Playing', 10)
        print('a song ended and', track(), 'followed')

        quit(proc)
        played = [count for rowid, uri, count in songs(db) if a.endswith('/%d' % rowid)]
        if not played or not played[0]:
            fail('the play of %s was not counted: %s' % (a, songs(db)))
        print('quit;', a, 'played', played[0], 'times')

        # second run, with two songs of the library opened as files
        # opened 3 then 2: not the library's order, where Next after 3 wraps around or stops
        three, two = (os.path.join(music, 'Song %d.ogg' % n) for n in (3, 2))
        proc = start(app, home, log, [three, two])
        wait_for('the opened song', lambda: track() == track_of(db, three) and status() == 'Playing', 20)
        if len(songs(db)) != SONGS:
            fail('the library has %d songs after a restart' % len(songs(db)))
        time.sleep(1)  # past the startup restore, which must leave it alone
        if track() != track_of(db, three):
            fail('the opened song was replaced by %s' % track())
        player('Next')
        wait_for('Next to the other opened song', lambda: track() == track_of(db, two), 10)
        print('restarted with two songs opened; Next went from one to the other')
        quit(proc)

        # third run: the live sync with itunes7 (docs/SYNC-BEATBOX.md in itunes7). A
        # stand-in itunes7 library where Song 1 has 5 plays and 4 stars: BeatBox adds
        # them when it starts, then follows one more play made there while it runs.
        one_uri = 'file://' + os.path.join(music, 'Song 1.ogg').replace(' ', '%20')
        own = song_row(db, one_uri)[0]
        it7_dir = os.path.join(home, '.local', 'share', 'itunes7')
        os.makedirs(it7_dir)
        it7_db = os.path.join(it7_dir, 'library.db')
        with sqlite3.connect(it7_db) as c:
            c.executescript('''PRAGMA journal_mode=WAL;
                CREATE TABLE tracks (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT UNIQUE NOT NULL,
                  play_count INTEGER NOT NULL DEFAULT 0, last_played INTEGER NOT NULL DEFAULT 0,
                  rating INTEGER NOT NULL DEFAULT 0, skip_shuffle INTEGER NOT NULL DEFAULT 0,
                  remember_pos INTEGER NOT NULL DEFAULT 0, volume_adjust INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE bookmarks (uri TEXT PRIMARY KEY NOT NULL, pos INTEGER NOT NULL DEFAULT 0);''')
            c.execute('INSERT INTO tracks (uri, play_count, last_played, rating) VALUES (?, 5, 1700000000, 80)',
                      (one_uri,))
        conf = os.path.join(home, '.config', 'beatbox', 'beatbox.conf')
        with open(conf) as f:
            text = f.read()
        if 'itunes7-sync=false' not in text:
            fail('beatbox.conf has no itunes7-sync option')
        with open(conf, 'w') as f:
            f.write(text.replace('itunes7-sync=false', 'itunes7-sync=true'))
        proc = start(app, home, log)
        wait_for('the plays and rating from itunes7', lambda: song_row(db, one_uri) == (own + 5, 4), 20)
        if not os.path.exists(db + '.pre-sync'):
            fail('no backup before the first sync with itunes7')
        with sqlite3.connect(it7_db, timeout=5) as c:  # one more play in itunes7, BeatBox running
            c.execute('UPDATE tracks SET play_count = 6, last_played = 1700000100 WHERE uri = ?', (one_uri,))
        wait_for('the live play from itunes7', lambda: song_row(db, one_uri) == (own + 6, 4), 15)
        time.sleep(3)  # no echo between the two apps: still the same a moment later
        if song_row(db, one_uri) != (own + 6, 4):
            fail('the count kept moving: %s' % (song_row(db, one_uri),))
        print('itunes7 sync: 5 plays and the rating at start, then one more live')
        quit(proc)

        # fourth run: a second library (docs/superpowers/specs/2026-10-11-multiple-libraries-design.md),
        # set up in beatbox.conf as "New Library..." leaves it. It has its own songs and play
        # counts; radio and podcasts stay the main library's, and media ids never collide.
        insert_row(db, 'stations', 900, uri='http://radio.invalid/live', title='Radio', mediatype=3)
        insert_row(db, 'podcasts', 901, uri='http://podcast.invalid/1.mp3', title='Episode', mediatype=1,
                   podcast_rss='http://podcast.invalid/feed')
        b_music = os.path.join(home, 'Music B')
        os.makedirs(b_music)
        for i in range(2):
            make_song(os.path.join(b_music, 'B %d.ogg' % (i + 1)), 550 + 110 * i)
        conf_replace(conf, '\nlibrary=\n', '\nlibrary=b\n')
        with open(conf, 'a') as f:
            f.write('\n[library b]\nlibrary-name=B\nmusic-folder=%s\n' % b_music)
        b_db = os.path.join(home, '.local', 'share', 'beatbox', 'libraries', 'b.db')
        proc = start(app, home, log)
        wait_for('the import of library B', lambda: len(songs(b_db)) == 2, 90)
        wait_for('playback in library B', play_from_top, 20)
        b_track = track()
        p = position()
        wait_for('the position to move in library B', lambda: position() > p, 10)
        wait_for('the play in library B to be counted', lambda: any(count for rowid, uri, count in songs(b_db)), 30)
        quit(proc)
        b_ids = [rowid for rowid, uri, count in songs(b_db)]
        if len(songs(db)) != SONGS:
            fail('library B changed the main one: %s' % songs(db))
        if not any(count for rowid, uri, count in songs(b_db)):
            fail('the play in library B was not counted: %s' % songs(b_db))
        if (table_rowids(db, 'stations'), table_rowids(db, 'podcasts')) != ([900], [901]):
            fail('radio or podcasts changed: %s %s' % (table_rowids(db, 'stations'), table_rowids(db, 'podcasts')))
        if set(b_ids) & {900, 901}:
            fail('a song of library B has the id of a station or podcast: %s' % b_ids)
        if b_track.rsplit('/', 1)[1] not in map(str, b_ids):
            fail('playing %s, not a song of library B %s' % (b_track, b_ids))
        with open(conf) as f:
            last = int(re.search(r'\nlast-rowid=(\d+)\n', f.read()).group(1))
        if last < max(b_ids + [900, 901] + [rowid for rowid, uri, count in songs(db)]):
            fail('last-rowid %d is behind the ids given' % last)
        print('library B: its own songs and play count; radio, podcasts and ids kept apart')

        # fifth run: beatbox.conf names a library that is gone: the main one opens
        conf_replace(conf, '\nlibrary=b\n', '\nlibrary=gone\n')
        proc = start(app, home, log)
        wait_for('playback in the main library', play_from_top, 20)
        main_tracks = ['/org/gnome/BeatBox/Track/%d' % rowid for rowid, uri, count in songs(db)]
        if track() not in main_tracks:
            fail('playing %s, not a song of the main library' % track())
        quit(proc)
        with open(conf) as f:
            if '\nlibrary=\n' not in f.read():
                fail('library=gone was kept')
        if os.path.exists(os.path.join(home, '.local', 'share', 'beatbox', 'libraries', 'gone.db')):
            fail('a database was made for the missing library')
        print('a library that is gone opens the main one')
    finally:
        log.close()
        if 'proc' in locals() and proc.poll() is None:
            proc.kill()
        with open(os.path.join(home, 'beatbox.log')) as f:
            criticals = [l for l in f if 'CRITICAL' in l]
        if criticals:
            print(''.join(criticals))
    if criticals:
        fail('BeatBox logged %d critical messages' % len(criticals))
    print('OK')


def main():
    app = os.path.abspath(sys.argv[1])
    if os.environ.get('SMOKE_INNER'):
        return run(app, os.environ['HOME'])

    for tool in ('Xvfb', 'dbus-run-session', 'gdbus', 'gst-launch-1.0'):
        if not shutil.which(tool):
            print('skipped: no', tool)
            sys.exit(1 if os.environ.get('SMOKE_REQUIRED') else SKIP)  # CI sets it

    home = tempfile.mkdtemp(prefix='beatbox-smoke-')
    read, write = os.pipe()
    xvfb = subprocess.Popen(['Xvfb', '-displayfd', str(write), '-screen', '0', '1100x700x24', '-nolisten', 'tcp'],
                            pass_fds=[write], stderr=subprocess.DEVNULL)
    os.close(write)
    display = os.read(read, 16).decode().strip()
    os.close(read)
    # XAUTHORITY is the desktop's cookie for its own X server: the test's X server doesn't accept it
    env = {k: v for k, v in os.environ.items() if k not in ('WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'XAUTHORITY')}
    env.update(SMOKE_INNER='1', DISPLAY=':' + display, GDK_BACKEND='x11', NO_AT_BRIDGE='1', HOME=home,
               XDG_CONFIG_HOME=home + '/.config', XDG_DATA_HOME=home + '/.local/share',
               XDG_CACHE_HOME=home + '/.cache', XDG_RUNTIME_DIR=home + '/run', LANG='C.UTF-8', LANGUAGE='',
               GST_PLUGIN_FEATURE_RANK=','.join(s + ':NONE' for s in (
                   'pulsesink', 'pipewiresink', 'alsasink', 'jackaudiosink', 'osssink', 'oss4sink', 'openalsink')))
    os.makedirs(home + '/run', mode=0o700)
    try:
        code = subprocess.run(['dbus-run-session', '--', sys.executable, os.path.abspath(__file__), app],
                              env=env).returncode
    finally:
        xvfb.terminate()
        xvfb.wait()
    if code == 0:
        shutil.rmtree(home)
    else:
        print('left for a look:', home)
    sys.exit(code)


if __name__ == '__main__':
    main()
