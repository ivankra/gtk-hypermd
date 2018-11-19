# TODO get get_context_menu override working

import os

from gi.repository import GLib, GObject, Gio, Gtk, Granite
from pathlib import Path

from .buffers import RenameOp
from .util import cached_property


class DummyItem(Granite.WidgetsSourceListItem):
    """Dummy item to put inside of a collapsed folder item."""

    def __init__(self):
        super().__init__(name='(empty)')


class FileItem(Granite.WidgetsSourceListItem):
    def __init__(self, path, sidebar):
        super().__init__(name=path.name)
        self.set_icon(Gio.ThemedIcon.new('text-x-generic'))
        self.set_editable(True)
        self.connect('edited', sidebar.on_item_edited)
        self.path = path

    def do_get_context_menu(self):
        print('FileItem.get_context_menu')


class FolderItem(Granite.WidgetsSourceListExpandableItem):
    def __init__(self, path, sidebar):
        super().__init__(name=path.name)
        self.set_icon(Gio.ThemedIcon.new('folder'))
        self.set_editable(True)
        self.connect('edited', sidebar.on_item_edited)
        self.connect('toggled', self.on_toggled)
        self.path = path
        self._children = []
        self._sidebar = sidebar
        self.add(DummyItem())

    def add(self, item):
        self._children.append(item)
        super().add(item)

    def clear(self):
        self._children = []
        super().clear()

    def on_toggled(self, widget, **args):
        self.refresh()

    def refresh(self):
        filenames = self.listdir()
        has_dummy = (len(self._children) == 1 and
                     type(self._children[0]) is DummyItem)

        if not self.get_expanded():
            if len(filenames) == 0:
                self.clear()
            elif len(filenames) > 0 and not has_dummy:
                self.clear()
                self.add(DummyItem())
            return

        if has_dummy:
            self.clear()

        old_items = {}
        for item in self._children:
            old_items[item.path.name] = item

        if set(old_items.keys()) != set(filenames):
            self.clear()
            for filename in filenames:
                path = self.path / filename
                item = old_items.get(filename, None)
                if item is None:
                    if path.is_dir():
                        item = FolderItem(path, self._sidebar)
                    else:
                        item = FileItem(path, self._sidebar)
                self.add(item)

        for item in self._children:
            if type(item) is FolderItem:
                item.refresh()

    def listdir(self):
        files = sorted(os.listdir(self.path.as_posix()))
        files = [s for s in files if not s.startswith('.')]
        dirs = [s for s in files if (self.path / s).is_dir()]
        files = [s for s in files if s not in dirs and s.endswith('.md')]
        return dirs + files

    def do_get_context_menu(self):
        print('FolderItem.get_context_menu')
        return self._sidebar.sidebar_menu



class Sidebar(Granite.WidgetsSourceList):
    __gsignals__ = {
        'file-selected': (GObject.SIGNAL_RUN_LAST, None, (str,)),  # path
    }

    def __init__(self, app):
        super().__init__(root=Granite.WidgetsSourceListExpandableItem())

        self.app = app
        self.buffers = app.buffers
        self.buffers.connect('on-rename', self.on_buffers_rename)

        self.builder = Gtk.Builder()
        self.builder.add_from_file((self.app.base_path / 'data/window.ui').as_posix())
        self.sidebar_menu = self.builder.get_object('sidebar_menu')

        self.toplevels = []

        self.get_style_context().add_class('sidebar')
        for child in self:
            if hasattr(child, 'set_activate_on_single_click'):  # TreeView
                child.get_style_context().add_class('sidebar')
                child.set_activate_on_single_click(True)

        self.connect('item-selected', self.on_item_selected)

    def add_toplevel(self, path: Path):
        """Add a top level folder item."""
        item = FolderItem(path, self)
        self.toplevels.append(item)
        self.get_root().add(item)
        item.refresh()
        item.expand_with_parents()

    def refresh(self):
        for item in self.toplevels:
            item.refresh()

    def on_item_selected(self, widget, item):
        if item and type(item) is FileItem:
            self.emit('file-selected', item.path.as_posix())

    def on_item_edited(self, item, new_name):
        if item is None: return
        if type(item) not in (FileItem, FolderItem): return

        old_path = item.path
        new_path = old_path.parent / new_name
        self.buffers.rename(RenameOp(old_path, new_path))

    def on_buffers_rename(self, obj, rename_op):
        self.refresh()
