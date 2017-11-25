var expressWs = require('express-ws');
var util = require('util');
var pty = require('node-pty');

function WebConsole (app, config) {
  config = config || {};
  config.wspath = config.wspath || "/ws";

  var wscmd_prefix = "\x1B\x1B\x1B\x1B";

  if (!app.ws) expressWs(app);

  app.ws(config.wspath, function(ws, req) {
    util.inspect(ws);

    var ptyProcess = undefined;

    function establish(width, height) {
      release();
      ptyProcess = pty.spawn("bash", [], {
        name: 'xterm-color',
        cols: width,
        rows: height,
        cwd: process.env.HOME,
        env: process.env
      });
      ptyProcess.on('data', function(data) {
        ws.send(data);
      });
    }
    function release() {
      if (ptyProcess) {
        ptyProcess.kill();
        ptyProcess = undefined;
      }
    }

    ws.on('message', function(msg) {
      if (msg.slice(0, wscmd_prefix.length) == wscmd_prefix) {
        msg = msg.slice(wscmd_prefix.length);
        var match;
        if (match = msg.match(/establish\s(\d+)\s(\d+)/)) {
          establish(parseInt(match[1]), parseInt(match[2]));
          ws.send(wscmd_prefix + "ack_establish");
        } else if (match = msg.match(/resize\s(\d+)\s(\d+)/)) {
          if (ptyProcess) ptyProcess.resize(parseInt(match[1]), parseInt(match[2]));
          ws.send(wscmd_prefix + "ack_resize");
        } else if (msg == "release") {
          release();
          ws.send(wscmd_prefix + "ack_release");
        } else if (msg == "sync") {
          ws.send(wscmd_prefix + "ack_sync")
        }
      } else {
        var match = msg.match(/\\x(\d+)/);
        if (match) {
          msg = new Buffer(1);
          msg[0] = parseInt(match[1]);
        }
        ptyProcess.write(msg);
      }
    });
    ws.on("close", (code, reason) => {
      release();
      console.log("ws close");
    });
  });
}

module.exports = WebConsole;