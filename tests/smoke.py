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
        subprocess.run(['gst-launch-1.0', '-q', 'audiotestsrc', 'num-buffers=%d' % (SONG_SECONDS * 44100 // 1024),
                        'freq=%d' % (330 + 110 * i), '!', 'audioconvert', '!', 'vorbisenc', '!', 'oggmux',
                        '!', 'filesink', 'location=' + path], check=True)
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
    env = {k: v for k, v in os.environ.items() if k not in ('WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS')}
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
