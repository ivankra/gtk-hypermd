using GLib;
using Gee;

namespace GtkHyperMD {
  /**
   *  Handles HTTP requests from the web application coming either directly
   *  from WebKit.WebView via custom URI handler or over HTTP for POST requests.
   */
  public class Server {
    public Application app;
    public API api;

    // HTTP server
    public Soup.Server soup_server;
    public Soup.Cookie auth_cookie;
    public uint port;
    public string uri;

    public Server(Application app, API api) {
      this.app = app;
      this.api = api;

      auth_cookie = new Soup.Cookie("gtk-hypermd", Uuid.string_random(),
                                    "127.0.0.1", "/", -1);

      soup_server = new Soup.Server("server_header", app.application_id);
      soup_server.add_handler("/", soup_handler);
      try {
        soup_server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
      } catch (Error e) {
        print("Error starting up HTTP server: %s\n", e.message);
      }

      assert(soup_server.get_uris().length() >= 1);
      port = soup_server.get_uris().last().data.get_port();
      uri = "http://127.0.0.1:" + port.to_string() + "/";

      print("Server listening on %sedit%s/README.md?token=%s\n",
            uri, app.base_path, auth_cookie.get_value());
    }

    // Handles app://app/ URIs coming internally from WebKit.WebView.
    // Unfortunately these don't seem to support POST, so POST requests
    // always go over HTTP (Soup.Server).
    public void webkit_handler(WebKit.URISchemeRequest request) {
      print("%s\n", request.get_path());
      Response response = serve(request.get_path(), empty_params);
      request.finish(response.read(), -1, response.content_type);
    }

    private Map<string, string> empty_params = new HashMap<string, string>();

    // Handles requests received via HTTP by Soup.Server.
    void soup_handler(Soup.Server server, Soup.Message msg, string path,
                      GLib.HashTable? query,
                      Soup.ClientContext client) {
      print("%s\n", path);
      //msg.request_headers.foreach((k, v) => { print("  %s: %s\n", k, v); });
      //if (!soup_authenticate(msg, query)) return;

      // Map with all URI and POST paramaters.
      HashMap<string, string> params = new HashMap<string, string>();
      if (query != null) {
        query.foreach((k, v) => { params[(string)k] = (string)v; });
      }

      Response response = null;

      // Parse json and extract first-level string fields into params.
      try {
        string post_body = (string)msg.request_body.flatten().data;
        Json.Node root = null;

        if (post_body.length > 0) {
          var parser = new Json.Parser();
          parser.load_from_data(post_body);
          root = parser.get_root();
        }

        if (root != null) {
          var obj = root.get_object();
          obj.foreach_member((obj, name, node) => {
            string? value = node.get_string();
            if (value != null) {
              params[name] = value;
            }
          });
        }
      } catch (Error e) {
        response = new Response.err("JSON parsing error: " + e.message);
      }

      //foreach (var k in params.keys) print("params[%s] = \"%s\"\n", k, params[k]);

      if (!authenticate(msg, params)) {
        response = new Response.err("Not authenticated");
      }

      if (response == null) {
        response = serve(path, params);
      }

      msg.status_code = response.code;
      msg.response_headers.set_content_type(response.content_type, null);
      msg.response_headers.append("Access-Control-Allow-Origin", "app://app");

      if (response.stream == null) {
        msg.response_body.append_take(response.text.data);
      } else {
        try {
          var bytes = response.stream.read_bytes(10 << 20);
          msg.response_body.append_take(bytes.get_data());
        } catch (Error e) {
          print("Error reading Response.stream: %s\n", e.message);
          msg.status_code = 500;
        }
      }
    }

    // Authenticate via cookie or `token` URI or POST parameter.
    bool authenticate(Soup.Message msg, Map<string, string> params) {
      // Authenticate via cookie.
        foreach (var cookie in Soup.cookies_from_request(msg)) {
        if (cookie.name == auth_cookie.get_name() &&
            cookie.value == auth_cookie.get_value()) {
          return true;
        }
      }

      // Authenticate via URI/POST parameter and set cookie.
      if (params.has_key("token") &&
          params["token"] == auth_cookie.get_value()) {
        var list = new SList<Soup.Cookie>();
        list.append(auth_cookie);
        Soup.cookies_to_response(list, msg);
        return true;
      }

      return false;
    }

    // Common handler for webkit and soup server.
    public Response serve(string raw_path, Map<string, string> params) {
      string? path = Uri.unescape_string(raw_path, "/");
      if (path == null) {
        return new Response.err("Uri.unescape_string failed for: " + path);
      }

      if (path.has_prefix("/edit/")) {
        return serve_edit(path.substring(5));
      }

      if (path == "/api/update") {
        return serve_update(params);
      }

      // Serve a file from application's base directory.
      File file = File.new_for_path(app.base_path + path);
      if (!file.get_path().has_prefix(app.base_path + "/") ||
          !file.query_exists()) {
        return new Response.err("Can't find " + path);
      } else {
        return new Response.from_file(file);
      }
    }

    // Serve /edit/<path> pages: edit.html app with prefilled textarea and
    // parameters for HMD object.
    public Response serve_edit(string filepath) {
      var buf = api.open(filepath);

      string tmpl_path = app.base_path + "/dist/edit.html";
      string tmpl = null;
      try {
        if (!FileUtils.get_contents(tmpl_path, out tmpl)) {
          tmpl = null;
        }
      } catch (Error e) {
        tmpl = null;
      }
      if (tmpl == null) {
        return new Response.err("Can't read " + tmpl_path);
      }

      string text = tmpl.replace(
          "</textarea>",
          (buf.text == null ? "" : Util.html_escape(buf.text)) +
          "</textarea>\n" +
          "<script>\n" +
          "window.hmdParams = {\n" +
          "  \"bufferId\": \"" + buf.id + "\",\n" +
          "  \"bufferHash\": \"" + buf.hash + "\",\n" +
          "  \"apiUri\": \"" + this.uri + "api/\",\n" +
          "  \"token\": \"" + auth_cookie.value + "\",\n" +
          "};\n" +
          "document.cookie = '" + auth_cookie.name + "=" +
          auth_cookie.value + "; expires=Fri, 31 Dec 9999 23:59:59 UTC; path=/';" +
          "</script>\n");

      return new Response.from_string(text, "text/html; charset=utf-8");
    }

    // Process /api/update calls.
    public Response serve_update(Map<string, string> params) {
      if (!params.has_key("content") || !params.has_key("bufferId") ||
          !params.has_key("bufferHash")) {
        return new Response.err("Missing required parameters");
      }

      Buffer? buffer = api.find_buffer_by_id(params["bufferId"]);
      if (buffer == null) {
        return new Response.err("Unknown buffer id: " + params["bufferId"]);
      }

      bool ok = false;
      try {
        ok = buffer.update(params["content"], params["bufferHash"]);
      } catch (Error e) {
        print("%s\n", e.message);
        ok = false;
      }

      if (ok) {
        return new Response.from_string(
            "{\"bufferHash\": \"%s\"}\n".printf(buffer.hash));
      } else {
        return new Response.from_string(
            "{\"error\": \"File has been modified\"}\n");
      }
    }
  }

  // HTTP response to server: status code, content type and content:
  // either an InputStream for a disk file or text string,
  public class Response {
    public uint code = 200;
    public string content_type = "text/plain";
    public InputStream stream = null;
    public string text = "";

    public Response.err(string message, int code = 500) {
      this.text = "Error: " + message + "\n";
      this.code = code;
    }

    public Response.from_string(string text, string? content_type = null) {
      this.text = text;
      if (content_type != null) {
        this.content_type = content_type;
      }
    }

    public Response.from_file(File file) {
      stream = null;

      if (!file.query_exists()) {
        code = 404;
        text = "Not found";
        return;
      }

      try {
        stream = file.read();
      } catch (Error error) {
        code = 500;
        text = error.message;
        return;
      }

      string path = file.get_path();
      if (path.has_suffix(".css")) {
        content_type = "text/css";
      } else if (path.has_suffix(".js")) {
        content_type = "application/javascript";
      } else if (path.has_suffix(".png")) {
        content_type = "image/png";
      } else if (path.has_suffix(".gif")) {
        content_type = "image/gif";
      } else {
        content_type = "application/octet-stream";
      }
    }

    public InputStream read() {
      if (stream != null) {
        return stream;
      } else {
        return new MemoryInputStream.from_data(text.data);
      }
    }
  }
}
