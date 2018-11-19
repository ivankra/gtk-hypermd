var HyperMD = require("hypermd");
require("codemirror/mode/clike/clike");
require("codemirror/mode/htmlmixed/htmlmixed");
require('codemirror/mode/javascript/javascript');
require('codemirror/mode/markdown/markdown');
require('codemirror/mode/python/python');
require('codemirror/mode/shell/shell');
require('codemirror/mode/xml/xml');
require("codemirror/mode/yaml/yaml");

require("hypermd/powerpack/fold-math-with-katex")
require("hypermd/powerpack/hover-with-marked")

var hmdTextArea = document.getElementById("hmdtextarea")

var hmd = HyperMD.fromTextArea(hmdTextArea, {
  autofocus: false,
  foldGutter: false,
  hmdModeLoader: false,
  lineNumbers: false
})
window.hmd = hmd;

window.hmdSaveTimer = -1;
hmd.on('change', function() {
  if (window.hmdSaveTimer != -1) {
    window.clearTimeout(window.hmdSaveTimer);
  }
  if (window.hmdUnsavedTimer == -1) {
    window.hmdUnsavedTimer = window.setTimeout(function() {
      if (!document.title.endsWith('*')) {
        document.title = document.title + '*';
      }
      window.hmdUnsavedTimer = -1;
    }, 500);
  }
  window.hmdSaveTimer = window.setTimeout(
    function() {
      (fetch(window.location.href + '?api=on_change', {})
      .then(response => response.text())
      .then(text => {
        if (text.trim() == 'saved') {
          document.title = document.title.replace('*', '');
          window.clearTimeout(window.hmdUnsavedTimer);
        }
      }));
      window.hmdSaveTimer = -1;
    },
    250);
});

document.title = decodeURIComponent(window.location.href.split('/').pop());

window.hmd.setCursor(1);
window.hmd.focus();
