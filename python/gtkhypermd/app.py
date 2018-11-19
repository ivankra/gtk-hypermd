import os
import signal
import sys

from gi.repository import GLib, Gio, Gtk
from pathlib import Path

from .buffers import Buffers
from .window import Window

APP_ID = 'me.ivank.gtk-hypermd'


class Application(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)

        self.add_main_option('tray', ord('t'),
                             GLib.OptionFlags.NONE, GLib.OptionArg.NONE,
                             'Enable tray mode', None)

        self.buffers = Buffers()
        self.base_path = Path(__file__).absolute().parents[2]  # repo root
        self.gsettings = None
        self.options = {}

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.quit)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.quit)

    def do_command_line(self, command_line):
        self.gsettings = self.create_gsettings()
        self.options = command_line.get_options_dict().end().unpack()
        self.activate()
        return 0

    def do_activate(self):
        if len(self.get_windows()) == 0:
            window = Window(self, tray=self.options.get('tray', False))
            window.view.load(self.base_path / 'README.md')
            window.show()
        else:
            # activated because user tried to start another instance
            for window in self.get_windows():
                window.show()

    def create_gsettings(self):
        schema_source = Gio.SettingsSchemaSource.new_from_directory(
            (self.base_path / 'data').as_posix(),
            Gio.SettingsSchemaSource.get_default(), False)
        schema = schema_source.lookup(self.get_application_id(), False)
        return Gio.Settings.new_full(schema, None, None)

    def load_default_window_state(self):
        state = dict()
        state['width'], state['height'], state['x'], state['y'] = \
            self.gsettings.get_value('window-geometry')
        state['sidebar-width'] = \
            self.gsettings.get_value('sidebar-width').get_int32()
        return state

    def save_default_window_state(self, state):
        val = (state['width'], state['height'], state['x'], state['y'])
        val = GLib.Variant.new_tuple(*[GLib.Variant('i', i) for i in val])
        self.gsettings.set_value('window-geometry', val)
        self.gsettings.set_value('sidebar-width',
                                 GLib.Variant('i', state['sidebar-width']))
