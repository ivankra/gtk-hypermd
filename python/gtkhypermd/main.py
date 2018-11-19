#!/usr/bin/env python3

import gi
try:
    gi.require_version('GLib', '2.0')
    gi.require_version('Gdk', '3.0')
    gi.require_version('Gtk', '3.0')
    gi.require_version('Granite', '1.0')
    gi.require_version('WebKit2', '4.0')
except Exception as e:
    print('''\
Some libraries seem to be missing, try installing:
gir1.2-granite-1.0 gir1.2-webkit2-4.0 gobject-introspection libgirepository1.0-dev
''')
    raise

import sys
from pathlib import Path
sys.path.append(Path(__file__).resolve().parents[1].as_posix())

try:
    from gi.repository import Granite
    _ = Granite.WidgetsSourceList()
except TypeError:
    # File "/usr/lib/python3/dist-packages/gi/overrides/__init__.py", line 326, in new_init
    #   return super_init_func(self, **new_kwargs)
    # TypeError: could not get a reference to type class
    sys.stderr.write(r'''
Error: local version of gir1.2-granite-1.0 appears to be buggy and unusable.
Try to upgrade or reinstall it or run the following potential fix:

$ sudo bash -x -c "\
    sed -i /usr/share/gir-1.0/Granite-1.0.gir -e \
      's/<namespace n/<namespace shared-library=\"libgranite.so\" n/' && \
    g-ir-compiler /usr/share/gir-1.0/Granite-1.0.gir \
      -o /usr/lib/x86_64-linux-gnu/girepository-1.0/Granite-1.0.typelib"

''')

from gtkhypermd.app import Application

if __name__ == '__main__':
    app = Application()
    sys.exit(app.run(sys.argv))
