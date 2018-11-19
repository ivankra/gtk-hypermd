using GLib;
using Gee;

// XXX moving between folders via drag & drop not possible - SourceList doesn't
// yet implement reparenting.

namespace GtkHyperMD {
  public interface SidebarItem : Granite.Widgets.SourceList.Item {
    public abstract string get_filename();
    public abstract void set_filename(string s);
    public abstract string get_path();
  }

  // Dummy item for temporarily putting inside of currently collapsed folders
  // to render them as expandale.
  public class DummyItem : SidebarItem, Granite.Widgets.SourceList.Item {
    private const string kName = "(empty)";

    public DummyItem() { Object(name: kName); }

    public string get_filename() { return kName; }
    public void set_filename(string s) {}
    public string get_path() { return ""; }
  }

  public class FileItem : SidebarItem, Granite.Widgets.SourceList.Item {
    public string filename;
    public FolderItem folder;
    public Sidebar sidebar { get { return folder.sidebar; } }

    public FileItem(string filename, FolderItem folder) {
      Object(name: filename);
      this.filename = filename;
      this.folder = folder;
      icon = sidebar.file_icon;
      editable = true;
    }

    public string get_filename() { return filename; }
    public void set_filename(string s) { filename = s; name = s; }
    public string get_path() { return folder.get_path() + "/" + filename; }

    public override void edited(string new_name) {
      sidebar.on_item_edited(this, new_name);
    }

    public override Gtk.Menu? get_context_menu() {
      var delete_menuitem = new Gtk.MenuItem.with_label("Delete");
      delete_menuitem.activate.connect(() => {
        this.sidebar.on_item_menu_delete(this.get_path());
      });

      var menu = new Gtk.Menu();
      menu.append(delete_menuitem);
      menu.show_all();
      return menu;
    }
  }

  public class FolderItem : SidebarItem,
                            Granite.Widgets.SourceList.ExpandableItem {
    public string filename;
    public FolderItem folder;
    public Sidebar sidebar;
    public string dirname;      // only at top level if folder == null

    public FolderItem(string path, FolderItem? folder, Sidebar sidebar) {
      Object(name: Path.get_basename(path));
      this.filename = Path.get_basename(path);
      if (folder == null) {
        this.dirname = Path.get_dirname(path);
      } else {
        this.dirname = null;
      }
      this.sidebar = sidebar;
      this.folder = folder;
      icon = sidebar.folder_icon;
      editable = true;
    }

    public bool is_top_level() { return folder == null; }
    public string get_filename() { return filename; }
    public void set_filename(string s) { filename = s; name = s; }

    public string get_path() {
      if (folder == null) {  // top level
        return dirname + "/" + filename;
      } else {
        return folder.get_path() + "/" + filename;
      }
    }

    public override Gtk.Menu? get_context_menu() {
      var menu = new Gtk.Menu();

      var new_file_item = new Gtk.MenuItem.with_label("New file");
      new_file_item.activate.connect(() => {
        this.sidebar.create_new_requested(this.get_path(), false);
      });
      menu.append(new_file_item);

      var new_folder_item = new Gtk.MenuItem.with_label("New folder");
      new_folder_item.activate.connect(() => {
        this.sidebar.create_new_requested(this.get_path(), true);
      });
      menu.append(new_folder_item);

      if (is_top_level()) {
        var close_item = new Gtk.MenuItem.with_label("Close");
        close_item.activate.connect(() => {
          this.sidebar.on_item_menu_close_toplevel(this.get_path());
        });
        menu.append(close_item);
      } else {
        var delete_item = new Gtk.MenuItem.with_label("Delete");
        delete_item.activate.connect(() => {
          this.sidebar.on_item_menu_delete(this.get_path());
        });
      }

      menu.show_all();
      return menu;
    }

    public override void edited(string new_name) {
      sidebar.on_item_edited(this, new_name);
    }

    public override void toggled() {
      refresh();
    }

    public void refresh() {
      if (!expanded) {
        // Add a dummy item if we have subitems to get rendered as expandable.
        // The rest of items will be added lazily if expanded.
        ArrayList<FileInfo> list = null;
        try { list = listdir(1); } catch (Error e) {}

        if (children.size != (list == null ? 0 : list.size)) {
          clear();
          if (list != null && list.size > 0) {
            add(new DummyItem());
          }
        }
      } else {
        refresh_expand();
      }
    }

    private void refresh_expand() {
      var old_items = new HashMap<string, Granite.Widgets.SourceList.Item>();
      foreach (var item in children) {
        if (item is FolderItem) {
          old_items["d" + (item as FolderItem).filename] = item;
        } else if (item is FileItem) {
          old_items["f" + (item as FileItem).filename] = item;
        }
      }

      var new_items = new ArrayList<Granite.Widgets.SourceList.Item>();
      bool modified = false;
      ArrayList<FileInfo> infos;

      try {
        infos = listdir();
      } catch (Error e) {
        sidebar.show_notification(e.message);
        return;
      }

      foreach (FileInfo info in infos) {
        bool dir = info.get_file_type() == FileType.DIRECTORY;
        string key = (dir ? "d" : "f") + info.get_name();
        if (old_items.has_key(key)) {
          new_items.add(old_items[key]);
        } else if (dir) {
          new_items.add(new FolderItem(info.get_name(), this, sidebar));
          modified = true;
        } else {
          new_items.add(new FileItem(info.get_name(), this));
          modified = true;
        }
      }
      modified |= new_items.size != old_items.size;

      if (modified) {
        clear();
        foreach (var item in new_items) {
          add(item);
        }
      }

      foreach (var item in children) {
        if (item is FolderItem) {
          (item as FolderItem).refresh();
        }
      }
    }

    private ArrayList<FileInfo> listdir(int limit = -1) throws Error {
      var list = new ArrayList<FileInfo>();
      var dir = File.new_for_path(get_path());
      //var enumerator = dir.enumerate_children("standard::*", 0);
      var enumerator = dir.enumerate_children(
          "standard::name,standard::type", 0);

      FileInfo info;
      while ((info = enumerator.next_file()) != null) {
        string name = info.get_name();
        if (name.has_prefix(".")) continue;
        if (info.get_file_type() != FileType.DIRECTORY &&
            !name.has_suffix(".md")) continue;
        list.add(info);
        if (limit >= 0 && list.size > limit) {
          break;
        }
      }

      list.sort((a, b) => {
        int d1 = (int)(a.get_file_type() == FileType.DIRECTORY);
        int d2 = (int)(b.get_file_type() == FileType.DIRECTORY);
        if (d1 != d2) return d2 - d1;
        return a.get_name().ascii_casecmp(b.get_name());
      });

      return list;
    }

    // Find item by file path, expanding subfolders if necessary.
    public SidebarItem? find_item(string abs_path, bool expand = true) {
      string cur_path = get_path();
      if (abs_path == cur_path) return this;
      if (!abs_path.has_prefix(cur_path + "/")) return null;

      if (expand) {
        refresh_expand();
      }

      foreach (var child in children) {
        SidebarItem item = child as SidebarItem;
        if (item == null) continue;

        string item_path = item.get_path();
        if (item_path == abs_path) return item;

        if (item is FolderItem && abs_path.has_prefix(item_path + "/")) {
          var folder = item as FolderItem;
          return folder.find_item(abs_path, expand);
        }
      }

      return null;
    }
  }

  public class Sidebar : Granite.Widgets.SourceList {
    public API api;
    public ThemedIcon file_icon = new ThemedIcon("text-x-generic");
    public ThemedIcon folder_icon = new ThemedIcon("folder");

    public signal void show_notification(string message);
    public signal void file_selected(string path);
    public signal void create_new_requested(string dir, bool folder);

    public Sidebar(API api) {
      this.api = api;

      item_selected.connect((widget, item) => {
        if (item is FileItem) {
          file_selected((item as FileItem).get_path());
        }
      });

      foreach (var widget in get_children()) {
        if (widget is Gtk.TreeView) {
          widget.get_style_context().add_class("sidebar");
        }
      }
    }

    // libgranite workaround: treeview doesn't get focused.
    public new void grab_focus() {
      base.grab_focus();
      foreach (var widget in get_children()) {
        if (widget is Gtk.TreeView) {
          widget.grab_focus();
        }
      }
    }

    public void refresh() {
      foreach (var item in root.children) {
        if (item is FolderItem) {
          (item as FolderItem).refresh();
        }
      }
    }

    // Add a new top level item ( if it doesn't already exists).
    public SidebarItem? add_toplevel(string path) {
      SidebarItem item = find_toplevel(path);
      if (item != null) {
        return item;
      } else if (Util.is_dir(path)) {
        var folder = new FolderItem(path, null, this);
        root.add(folder);
        folder.expand_with_parents();  // will refresh
        return folder;
      } else {
        return null;
      }
    }

    // Find item by file path, expanding and refreshing subfolders if necessary.
    public SidebarItem? find_item(string path, bool expand = true) {
      string abs_path = Util.abspath(path);
      if (!Util.exists(abs_path)) {
        return null;
      }
      foreach (var item in root.children) {
        if (item is FolderItem) {
          var res = (item as FolderItem).find_item(abs_path, expand);
          if (res != null) return res;
        }
      }
      return null;
    }

    // Returns top-level item matching given path, if any.
    public SidebarItem? find_toplevel(string path) {
      string abs_path = Util.abspath(path);
      foreach (var item in root.children) {
        var folder = item as FolderItem;
        if (folder != null && folder.get_path() == abs_path) return folder;
      }
      return null;
    }

    // Selects item with a given filepath, expanding subfolders as necessary.
    public bool select_path(string path) {
      string abs_path = Util.abspath(path);
      var item = find_item(abs_path, true);
      if (item != null) {
        selected = item;
      }
      return item != null;
    }

    public string? get_selected_path() {
      var item = selected as SidebarItem;
      return item == null ? null : item.get_path();
    }

    public ArrayList<string> get_toplevel_paths() {
      var res = new ArrayList<string>();
      foreach (var item in root.children) {
        if (item is FolderItem) {
          res.add((item as FolderItem).get_path());
        }
      }
      return res;
    }

    public void on_item_edited(Granite.Widgets.SourceList.Item gr_item,
                               string new_name) {
      SidebarItem item = gr_item as SidebarItem;
      if (item == null || new_name == item.name || new_name == "") {
        return;
      }

      string old_path = item.get_path();
      string new_path = Path.get_dirname(old_path) + "/" + new_name;

      try {
        api.move(old_path, new_path);
      } catch (Error e) {
        show_notification(e.message);
        return;
      }

      if (!new_name.contains("/")) {
        item.set_filename(new_name);
      }

      refresh();

      var new_item = find_item(new_path, true);
      if (new_item != null && (selected as SidebarItem) != new_item) {
        selected = new_item;
      }
    }

    public void on_item_menu_delete(string path) {
      try {
        api.delete(path);
      } catch (Error e) {
        show_notification(e.message);
        return;
      }
      refresh();
    }

    public void on_item_menu_close_toplevel(string path) {
      SidebarItem? folder = find_toplevel(path);
      if (folder == null) return;

      root.remove(folder);
      refresh();
    }
  }
}
