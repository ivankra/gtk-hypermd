from gi.repository import GLib, Gdk, Gtk

from .view import AppView
from .sidebar import Sidebar


class Window(object):
    def __init__(self, app, tray=True):
        self.app = app

        self.builder = Gtk.Builder()
        self.builder.add_from_file(self.app.get_data_path('window.ui').as_posix())
        self.builder.connect_signals(self)

        self.window = self.builder.get_object('window')

        self.window_state = self.app.load_default_window_state()
        self.window.connect('configure-event', self.on_configure_event)
        self.resize_timer_id = None

        self.sidebar = Sidebar(self.app.get_data_path().parent)
        self.sidebar.connect('path-selected', self.on_sidebar_path_selected)
        self.builder.get_object('scrolled_side').add(self.sidebar)

        self.view = AppView(app)
        self.view.connect('update-title', self.on_view_update_title)
        self.builder.get_object('viewport').add(self.view.webview)

        if tray:
            self.tray_icon = Gtk.StatusIcon()
            self.tray_icon.set_from_file(self.app.get_data_path('icon-light.png').as_posix())
            self.tray_icon.set_tooltip_text('GTK HyperMD')
            self.tray_icon.connect('activate', self.on_tray_icon_activate)
            #self.tray_icon.connect('popup-menu', self.on_tray_icon_menu)
        else:
            self.tray_icon = None

        self.window.set_application(self.app)

    def ui(self, name):
        return self.builder.get_object(name)

    def show(self):
        state = self.window_state
        self.window.set_default_size(state['width'], state['height'])
        self.window.move(state['x'], state['y'])
        self.ui('paned').set_position(state['sidebar-width'])
        self.window.show_all()
        if self.ui('paned').get_position() < 10:
            self.view.grab_focus()
        else:
            self.sidebar.grab_focus()

    def hide(self):
        self.save_window_state()
        self.window.hide()

    def toggle_sidebar(self):
        if self.ui('paned').get_position() < 10:
            self.ui('paned').set_position(300)
            self.sidebar.grab_focus()
        else:
            self.ui('paned').set_position(0)
            self.view.grab_focus()
        self.save_window_state()

    def save_window_state(self):
        if not self.window.get_property('visible'): return
        state = self.window_state
        state['width'], state['height'] = self.window.get_size()
        state['x'], state['y'] = self.window.get_position()
        state['sidebar-width'] = self.ui('paned').get_position()
        if len(self.app.get_windows()) <= 1:
            self.app.save_default_window_state(state)

    def on_configure_event(self, widget, event):
        """Saves window position on moves and resizes."""

        if self.resize_timer_id is not None:
            return

        def on_timer(*args):
            self.resize_timer_id = None
            self.save_window_state()

        self.resize_timer_id = GLib.timeout_add(250, on_timer)

    def on_window_delete_event(self, widget, *data):
        # Hide to tray instead of closing
        if self.tray_icon is not None:
            self.hide()
            return True

    def on_tray_icon_activate(self, widget):
        if self.window.get_property('visible'):
            if self.window.is_active():
                self.hide()
            else:
                self.window.present()
        else:
            self.show()

    def on_menu_quit_clicked(self, widget):
        self.app.quit()

    def on_menu_sidebar_toggled(self, widget):
        self.toggle_sidebar()
        self.ui('main_menu').hide()

    def on_window_key_press_event(self, widget, event):
        key_name  = Gdk.keyval_name(event.keyval)
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        #print(event.keyval, event.state, key_name)

        if self.tray_icon is not None and key_name == 'Escape':
            self.hide()
        if self.tray_icon is not None and ctrl and key_name in ('w', 'W'):
            self.hide()
        elif ctrl and key_name in ('q', 'Q'):
            self.app.quit()
        elif ctrl and key_name in ('backslash', 'space'):
            self.toggle_sidebar()
        elif ctrl and key_name in ('KP_Add', 'equal', 'plus'):
            self.view.zoom(1.1)
        elif ctrl and key_name in ('KP_Subtract', 'minus'):
            self.view.zoom(1/1.1)
        else:
            return False
        return True

    def on_window_key_release_event(self, widget, event):
        return False

    def on_view_update_title(self, obj, title):
        self.ui('headerbar_title').set_text(title)
        self.window.set_title(title)

    def on_sidebar_path_selected(self, obj, path):
        self.view.load(path)
