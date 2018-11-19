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
        self.buffers = app.buffers
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
        buffer = self.buffers.find_by_path(path, create=True)
        uri = 'app://app/edit' + buffer.path.as_posix()
        self.webview.load_uri(uri)

    def zoom(self, mult):
        zoom = self.webview.get_zoom_level()
        self.webview.set_zoom_level(zoom * mult)

    def grab_focus(self):
        self.webview.grab_focus()
        self.js('window.hmd.focus();')

    def on_load_changed(self, widget, event):
        #rint('on_load_changed: ', event)
        self.emit('update-back', self.webview.can_go_back())
        self.emit('update-next', self.webview.can_go_forward())

    def js(self, script, callback=None):
        """Runs javascript asynchronously. Calls callback with string representation of result."""

        def cb(obj, result, data):
            js_result = obj.run_javascript_finish(result)  # WebKit2.JavascriptResult
            js_value = js_result.get_js_value()  # JavaScriptCore.Value
            callback(js_value.to_string())

        self.webview.run_javascript(script, None, callback and cb, None)

    # Javascript-facing APIs
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
        print(uri)
        unquoted_path = urllib.parse.unquote(parsed.path)

        if parsed.netloc == 'app' and unquoted_path.startswith('/edit/'):
            # app://app/edit/<path> -- serve editor app
            filepath = unquoted_path[5:]
            if parsed.query == '':
                buffer = self.buffers.find_by_path(filepath)
                if buffer is None:
                    return 'ERROR: buffer for path %s does not exist' % str(filepath)
                tmpl = (self.app.base_path / 'dist/edit.html').open().read()
                return buffer.render_html(tmpl)

            # app://app/edit/<path>?api=<method>&... -- API calls
            elif len(params.get('api', [])) == 1:
                api = params.pop('api')[0]
                if hasattr(self, 'api_' + api):
                    fn = getattr(self, 'api_' + api)
                    args = { k: v[-1] for (k, v) in params.items() }
                    args['path'] = filepath
                    return fn(**args)

        # app://app/<path> -- serve data files
        if parsed.netloc == 'app':
            path = self.app.base_path / Path(unquoted_path).relative_to('/')
            if path.exists() and not path.is_dir():
                return Gio.File.new_for_path(path.as_posix()).read()

    def api_on_change(self, path, buffer_id=''):
        buffer = self.buffers.find_by_id(buffer_id)
        if buffer is None: buffer = self.buffers.find_by_path(path)
        if buffer is None: return
        self.js('window.hmd.getValue()', lambda text: buffer.on_change(text))
        return 'saved'
