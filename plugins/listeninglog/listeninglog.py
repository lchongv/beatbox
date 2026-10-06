# Listening log: a line per song played, in ~/.local/share/beatbox/listening-log.txt.
# An example of a BeatBox plugin in Python (see docs/plugins.md).

import os
import time

import gi
gi.require_version('BeatBox', '1.0')
from gi.repository import BeatBox, GLib, GObject


class ListeningLog(GObject.Object, BeatBox.Plugin):

    def do_activate(self, host):
        self.path = os.path.join(GLib.get_user_data_dir(), 'beatbox', 'listening-log.txt')
        self.playback = host.props.playback
        self.handler = self.playback.connect('media-played', self.media_played)

    def do_deactivate(self):
        self.playback.disconnect(self.handler)
        self.playback = None

    def media_played(self, playback, media, old):
        line = '%s  %s - %s\n' % (time.strftime('%Y-%m-%d %H:%M'), media.props.artist, media.props.title)
        try:
            with open(self.path, 'a', encoding='utf-8') as log:
                log.write(line)
        except OSError as err:
            print('listeninglog: could not write %s: %s' % (self.path, err))
