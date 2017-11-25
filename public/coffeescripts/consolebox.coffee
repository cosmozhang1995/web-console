medias = require('./media_base64')

ControlSignal = (lead, char, nums) ->
  this.lead = lead
  this.char = char
  this.nums = nums || []
  this.toString = ->
    lead_hex = this.lead.charCodeAt().toString(16)
    (lead_hex = "0" + lead_hex) while lead_hex.length < 2
    lead_hex = "\\x" + lead_hex
    str = lead_hex
    if this.char
      str += "["
      if this.nums.length then str += this.nums.join(";")
      str += this.char
    return str
  return this
ControlSignal.makeRegExp = () ->
  return /(\r|\n|\x07|\x08|\x1B)(\[([\d\;]*)([a-zA-Z]))?/g
ControlSignal.fromMatch = (match) ->
  lead = match[1]
  nums = match[3]
  char = match[4]
  nums = (if nums then nums.split(';') else [])
  nums = (parseInt(n) for n in nums)
  return new ControlSignal(lead, char, nums)
ControlSignal.parseSentence = (sentence) ->
  reg = ControlSignal.makeRegExp()
  matches = []
  while match = reg.exec(sentence)
    matches.push(match)
  parsed = []
  if matches.length == 0
    parsed.push(sentence)
  else
    if matches[0].index > 0
      parsed.push(sentence.slice(0, matches[0].index))
    for i in [0...matches.length]
      match = matches[i]
      parsed.push(ControlSignal.fromMatch(match))
      nextstart = match.index + match[0].length
      nextmatch = matches[i+1]
      if nextstart < sentence.length
        if nextmatch
          if nextstart < nextmatch.index
            parsed.push(sentence.slice(nextstart, nextmatch.index))
        else
          parsed.push(sentence.slice(nextstart))
  return parsed

CSSProp = (val, unit) ->
  this.val = val || 0
  this.unit = unit || ""
  return this
CSSProp.prototype.valueOf = ->
  return this.val
CSSProp.prototype.toString = ->
  return this.val + this.unit
CSSProp.parse = (propstr) ->
  propstr = "" + propstr
  match = propstr.match(/(\d+(\.\d+)?)([a-zA-Z]*)/)
  if match
    val = if match[2] then parseFloat(match[1]) else parseInt(match[1])
    unit = match[3] || ""
    return new CSSProp(val, unit)
  else
    return new CSSProp()

TextProp = (ctrl, fgcolor, bgcolor) ->
  ctrl = ctrl || {}
  this.ctrl = {}
  this.ctrl.clear = ctrl.clear || false
  this.ctrl.highlight = ctrl.highlight || false
  this.ctrl.underline = ctrl.underline || false
  this.ctrl.blink = ctrl.blink || false
  this.ctrl.inverse = ctrl.inverse || false
  this.ctrl.invisible = ctrl.invisible || false
  this.fgcolor = fgcolor || 0
  this.bgcolor = bgcolor || 0
  return this

StyledChar = (char, prop) ->
  this.char = char || "\x00"
  this.prop = prop || (new TextProp())
  return this
StyledChar.prototype.toString = ->
  return this.char

StyledText = (text, prop) ->
  emptyProp = new TextProp()
  this.text = text || ""
  Object.defineProperty(this, 'length', {
    get: -> this.text.length
  })
  if prop instanceof Array
    this.prop = prop
  else if prop instanceof TextProp
    this.prop = (prop for i in [0...this.length])
  else
    this.prop = (emptyProp for i in [0...this.length])
  return this
StyledText.prototype.concat = () ->
  texts = []
  props = []
  for item in arguments
    if item instanceof StyledText
      texts = texts.concat(item.text)
      props = props.concat(item.prop)
    else if item instanceof StyledChar
      texts = texts.concat(item.char)
      props.push(item.prop)
  new_text = String.prototype.concat.apply(this.text, texts)
  new_prop = Array.prototype.concat.apply(this.prop, props)
  return new StyledText(new_text, new_prop)
StyledText.prototype.slice = (start, end) ->
  new_text = this.text.slice(start, end)
  new_prop = this.prop.slice(start, end)
  return new StyledText(new_text, new_prop)
StyledText.prototype.split = (token) ->
  indexes = []
  nextidx = 0
  tlen = token.length
  while (idx = this.text.indexOf(token, nextidx)) >= 0
    indexes.push(idx)
    nextidx = idx + tlen
    if nextidx >= this.text.length then break
  if indexes.length == 0
    return [new StyledText(this.text, this.prop)]
  else
    idx = indexes[0]
    new_text = this.text.slice(0, idx)
    new_prop = this.prop.slice(0, idx)
    splitted = [new StyledText(new_text, new_prop)]
    for i in [0...indexes.length]
      idx = indexes[i]
      nextidx = indexes[i+1]
      new_text = this.text.slice(idx + tlen, nextidx)
      new_prop = this.prop.slice(idx + tlen, nextidx)
      splitted.push(new StyledText(new_text, new_prop))
    return splitted
StyledText.prototype.at = (idx) ->
  new StyledChar(this.text[idx], this.prop[idx])
StyledText.prototype.toString = -> this.text

ConsoleBox = (selector, config) ->
  wscmd_prefix = "\x1B\x1B\x1B\x1B"

  # fill default configs
  config = config || {}
  config.tabwidth = config.tabwidth || 8
  config.width = config.width || "100%"
  config.height = config.height || "100%"
  config.padding = config.padding || "10px"
  config.fontsize = config.fontsize || "inherit"
  config.fontfamily = config.fontfamily || "Courier"
  config.cursorcolor = config.cursorcolor || "#999"
  config.lineheight = config.lineheight || "1.5"
  config.fgcolor = config.fgcolor || "#eee"
  config.bgcolor = config.bgcolor || "#001"
  config.colorscheme = config.colorscheme || ["#000","#f00","#0f0","#ff0","#00f","#f0f","#0ff","#fff"]
  config.initcmds = config.initcmds || ["source ~/.bash_profile"]
  config.blinkinterval = 500

  el = $(selector) # the root element
  ws = undefined # the websocket

  elcss = {}
  Object.defineProperty elcss, 'width', 
    get: -> CSSProp.parse(el.css('width'))
  Object.defineProperty elcss, 'height', 
    get: -> CSSProp.parse(el.css('height'))
  Object.defineProperty elcss, 'fontsize', 
    get: -> CSSProp.parse(el.css('font-size'))
  Object.defineProperty elcss, 'padding', 
    get: -> CSSProp.parse(el.css('padding'))
  Object.defineProperty elcss, 'lineheight', 
    get: -> CSSProp.parse(el.css('line-height'))

  wsready = -> (ws && ws.readyState == 1)

  initialized = false

  # construct a cursor
  cursorInnerEl = $('<span class="cursor"></span>').css
    backgroundColor: "transparent"
    borderWidth: "1px"
    borderStyle: "solid"
    borderColor: "transparent"
    height: elcss.fontsize.toString()
    width: new CSSProp(elcss.fontsize.val / 2, elcss.fontsize.unit).toString()
    display: "inline-block"
    content: " "
  cursorEl = $('<span class="cursor-wrapper"></span>').css
    width: "0"
    height: elcss.fontsize.toString()
    display: "inline-block"
  cursorEl.append(cursorInnerEl)

  # construct a content-row
  makeContentRow = ->
    $('<div class="content-row"></div>').css
      zIndex: 10
      minHeight: elcss.lineheight

  # main styles
  el.css
    width: config.width
    height: config.height
    padding: config.padding
    boxSizing: "border-box"
    overflowY: "scroll"
    overflowX: "hidden"
    fontSize: config.fontsize
    fontFamily: config.fontfamily
    lineHeight: config.lineheight
    color: config.fgcolor
    backgroundColor: config.bgcolor
    outline: "none"
    cursor: "text"

  # fill out basic structure
  el.children().remove()
  emptyBoxEl = $('<div></div>')
    .css('height', '0')
    .css('overflow', 'hidden')
  beepAudio = $('<audio></audio>')
    .attr('src', medias.beep_wav)
    .attr('autostart', "false")
  emptyBoxEl.append(beepAudio)
  beepAudio = beepAudio[0]
  el.append(emptyBoxEl)
  fakeinput = $('<input class="fake-input"/>').css
    width: "0"
    height: "0"
    border: "none"
    padding: "0"
    margin: "0"
  currrow = makeContentRow()
  currrow.append(fakeinput)
  currrow.append(cursorEl.detach())
  contentEl = $('<div class="content"></div>').css
    overflow: "hidden"
    display: "block"
    height: "auto"
  contentEl.append(currrow)
  el.append(contentEl)

  # blinking
  blinkstate = false
  updateBlinkState = ->
    if el.is(":focus")
      if blinkstate
        cursorInnerEl.css
          backgroundColor: config.cursorcolor
          borderColor: config.cursorcolor
        el.find('.blink-text').css
          opacity: 1
      else
        cursorInnerEl.css
          backgroundColor: "transparent"
          borderColor: config.cursorcolor
        el.find('.blink-text').css
          opacity: 0
    else
      cursorInnerEl.css
        backgroundColor: "transparent"
        borderColor: "transparent"
      el.find('.blink-text').css
        opacity: 1
  blinktimer = setInterval ->
    blinkstate = not blinkstate
    updateBlinkState()
  , config.blinkinterval

  # the text and cursor in current row
  currtext = new StyledText()
  currcpos = 0
  currcprp = new TextProp()
  currcmod = [false, false, false, false, false] # Input mode (SM/RM)

  # # cursor blinking
  # cursorTimer = -1
  # cursorState = false

  # window size in text width
  window_width = 1000
  window_height = 1000
  measureEl = $('<div></div>')
    .css('height', 'auto')
    .css('word-wrap', 'normal')
    .css('word-break', 'break-all')
  measureWrapperEl = $('<div></div>')
    .css('height', '0px')
    .css('overflow', 'hidden')
    .append(measureEl)
  el.prepend(measureWrapperEl)
  onWindowResize = ->
    txt = "x"
    measureEl.text(txt)
    lh = measureEl.height()
    while measureEl.height() == lh
      txt += "x"
      measureEl.text(txt)
    window.measureEl = measureEl
    window_width = txt.length - 1
    window_height = parseInt(contentEl.height() / lh)
    if wsready() then ws.send(wscmd_prefix + "resize " + window_width + " " + window_height)
  onWindowResize()

  # beep
  beep = ->
    beepAudio.play()

  parse_fgcolor = (code) -> config.colorscheme[code-30]
  parse_bgcolor = (code) -> config.colorscheme[code-40]

  text2html = (text) ->
    prop = text.prop
    text = text.text
    cp = prop[0]
    proparr = [{index: 0, prop: cp}]
    for i in [0...prop.length]
      p = prop[i]
      unless p.code == cp.code and p.fgcolor == cp.fgcolor and p.bgcolor == cp.bgcolor
        proparr.push
          index: i
          prop: p
    console.log("[text2html]", text, proparr)
    retspan = $('<span></span>')
    for i in [0...proparr.length]
      p = proparr[i]
      nextp = proparr[i+1]
      idx = p.index
      p = p.prop
      nextidx = if nextp then nextp.index else undefined
      t = text.slice(idx, nextidx)
      t = t.replace(/\x20/g, "&nbsp;")
      t = t.replace(/\n/g, "<br/>")
      span = $('<span></span>').html(t)
      fgcolor = if p.fgcolor == undefined then config.fgcolor else parse_fgcolor(p.fgcolor)
      bgcolor = if p.bgcolor == undefined then config.bgcolor else parse_fgcolor(p.bgcolor)
      if p.ctrl.clear
        fgcolor = config.fgcolor
        bgcolor = config.bgcolor
      else
        if p.ctrl.highlight
          # Highlighting
          span.css('font-weight', 'bold')
        if p.ctrl.underline
          # Underline
          span.css('text-decoration', 'underline')
        if p.ctrl.blink
          # Blink
          span.addClass('blink-text')
        if p.ctrl.inverse
          # Inverse color
          tmpcolor = fgcolor
          fgcolor = bgcolor
          bgcolor = tmpcolor
        if p.ctrl.invisible
          # Invisible
          fgcolor = "transparent"
          bgcolor = "transparent"
      span.css('color', fgcolor)
      span.css('background-color', bgcolor)
      retspan.append(span)
    return retspan

  # cursorBlinkBegin = ->
  #   clearInterval(cursorTimer)
  #   cursorTimer = -1
  #   cursorTimer = setInterval ->
  #     updateCursorState()
  #   , 500
  # cursorBlinkReset = ->
  #   clearInterval(cursorTimer)
  #   cursorTimer = -1
  #   updateCursorState(true)
  # cursorBlinkEnd = ->
  #   clearInterval cursorTimer
  #   cursorTimer = -1
  #   updateCursorState(false)
  # cursorBlinkBegin()

  scrollToBottom = ->
    el.scrollTop(contentEl.height())

  interpretColor = (code) ->
    if code >= 30 and code <= 37
      return config.colorscheme[code - 30]
    else if code >= 40 and code <= 47
      return config.colorscheme[code - 40]

  # updateCursorState = (state) ->
  #   if typeof state != "boolean" then state = !cursorState
  #   cursorState = state
  #   if cursorState
  #     el.addClass('cursor-on')
  #     el.removeClass('cursor-off')
  #   else
  #     el.removeClass('cursor-on')
  #     el.addClass('cursor-off')

  updateText = (text, cpos, cprp) ->
    # cursorBlinkReset()
    if cpos == undefined then cpos = text.length
    if cpos < 0 then cpos = text.length + cpos
    if cpos < 0 then cpos = 0
    if cpos > text.length then cpos = text.length
    currtext = text
    currcpos = cpos
    text1 = text.slice(0,cpos)
    text2 = text.slice(cpos)
    currrow.children().remove()
    if (text1.length > 0)
      currrow.append(text2html(text1))
    currrow.append(cursorEl.detach())
    if (text2.length > 0)
      currrow.append(text2html(text2))
    # cursorBlinkBegin()
    scrollToBottom()

  # insertChar = (ch) ->
  #   newtext = undefined
  #   cpos = currcpos
  #   if cpos == undefined
  #     newtext = currtext + ch
  #   else
  #     newtext = currtext.slice(0,cpos) + ch + currtext.slice(cpos)
  #     cpos += ch.length
  #   updateText(newtext, cpos)

  # removeChar = (len) ->
  #   if len == undefined then len = 1
  #   if len < 0 then return
  #   newtext = undefined
  #   cpos = currcpos
  #   if cpos == undefined
  #     newtext = currtext.slice(0, currtext.length - len)
  #   else
  #     newtext = currtext.slice(0, cpos - len) + currtext.slice(cpos)
  #     cpos -= len
  #     if cpos < 0 then cpos = 0
  #   updateText(newtext, cpos)

  moveCursor = (amount) ->
    cpos = currcpos
    if cpos == undefined then cpos = currtext.length
    cpos += amount
    if cpos > currtext.length then cpos = currtext.length
    if cpos < 0 then cpos = 0
    updateText(currtext, cpos, currprop, currcprp)

  appendRow = (text) ->
    newrow = makeContentRow().append(text2html(text))
    currrow.before(newrow)
    scrollToBottom()

  # Bind focus/blur events
  el.attr('tabindex', -1)
  el.on 'focus', ->
    # fakeinput.focus()
    updateBlinkState()
    return
  el.on 'blur', ->
    updateBlinkState()
    return

  el.on 'keyup', (event)->
    if not initialized then return
    keycode = event.keyCode
    ch = String.fromCharCode(keycode)
    keych = event.key
    prevtext = currrow.text()
    # console.log(keycode, event)
    visible = false
    visible = visible || (keycode >= 48 and keycode <= 90) # digital and alphabets
    visible = visible || (keycode >= 96 and keycode <= 111 and keycode != 108) # KP keys
    visible = visible || (keycode >= 186 and keycode <= 192) # punctuations
    visible = visible || (keycode >= 219 and keycode <= 222) # punctuations
    visible = visible || (keycode == 32) # space bar
    # if !event.ctrlKey and !event.metaKey and !event.shiftKey
    if !event.ctrlKey and !event.metaKey and visible and keych
      # Visible chars
      #### insertChar(keych)
      ws.send(keych)
    else if event.ctrlKey and keycode >= 65 and keycode <= 90
      # Control
      ws.send(String.fromCharCode(keycode-64))
    else if keycode == 8
      # Delete
      #### removeChar()
      #### ws.send('\\x' + 127)
      ws.send('\x08')
    else if keycode == 108 or keycode == 13
      # Enter
      #### appendRow(currtext)
      #### updateText("")
      ws.send('\r')
    else if keycode == 37
      # Left key
      #### moveCursor(-1)
      ws.send('\x1B[D')
    else if keycode == 39
      # Right key
      #### moveCursor(1)
      ws.send('\x1B[C')
    else if keycode == 38
      # Up key
      ws.send('\x1B[A')
    else if keycode == 40
      # Down key
      ws.send('\x1B[B')
    else if keycode == 0x09
      # Tab
      ws.send('\t')
  
  handleMessage = (data) ->
    if data.slice(0, wscmd_prefix.length) == wscmd_prefix
      wscmd = data.slice(wscmd_prefix.length)
      if wscmd == "ack_establish"
        for cmd in config.initcmds
          ws.send(cmd + "\n")
        initialized = true
      else if wscmd == "ack_release"
        initialized = false
      else if wscmd == "ack_sync"
        initialized = true
    else if initialized
      text = ""
      data = ControlSignal.parseSentence(data)
      # console.log((item.toString() for item in data).join(""))
      console.log("[data]", data)
      cpos = currcpos
      if cpos == undefined then cpos = currtext.length
      cprp = currcprp
      text0 = new StyledText()
      text1 = currtext.slice(0, cpos)
      text2 = currtext.slice(cpos)
      # console.log("[cprp]", cprp)
      for item in data
        if typeof item == "string"
          text1 = text1.concat(new StyledText(item, cprp))
          unless currcmod[4]
            text2 = text2.slice(item.length)
        else if item instanceof ControlSignal
          lead = item.lead
          char = item.char
          nums = item.nums
          num1 = nums[0]
          num2 = nums[1]
          if lead == '\x08'
            # backspace
            text2 = text1.slice(-1).concat(text2)
            text1 = text1.slice(0,-1)
          else if lead == '\x07'
            # beep
            beep()
          else if lead == '\r'
            # Return
            text2 = text1.concat(text2)
            text1 = new StyledText()
          else if lead == '\n'
            # Next row
            text_tmp = text1.concat(text2)
            text0 = text0.concat(text_tmp, new StyledText('\n', cprp))
            text1 = new StyledText((" " for c in text1).join(""), cprp)
            text2 = new StyledText()
          else if lead == '\x1B'
            # escape sequence
            if char == "K"
              # Erase in Line (DECSEL).
              nc = num1 || 0
              if nc == 0
                text2 = new StyledText()
              else if nc == 1
                text1 = new StyledText()
              else if nc == 2
                text1 = new StyledText()
                text2 = new StyledText()
            else if char == "P"
              # Delete Ps Character(s) (default = 1) (DCH).
              nc = num1 || 1
              text2 = text2.slice(nc)
            else if char == "C"
              nc = num1 || 1
              text1 = text1.concat(text2.slice(0,nc))
              text2 = text2.slice(nc)
            else if char == "D"
              nc = num1 || 1
              text2 = text1.slice(-nc).concat(text2)
              text1 = text1.slice(0,-nc)
            else if char == "J"
              # Erase in Display (DECSED).
              # @TODO: Should clear the whole screen instead of the current line
              nc = num1 || 0
              if nc == 0
                text2 = new StyledText()
              else if nc == 1
                text1 = new StyledText()
              else if nc == 2
                text1 = new StyledText()
                text2 = new StyledText()
            else if char == "G"
              nc = num1 || 1
              nc = nc - 1
              if nc < 0 then nc = 0
              text_tmp = text1.concat(text2)
              text1 = text_tmp.slice(0,nc)
              while text1.length < nc
                text1 = text1.concat(new StyledText(" ", cprp))
              text2 = text_tmp.slice(nc)
            else if char == "h"
              nc = num1
              if nc >= 0 and nc <= 4 then currcmod[nc] = true
            else if char == "l"
              nc = num1
              if nc >= 0 and nc <= 4 then currcmod[nc] = false
            else if char == "m"
              val0 = undefined # style
              val1 = undefined # fg_color
              val2 = undefined # bg_color
              for n in nums
                if n >= 0 and n <= 8
                  val0 = n
                else if n >= 30 and n <= 37
                  val1 = n
                else if n >= 40 and n <= 47
                  val2 = n
              ctrl = {}
              (ctrl[k] = cprp.ctrl[k]) for k in Object.keys(cprp.ctrl)
              if val0 == 0 or nums.length == 0
                ctrl = { clear: true }
                val1 = 0
                val2 = 0
              else
                ctrl.clear = false
                if val0 == 1
                  ctrl.highlight = true
                else if val0 == 4
                  ctrl.underline = true
                else if val0 == 5
                  ctrl.blink = true
                else if val0 == 7
                  ctrl.inverse = true
                else if val0 == 8
                  ctrl.invisible = true
              cprp = new TextProp(ctrl, val1, val2)
    
      # horizontal tab
      data = text0.concat(text1, text2)
      cpos = data.length - text2.length
      cpos_at_last = (text2.length == 0)
      tokens = []
      for i in [0...data.length]
        ch = data.at(i)
        if ch.char == '\n' or ch.char == '\x09'
          tokens.push({i: i, c: ch})
      acctext = new StyledText()
      acclen = 0
      lines = []
      if tokens.length > 0
        if tokens[0].i > 0
          acctext = acctext.concat(data.slice(0, tokens[0].i))
        for i in [0...tokens.length]
          i1 = tokens[i].i
          i2 = if i + 1 < tokens.length then tokens[i+1].i else data.length
          ch = tokens[i].c
          if (not cpos_at_last) and (i1 <= cpos and cpos < i2)
            cpos = acclen + cpos - i1
          if ch.char == '\n'
            acclen += acctext.length + 1
            lines.push(acctext)
            acctext = new StyledText()
          else if ch.char == '\x09'
            nremain = config.tabwidth - acctext.length % config.tabwidth
            newtext = (" " for j in [0...nremain]).join("")
            acctext = acctext.concat(new StyledText(newtext, ch.prop))
          if i1 + 1 < i2
            acctext = acctext.concat(data.slice(i1 + 1, i2))
        lines.push(acctext)
        acclen += acctext.length
      else
        lines.push(data)
        acclen += data.length
      cpos = acclen - cpos

      # build the text
      for line in lines.slice(0, lines.length-1)
        appendRow(line)
      lastline = lines[lines.length-1]
      updateText(lastline, lastline.length - cpos, cprp)

  el.on 'keydown', (event)->
    keycode = event.keyCode
    # prevent arrow scroll
    if keycode >= 37 and keycode <= 40
      event.preventDefault()
    # prevent tab switch
    if keycode == 0x09
      event.preventDefault()


  # fakeinput.on 'keypress', ->
  #   val = fakeinput.val()
  #   currrow.text(val)
  #   currrow.append(makeCursor())

  # initilize the websocket
  ws = new WebSocket(config.wsurl)
  ws.addEventListener 'open', (event) ->
    console.info 'WebSocket open'
    ws.send(wscmd_prefix + "establish " + window_width + " " + window_height)
  ws.addEventListener 'error', (event) ->
    console.error 'WebSocket error', event
  ws.addEventListener 'message', (event) ->
    data = event.data
    handleMessage(data)
  ws.addEventListener 'close', (event) ->
    console.info 'WebSocket close', event
    initialized = false
  window.ws = ws


module.exports = ConsoleBox