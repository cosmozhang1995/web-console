ConsoleBox = require('./consolebox');

$(document).ready ->
  rooturl = window.location.href.match(/^([^\/^:^?^#]+)\:\/\/([^\/^:^?^#]+)(\:\d+)?/)[0]
  wsurl = "ws://" + window.location.host + "/ws"

  box = new ConsoleBox '.console-box', 
    wsurl: wsurl
    height: "50%"
    width: "100%"

  return undefined