import html
from gi.repository import GLib, GObject
from pathlib import Path


class RenameOp(GObject.GObject):
    def __init__(self, old_path: Path, new_path: Path):
        super().__init__()
        self.old_path = old_path
        self.new_path = new_path

    def __str__(self):
        return '<RenameOp: %s -> %s>' % (self.old_path, self.new_path)

    def apply(self, path: Path) -> Path:
        if path == self.old_path:
            return self.new_path

        try:
            res = self.new_path / path.relative_to(self.old_path)
            return res
        except ValueError:
            return path


class Buffer(object):
    """Keeps track of editing state of a single file."""

    def __init__(self, path: Path, id: str):
        self.path = self.normalize_path(path)
        self.id = id
        #self.buffer = None  # text data if modified and unsaved yet

    @staticmethod
    def normalize_path(path: Path) -> Path:
        return Path(path).absolute()

    def on_rename(self, rename_op: RenameOp):
        self.path = rename_op.apply(self.path)

    def on_change(self, text: str):
        if len(text.strip()) == 0: return
        if not self.path.name.endswith('.md'): return
        open(self.path, 'w').write(text)
        #self.buffer = None

    def render_html(self, html_template: str):
        if self.path.exists() and self.path.is_dir():
            return '%s is a directory' % str(self.path)
        if self.path.exists():
            data = self.path.open().read()
        else:
            data = '# %s\n\n' % self.path.name
        res = html_template.replace('</textarea>',
            html.escape(data) + '</textarea>' +
            '<script>window.hmdBufferId="%s";</script>' % self.id)
        return res

    def __str__(self):
        return '<Buffer id=%s path=%s>' % (self.id, self.path)


class Buffers(GObject.GObject):
    __gsignals__ = {
        'on-rename': (GObject.SIGNAL_RUN_FIRST, None, (RenameOp,))
    }

    def __init__(self):
        super().__init__()
        self._path_map = {}
        self._id_map = {}
        self._id_counter = 0

    def find_by_path(self, path: Path, create: bool = False):
        """Returns an open buffer for a given path, creating if needed."""
        path = Buffer.normalize_path(path)
        if path not in self._path_map and create:
            self._id_counter += 1
            session = Buffer(path, str(self._id_counter))
            self._path_map[path] = session
            self._id_map[session.id] = session
        return self._path_map.get(path, None)

    def find_by_id(self, id: str):
        return self._id_map.get(id, None)

    def rename(self, rename_op: RenameOp):
        """Renames file/folder, updates buffers and invokes callbacks."""

        if rename_op.old_path == rename_op.new_path: return
        if not rename_op.old_path.exists():
            raise Exception('RenameOp.old_path="%s" does not exist' % rename_op.old_path)

        print('Buffers.rename(%s)' % rename_op)
        rename_op.old_path.rename(rename_op.new_path)

        self._path_map.clear()
        for buf in self._id_map.values():
            buf.on_rename(rename_op)
            self._path_map[buf.path] = buf

        self.emit('on-rename', rename_op)
