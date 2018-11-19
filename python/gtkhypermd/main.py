#!/usr/bin/env python3

import gi
gi.require_version('GLib', '2.0')
gi.require_version('Gdk', '3.0')
gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.0')

import sys
from pathlib import Path
sys.path.append(Path(__file__).resolve().parents[1].as_posix())

from gtkhypermd.app import Application

if __name__ == '__main__':
    app = Application()
    sys.exit(app.run(sys.argv))
