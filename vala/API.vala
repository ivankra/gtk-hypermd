using GLib;
using Gee;

// TODO:
// * create multiple buffers for same path for different windows
// * don't read file into memory until first modication
// * retire unmodified buffers when navigating to a different page in a window

namespace GtkHyperMD {
  public class Buffer {
    // Absolute path to file being edited.
    public string path;

    // Unique integer id to identify the buffer in case of renames.
    public string id;
    private static int64 id_counter = 0;

    public string text;
    public string hash;
    public string disk_hash;

    public Buffer(string path) {
      this.path = path;
      id_counter++;
      id = id_counter.to_string();
      try {
        check_disk();
      } catch (Error e) {
        print("%s\n", e.message);
      }
    }

    public bool update(string text, string prev_hash) throws Error {
      string hash = compute_hash(text);
      // TODO: this is broken and needs fixing, accept all requests for now.
      /*
      check_disk();
      if (hash == this.hash) return true;
      if (prev_hash != this.hash) return false;
      */
      this.text = text;
      this.hash = hash;
      return save();
    }

    public bool save() throws Error {
      File file = File.new_for_path(path);
      if (file.query_exists()) {
        file.delete();
      }
      var os = file.create(FileCreateFlags.REPLACE_DESTINATION);
      var dos = new DataOutputStream(os);
      dos.put_string(text);
      disk_hash = hash;
      return dos.close();
    }

    private void check_disk() throws Error {
      string prev_disk_hash = disk_hash;
      string? text = disk_read();
      if (text != null &&
          disk_hash != prev_disk_hash &&
          hash == prev_disk_hash) {
        this.text = text;
        this.hash = disk_hash;
      }
    }

    // Reads file from disk and updates disk_hash.
    // Returns null if file doesn't exist, throws exception on all other errors.
    private string? disk_read() throws Error {
      disk_hash = "";

      File file = File.new_for_path(path);
      if (!file.query_exists()) {
        return null;
      }

      FileInputStream fis = file.read();
      DataInputStream dis = new DataInputStream(fis);

      size_t len;
      string data = dis.read_upto("", 0, out len);

      disk_hash = compute_hash(data);
      return data;
    }

    private string compute_hash(string? data) {
      if (data == null) return "";
      return Checksum.compute_for_string(ChecksumType.MD5, data);
    }
  }

  /**
   *  Backend logic for the web app.
   */
  public class API {
    // Absolute path / integer id as string -> Buffer.
    public HashMap<string, Buffer> buffer_map;

    public API() {
      buffer_map = new HashMap<string, Buffer>();
    }

    public Buffer open(string path) {
      string apath = Util.abspath(path);
      if (buffer_map.has_key(apath)) {
        return buffer_map.get(apath);
      } else {
        Buffer buffer = new Buffer(apath);
        buffer_map[apath] = buffer;
        buffer_map[buffer.id] = buffer;
        return buffer;
      }
    }

    public Buffer? find_buffer_by_path(string path) {
      string apath = Util.abspath(path);
      return buffer_map.has_key(apath) ? buffer_map.get(apath) : null;
    }

    public Buffer? find_buffer_by_id(string id) {
      return buffer_map.has_key(id) ? buffer_map.get(id) : null;
    }

    public void delete(string path) throws Error {
      File file = File.new_for_path(path);
      file.delete();
    }

    // Rename file/directory and update path references in buffers.
    public void move(string old_path, string new_path) throws Error {
      string new_basename = Path.get_basename(new_path);
      if (new_basename == "" || new_basename == "." || new_basename == "..") {
        throw new IOError.INVALID_FILENAME(
            "Name \"" + new_basename + "\" is invalid");
      }

      File old_file = File.new_for_path(old_path);
      File new_file = File.new_for_path(new_path);
      string old_path_abs = old_file.get_path();
      string new_path_abs = new_file.get_path();
      old_path = old_path_abs;
      new_path = new_path_abs;
      if (old_path == new_path) return;

      if (!old_file.move(new_file, FileCopyFlags.ALL_METADATA)) {
        throw new IOError.FAILED("Failed to rename file");
      }

      var bufs = new ArrayList<Buffer>();
      foreach (var key in buffer_map.keys) {
        if (key.has_prefix("/") &&
            (key == old_path || Util.is_subdir(old_path, key))) {
          bufs.add(buffer_map[key]);
        }
      }

      foreach (var buffer in bufs) {
        string buf_path = buffer.path;
        if (buffer.path == old_path) {
          buffer.path = new_path;
        } else if (buffer.path.has_prefix(old_path + "/")) {
          buffer.path = new_path + buffer.path.substring(old_path.length);
        } else {
          continue;
        }

        if (buffer_map.has_key(buf_path)) {
          buffer_map.unset(buf_path);
        }
        buffer_map[buffer.path] = buffer;
      }

      // TODO: signal all sidebars to refresh()
    }
  }
}
