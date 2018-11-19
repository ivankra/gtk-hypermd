using GLib;

namespace GtkHyperMD {
  public class Application : Gtk.Application {
    // Absolute canonical path to repository root or installation directory.
    // Without trailing slash.
    public string base_path;

    // Command line options.
    // TODO: on_command_line called too late after on_activated
    public static bool option_tray_mode = false;
    public static bool option_debug = true;

    public GLib.Settings settings;
    public API api;
    public Server server;

    construct {
      application_id = "me.ivank.gtk-hypermd";
      flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
    }

    public Application(string[] args) {
      Unix.signal_add(2, on_sigint, Priority.DEFAULT);   // SIGINT
      Unix.signal_add(15, on_sigint, Priority.DEFAULT);  // SIGTERM
      command_line.connect(on_command_line);
      activate.connect(on_activated);
      startup.connect(on_activated);

      init_paths(args);
      init_settings();

      api = new API();
      server = new Server(this, api);
    }

    // Locate application's base path.
    private void init_paths(string[] args) {
      string[] dirs = {
          args[0], Util.resolve_symlink(args[0]), "/usr/share/gtk-hypermd",
      };

      foreach (var dir in dirs) {
        if (dir == null || dir == "") continue;

        var file = File.new_for_path(dir);
        while (file != null &&
               !file.get_child("dist/edit.html").query_exists()) {
          file = file.get_parent();
        }

        if (file != null) {
          base_path = file.get_path();
          break;
        }
      }

      if (base_path == null) {
        print("Error: can't find application's data directory!\n");
        print("Reinstall app or make sure you've compiled resource files.\n");
        return;
      }
    }

    // Init GLib.Settings using custom schema from $base_path/data.
    private void init_settings() {
      try {
        var def_source = GLib.SettingsSchemaSource.get_default();
        var source = new GLib.SettingsSchemaSource.from_directory(
            base_path + "/data", def_source, false);

        GLib.SettingsSchema schema = source.lookup(application_id, false);
        if (source.lookup == null) {
          print("SettingsSchemaSource.lookup failed\n");
          return;
        }

        settings = new GLib.Settings.full(schema, null, null);
      } catch (GLib.Error e) {
        print("Failed to create GLib.SettingsSchema: %s\n", e.message);
        return;
      }
    }

    public int on_command_line(ApplicationCommandLine command_line) {
      print("on_command_line\n");

          const GLib.OptionEntry[] entries = {
                // long, short, flags, arg, arg_data, description, arg_description
                { "tray", 't', 0, OptionArg.NONE, out option_tray_mode,
                  "Tray mode", null },
          };

      var context = new GLib.OptionContext("");
      context.add_main_entries(entries, null);
      context.set_help_enabled(true);
      context.add_group(Gtk.get_option_group(false));

      string[] args = command_line.get_arguments();
      try {
        context.parse_strv(ref args);
      } catch (OptionError e) {
        print(e.message + "\n");
        return 1;
      }

      print("args: %d\n", args.length);

      // TODO:
      on_activated();

      return 0;
    }

    public bool on_sigint() {
      quit();
      return true;
    }

    public void on_activated() {
      print("on_activated\n");

      MainWindow window = get_last_window();
      if (window == null) {
        try {
          window = new MainWindow(this, false);
          window.present();
        } catch (GLib.Error e) {
          print("Couldn't create main window: %s\n", e.message);
          quit();
        }
      } else {
        // Activated from user starting another instance of the app.
        window.present();
      }
    }

    public MainWindow? get_last_window() {
      unowned List<weak Gtk.Window> windows = get_windows();
      if (windows.length() == 0) {
        return null;
      } else {
        return windows.last().data as MainWindow;
      }
    }
  }

  public static int main(string[] args) {
    return new GtkHyperMD.Application(args).run(args);
  }
}
