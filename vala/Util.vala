namespace GtkHyperMD {
  public class Util {
    public static string html_escape(string s) {
      return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    // Returns absolute path.
    public static string abspath(string path) {
      return File.new_for_path(path).get_path();
    }

    // Checks that path exists.
    public static bool exists(string path) {
      return File.new_for_path(path).query_exists();
    }

    // Checks that path exists and is a directory.
    public static bool is_dir(string path) {
      File file = File.new_for_path(path);
      if (!file.query_exists()) return false;
      FileType type = file.query_file_type(FileQueryInfoFlags.NONE, null);
      return type == FileType.DIRECTORY;
    }

    // Checks that subdir is a strict subdirectory of path.
    // subdir and path may or may not exist.
    public static bool is_subdir(string subdir, string path) {
      File file1 = File.new_for_path(subdir);
      File file2 = File.new_for_path(path);
      return file2.get_path().has_prefix(file1.get_path() + "/");
    }

    public static string resolve_symlink(string path) {
      try {
        File file = File.new_for_path(path);
        FileInfo info = file.query_info(
            FileAttribute.STANDARD_IS_SYMLINK + "," +
            FileAttribute.STANDARD_SYMLINK_TARGET,
            FileQueryInfoFlags.NONE);
        if (!info.get_is_symlink()) {
          return path;
        }
        File dir = file.get_parent();
        File target = dir.resolve_relative_path(info.get_symlink_target());
        return target.get_path();
      } catch (Error e) {
        return path;
      }
    }
  }
}
