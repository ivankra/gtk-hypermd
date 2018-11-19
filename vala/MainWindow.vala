using GLib;
using Gee;

namespace GtkHyperMD {
  [GtkTemplate(ui = "/me/ivank/gtk-hypermd/data/MainWindow.ui")]
  public class MainWindow : Gtk.ApplicationWindow {
    // True if opened as an auxiliary new window or a window for editing
    // a specific file. One-off windows don't create tray icons and don't
    // save geometry to gsettings.
    public bool one_off;

    public WindowState window_state;
    public Sidebar sidebar;
    public WebKit.WebView webview;
    public Gtk.StatusIcon status_icon;
    public Granite.Widgets.Toast toast;

    [GtkChild] public Gtk.Paned paned;
    [GtkChild] public Gtk.Label headerbar_title;
    [GtkChild] public Gtk.MenuButton headerbar_menu;
    [GtkChild] public Gtk.Button headerbar_back;
    [GtkChild] public Gtk.Button headerbar_forward;
    [GtkChild] public Gtk.CheckButton menu_sidebar;
    [GtkChild] public Gtk.CheckButton menu_dark_theme;
    [GtkChild] public Gtk.Overlay overlay;

    public Application app {
      get { return application as Application; }
    }

    public MainWindow(Application app, bool one_off) throws GLib.Error {
      Object(application: app);

      this.one_off = one_off;

      set_title(headerbar_title.get_text());

      sidebar = new Sidebar(app.api);
      sidebar.file_selected.connect((path) => { navigate(path); });
      sidebar.show_notification.connect(show_notification);
      sidebar.create_new_requested.connect(create_new_in_dir);

      paned.add1(sidebar);

      webview = create_webview();
      webview.notify["title"].connect(webview_updated);
      webview.load_changed.connect(webview_updated);

      var viewport = new Gtk.Viewport(null, null);
      viewport.add(webview);
      var scrolled = new Gtk.ScrolledWindow(null, null);
      scrolled.add(viewport);
      paned.add2(scrolled);

      window_state = WindowState.from_settings(app.settings);
      window_state.apply(this);

      if (!one_off) {
        status_icon = new Gtk.StatusIcon.from_file(
            app.base_path + "/data/icon-light.png");
        status_icon.activate.connect(on_status_icon_activate);
      }

      var icon_file = File.new_for_path(app.base_path + "/data/icon-light.png");
      set_icon_from_file(icon_file.get_path());
      var gicon = new FileIcon(icon_file);
      var icon = new Gtk.Image.from_gicon(gicon, Gtk.IconSize.MENU);
      headerbar_menu.set_image(icon);

      if (!one_off) {
        string[] toplevel = app.settings.get_strv("toplevel");
        if (toplevel.length == 0) {
          open_with_sidebar(app.base_path + "/README.md");
        } else {
          foreach (string path in toplevel) {
            sidebar.add_toplevel(path);
          }
        }
      }
    }

    private WebKit.WebView create_webview() {
      var context = new WebKit.WebContext.ephemeral();
      context.register_uri_scheme("app", app.server.webkit_handler);
      // TODO: doesn't seem to work
      //context.get_cookie_manager().add_cookie.begin(server.auth_cookie, null,
      //  () => {});

      var webview = new WebKit.WebView.with_context(context);

      var settings = new WebKit.Settings();
      settings.enable_java = false;
                settings.enable_page_cache = false;
      settings.enable_write_console_messages_to_stdout = true;
      settings.enable_developer_extras = true;
                webview.set_settings(settings);

      return webview;
    }

    public void navigate(string path) {
      string uri = "app://app/edit" + Uri.escape_string(path, "/");
      //string uri = server.uri + "edit" + Uri.escape_string(path, "/");
      webview.load_uri(uri);
    }

    // Opens file or folder: adds directory if necessary to sidebar, then
    // locates the file in sidebar and open it in the webview.
    public void open_with_sidebar(string path) {
      string abs_path = Util.abspath(path);
      if (sidebar.find_item(abs_path) != null) {
        sidebar.select_path(abs_path);
        return;
      }

      string dir;
      if (Util.is_dir(abs_path)) {
        dir = abs_path;
      } else {
        dir = Path.get_dirname(abs_path);
      }

      if (sidebar.find_toplevel(dir) == null) {
        sidebar.add_toplevel(dir);
      }

      sidebar.select_path(abs_path);
    }

    // Shows a toast notification to user.
    public void show_notification(string text) {
      if (toast == null) {
        toast = new Granite.Widgets.Toast("");
        toast.show_all();
        overlay.add_overlay(toast);
      }
      toast.title = text;
      toast.send_notification();
    }

    private void webview_updated() {
      set_title(webview.title);
      headerbar_title.set_text(webview.title);
      headerbar_back.sensitive = webview.can_go_back();
      headerbar_forward.sensitive = webview.can_go_forward();
    }

    private void save_window_state() {
      if (visible) {
        window_state = WindowState.from_window(this);
        if (app != null && app.get_windows().length() == 1) {
          window_state.save(app.settings);
        }

        if (!one_off) {
          ArrayList<string> toplevel = sidebar.get_toplevel_paths();
          string[] toplevel_arr = toplevel.to_array();
          for (int i = 0; i < toplevel_arr.length; i++) {
            print("toplevel[%d] = ", i);
            print("%s\n", toplevel_arr[i]);
          }
          // XXX crash here
          app.settings.set_strv("toplevel", toplevel_arr);
          print("saved %d\n", toplevel_arr.length);
        }
      }
    }

    public new void hide() {
      save_window_state();
      base.hide();
    }

    public new void present() {
      window_state.apply(this);
      show_all();
      base.present();
    }

    public void toggle_sidebar() {
      menu_sidebar.set_active(!menu_sidebar.get_active());
    }

    private uint on_configure_timer_id = 0;

    [GtkCallback]
    private bool on_configure_event() {
      // Save window state on resize/move, with a small delay.
      if (on_configure_timer_id == 0) {
        on_configure_timer_id = GLib.Timeout.add(250, () => {
          on_configure_timer_id = 0;
          save_window_state();
          return false;
        });
      }
      return false;
    }

    [GtkCallback]
    private bool on_delete_event(Gtk.Widget widget, Gdk.EventAny event) {
      save_window_state();
      // Hide to tray instead of closing
      if (status_icon != null) {
        hide();
        return true;
      }
      return false;
    }

    [GtkCallback]
    private bool on_key_press_event(Gtk.Widget widget, Gdk.EventKey event) {
      bool ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
      string key = Gdk.keyval_name(event.keyval);

      if (status_icon != null &&
          (key == "Escape" || (ctrl && (key == "w" || key == "W")))) {
        hide();
      } else if (ctrl && (key == "q" || key == "Q")) {
        app.quit();
      } else if (ctrl && (key == "backslash" || key == "space")) {
        toggle_sidebar();
      } else if (ctrl && (key == "KP_Add" || key == "equal" || key == "plus")) {
        webview.set_zoom_level(webview.get_zoom_level() * 1.1);
      } else if (ctrl && (key == "KP_Subtract" || key == "minus")) {
        webview.set_zoom_level(webview.get_zoom_level() / 1.1);
      } else {
        return false;
      }
      return true;
    }

    [GtkCallback]
    private void on_menu_new_window_clicked(Gtk.Button button) {
      try {
        var window = new MainWindow(app, true);
        window.window_state = this.window_state;
        window.window_state.x += 50;
        window.window_state.y += 50;
        window.present();
      } catch (Error e) {
        show_notification(e.message);
      }
    }

    [GtkCallback]
    private void on_menu_open_file_clicked(Gtk.Button button) {
      var chooser = new Gtk.FileChooserDialog(
          "Select file to open", this, Gtk.FileChooserAction.OPEN,
          "Cancel", Gtk.ResponseType.CANCEL,
          "Open", Gtk.ResponseType.ACCEPT);
      if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        open_with_sidebar(chooser.get_filename());
      }
      chooser.destroy();
    }

    [GtkCallback]
    private void on_menu_open_folder_clicked(Gtk.Button button) {
      var chooser = new Gtk.FileChooserDialog(
          "Select folder to open", this, Gtk.FileChooserAction.SELECT_FOLDER,
          "Cancel", Gtk.ResponseType.CANCEL,
          "Open", Gtk.ResponseType.ACCEPT);
      if (chooser.run() == Gtk.ResponseType.ACCEPT) {
        open_with_sidebar(chooser.get_filename());
      }
      chooser.destroy();
    }

    [GtkCallback]
    private void on_menu_about_clicked(Gtk.Button button) {
      open_with_sidebar(app.base_path + "/README.md");
    }

    [GtkCallback]
    private void on_menu_quit_clicked(Gtk.Button button) {
      app.quit();
    }

    [GtkCallback]
    public void on_menu_sidebar_toggled(Gtk.ToggleButton button) {
      toggle_sidebar_impl();
    }

    private void toggle_sidebar_impl() {
      if (paned.get_position() < 10) {
        if (window_state.sidebar_width < 10) {
          window_state.sidebar_width = 300;
        }
        paned.set_position(window_state.sidebar_width);
        sidebar.grab_focus();
      } else {
        paned.set_position(0);
        webview.grab_focus();
      }
      save_window_state();
    }

    [GtkCallback]
    public void on_menu_dark_theme_toggled(Gtk.ToggleButton button) {
      var gtk_settings = Gtk.Settings.get_default();
      gtk_settings.gtk_application_prefer_dark_theme = menu_dark_theme.active;
      // TODO: change editor's style sheets
    }

    [GtkCallback]
    private void on_headerbar_back_clicked(Gtk.Button button) {
      webview.go_back();
    }

    [GtkCallback]
    private void on_headerbar_forward_clicked(Gtk.Button button) {
      webview.go_forward();
    }

    [GtkCallback]
    private void on_headerbar_new_clicked(Gtk.Button button) {
      string path = sidebar.get_selected_path();
      if (path == null) {
        var toplevel = sidebar.get_toplevel_paths();
        if (toplevel.size == 0) return;
        path = toplevel[0];
      }
      create_new_in_dir(path);
    }

    public void create_new_in_dir(string dir, bool folder = false) {
      string path = dir;
      if (Util.exists(path) && !Util.is_dir(path)) {
        path = Path.get_dirname(path);
      }

      for (int n = 1;; n++) {
        string basename = ("Untitled" + (n == 1 ? "" : n.to_string()) +
                           (folder ? "" : ".md"));
        if (!Util.exists(path + "/" + basename)) {
          path = path + "/" + basename;
          break;
        }
        if (n > 100) {
          return;
        }
      }

      try {
        if (folder) {
          File file = File.new_for_path(path);
          file.make_directory();
        } else {
          FileUtils.set_contents(path, "");
        }
      } catch (Error e) {
        show_notification(e.message);
        return;
      }

      sidebar.refresh();
      sidebar.select_path(path);
    }

    private void on_status_icon_activate() {
      if (visible) {
        if (is_active) {
          hide();
        } else {
          present();
        }
      } else {
        present();
      }
    }
  }

  // Persistent window parameters, particularly geometry.
  public struct WindowState {
    public int width;
    public int height;
    public int x;
    public int y;
    public int sidebar_width;
    public bool sidebar_hidden;
    public double zoom_level;

    public WindowState.from_settings(Settings settings) {
      settings.get_value("window-geometry").get(
        "(iiii)", out width, out height, out x, out y);
      sidebar_width = settings.get_int("sidebar-width");
      sidebar_hidden = settings.get_boolean("sidebar-hidden");
      zoom_level = settings.get_double("zoom-level");
    }

    public WindowState.from_window(MainWindow window) {
      this.from_settings(window.app.settings);
      window.get_size(out width, out height);
      window.get_position(out x, out y);
      if (window.paned.position < 10) {
        sidebar_hidden = true;
      } else {
        sidebar_width = window.paned.position;
      }
      zoom_level = window.webview.get_zoom_level();
    }

    public void apply(MainWindow window) {
      window.set_default_size(width, height);
      window.move(x, y);
      window.paned.position = sidebar_hidden ? 0 : sidebar_width;
      window.webview.set_zoom_level(zoom_level);
      if (window.menu_sidebar.get_active() != !sidebar_hidden) {
        window.toggle_sidebar();
      }
    }

    public void save(Settings settings) {
      var tuple = new Variant.tuple({
          new Variant.int32(width), new Variant.int32(height),
          new Variant.int32(x), new Variant.int32(y)});
      settings.set_value("window-geometry", tuple);
      settings.set_int("sidebar-width", sidebar_width);
      settings.set_boolean("sidebar-hidden", sidebar_hidden);
      settings.set_double("zoom-level", zoom_level);
    }
  }
}
