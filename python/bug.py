#!/usr/bin/env python3
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Granite', '1.0')
from gi.repository import Granite, Gtk

class Item(Granite.WidgetsSourceListItem):
    def __init__(self):
        super().__init__(name='item')

    def do_get_context_menu(self):
        print('do_get_context_menu called')
        return Gtk.Menu()

item = Item()
print(item.get_context_menu())
