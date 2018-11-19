# TOOD: Use Granite.WidgetsSourceList after gi bindings are fixed
import os

from gi.repository import GLib, GObject, Gio, Gtk
from pathlib import Path


class TreeItem(object):
    def __init__(self, path=None):
        self.path = path
        self.is_dir = self.path and self.path.exists() and self.path.is_dir()

    def __str__(self):
        return self.path.as_posix() if self.path else '<dummy>'

    def listdir(self):
        files = sorted(os.listdir(self.path.as_posix()))
        files = [s for s in files if not s.startswith('.')]
        dirs = [s for s in files if (self.path / s).is_dir()]
        files = [s for s in files if s not in dirs and s.endswith('.md')]
        files = dirs + files
        return [TreeItem(self.path / s) for s in files]

class Sidebar(Gtk.TreeView):
    __gsignals__ = {
        'path-selected': (GObject.SIGNAL_RUN_LAST, None, (str,)),  # path
    }

    def __init__(self, root_path):
        Gtk.TreeView.__init__(self)

        self.set_headers_visible(False)
        self.set_activate_on_single_click(True)
        self.connect('row-activated', self.on_row_activated)
        self.connect('row-expanded', self.on_row_expanded)

        self.model = Gtk.TreeStore(object)
        self.dummy_item = TreeItem()
        it = self.model.append(None, [TreeItem(root_path)])
        self.model.append(it, [self.dummy_item])
        self.set_model(self.model)
        self.expand_row(Gtk.TreePath(), False)

        column = Gtk.TreeViewColumn('name')

        cell = Gtk.CellRendererPixbuf()
        column.pack_start(cell, False)
        column.set_cell_data_func(cell, self.render_icon)

        cell = Gtk.CellRendererText()
        column.pack_start(cell, False)
        column.set_cell_data_func(cell, self.render_text)

        self.append_column(column)

        self.get_style_context().add_class('sidebar')

    def render_icon(self, column, cell, model, tree_iter, data):
        item = model[tree_iter][0]
        if item is self.dummy_item:
            cell.set_property('icon-name', None)
        elif not item.is_dir:
            cell.set_property('icon-name', 'text-x-generic')
        #elif cell.get_property('is-expanded'):
        #    cell.set_property('icon-name', 'folder-open')
        else:
            cell.set_property('icon-name', 'folder')

    def render_text(self, column, cell, model, tree_iter, data):
        item = model[tree_iter][0]
        if item is self.dummy_item:
            html = '<i>(empty)</i>'
        else:
            html = GLib.markup_escape_text(item.path.name)
        cell.set_property('markup', html)

    def expand_model_at_iter(self, tree_iter):
        item = self.model[tree_iter][0]

        dummy_iter = self.model.iter_children(tree_iter)
        if dummy_iter is not None and self.model[dummy_iter][0] is not self.dummy_item:
            return

        sub_items = item.listdir()
        if len(sub_items) == 0:
            self.model.append(tree_iter, [self.dummy_item])
        else:
            for sub_item in sub_items:
                sub_iter = self.model.append(tree_iter, [sub_item])
                if sub_item.is_dir:
                    self.model.append(sub_iter, [self.dummy_item])

        if dummy_iter is not None:
            self.model.remove(dummy_iter)

    def on_row_expanded(self, widget, tree_iter, tree_path):
        self.expand_model_at_iter(tree_iter)

    def on_row_activated(self, widget, tree_iter, tree_path):
        item = self.model[tree_iter][0]
        if item is self.dummy_item: return
        if not item.path.exists() or item.path.is_dir(): return
        self.emit('path-selected', item.path.absolute().as_posix())
