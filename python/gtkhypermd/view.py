import logging
import html
import urllib
import urllib.parse

from gi.repository import GLib, GObject, Gio, Gtk, WebKit2
from pathlib import Path

WEBKIT_SETTINGS = {
    'enable-accelerated-2d-canvas': True,
    'enable-developer-extras': True,
    'enable-html5-local-storage': False,
    'enable-java': False,
    'enable-page-cache': False,
    'enable-webgl': True,
    'enable-write-console-messages-to-stdout': True,
}


class AppView(GObject.GObject):
    __gsignals__ = {
        'update-title': (GObject.SIGNAL_RUN_LAST, None, (str,)),  # title
        'update-back': (GObject.SIGNAL_RUN_LAST, None, (bool,)),  # enabled
        'update-next': (GObject.SIGNAL_RUN_LAST, None, (bool,)),  # enabled
    }

    def __init__(self, app):
        GObject.GObject.__init__(self)
        self.app = app
        self.webview = self.create_webview()

    def create_webview(self):
        context = WebKit2.WebContext.new_ephemeral()
        context.register_uri_scheme('app', self.open_app_uri)
        context.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)

        webview = WebKit2.WebView.new_with_context(context)
        for k, v in WEBKIT_SETTINGS.items():
            webview.get_settings().set_property(k, v)

        webview.connect('load-changed', self.on_load_changed)
        webview.connect('notify::title',
            lambda w, s: self.emit('update-title', self.webview.get_title()))
        return webview

    def load(self, path):
        path = Path(path)
        self.webview.load_uri('app://edit' + path.resolve().absolute().as_posix())

    def zoom(self, mult):
        zoom = self.webview.get_zoom_level()
        self.webview.set_zoom_level(zoom * mult)

    def grab_focus(self):
        self.webview.grab_focus()
        self.js('window.hmd.focus();')

    def on_load_changed(self, widget, event):
        #print('on_load_changed: ', event)
        pass

    def js(self, script, callback=None):
        """Runs javascript asynchronously. Calls callback with string representation of result."""

        def cb(obj, result, data):
            js_result = obj.run_javascript_finish(result)  # WebKit2.JavascriptResult
            js_value = js_result.get_js_value()  # JavaScriptCore.Value
            callback(js_value.to_string())

        self.webview.run_javascript(script, None, callback and cb, None)

    # Javascript-facing APIs:
    #   * app://data/path - serve file from data directory
    #   * app://edit/path - serve edit.html to edit specified absolute path on host
    #   * app://edit/path?api=name&arg=... - call self.api_<name>()
    #
    # TODO: use a proper RPC library, json-rpc/zeromq,...

    def open_app_uri(self, request):
        uri = request.get_uri()
        logging.info('Serving: %s' % str(uri))
        data = self.open_app_uri2(uri)
        if data is None:
            data = b''
        if type(data) is str:
            data = data.encode('utf-8')
        if type(data) is bytes:
            data = Gio.MemoryInputStream.new_from_data(data)
        request.finish(data, -1, 'text/html; charset=utf-8')

    def open_app_uri2(self, uri):
        parsed = urllib.parse.urlsplit(uri)
        params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        print(uri) #, parsed, params)
        unquoted_path = urllib.parse.unquote(parsed.path)

        # app://data/
        if parsed.netloc == 'data':
            path = self.app.get_data_path(unquoted_path)
            if path.exists() and not path.is_dir():
                return Gio.File.new_for_path(path.as_posix()).read()

        # app://edit/<path>
        if parsed.netloc == 'edit' and parsed.query == '':
            path = Path(unquoted_path)
            if path.exists() and not path.is_dir():
                data = path.open().read()
                data = (self.app.get_data_path('dist/edit.html').open().read()
                        .replace('</textarea>', html.escape(data) + '</textarea>')
                        .encode('utf-8'))
                return data

        # app://edit/<path>?api=<method>&...
        if parsed.netloc == 'edit' and len(params.get('api', [])) == 1:
            api = params.pop('api')[0]
            if hasattr(self, 'api_' + api):
                fn = getattr(self, 'api_' + api)
                args = { k: v[-1] for (k, v) in params.items() }
                if 'path' not in args:
                    args['path'] = unquoted_path
                return fn(**args)

    def api_on_change(self, path):
        self.js('window.hmd.getValue()', lambda text: self.do_save(path, text))
        # TODO: call back into js, pass errors
        return 'saved'

    def do_save(self, path, text):
        if len(text.strip()) == 0: return
        if not path.endswith('.md'): return
        open(path, 'w').write(text)
