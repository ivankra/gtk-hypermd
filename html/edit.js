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

class HMD {
  constructor(params) {
    this.textArea = document.getElementById("hmdtextarea");
    this.hyperMD = HyperMD.fromTextArea(this.textArea, {
      autofocus: false,
      foldGutter: false,
      hmdModeLoader: false,
      lineNumbers: false
    });
    this.hyperMD.on("change", cm => { this.onChange(); });
    this.hyperMD.setCursor(1);
    this.hyperMD.focus();
    this.bufferId = params != null ? params.bufferId : -1;
    this.bufferHash = params != null ? params.bufferHash : "";
    this.apiUri = params != null ? params.apiUri : "";
    this.apiUri = this.apiUri.replace(/\/$/, "");
    this.token = params != null ? params.token : "";
    this.sendTimer = -1;
  }

  onChange() {
    if (this.sendTimer != -1) {
      window.clearTimeout(this.sendTimer);
    }
    this.sendTimer = window.setTimeout(() => {
      this.sendUpdate();
      this.sendTimer = -1;
    }, 250);
  }

  sendUpdate() {
    fetch(this.apiUri + "/update", {
      method: "post",
      body: JSON.stringify({
        "content": this.hyperMD.getValue(),
        "bufferId": this.bufferId,
        "bufferHash": this.bufferHash,
        "token": this.token,
      })
    })
    .then(response => response.json())
    .then(response => {
      if (response.error != null) {
        // TODO: give a choice to overwrite or reload
        alert(response.error);
      } else {
        this.bufferHash = response.bufferHash;
      }
    });
  }
}

window.hmd = new HMD(window.hmdParams);
document.title = decodeURIComponent(window.location.href.split('/').pop());
