"use strict"

{TextEditor, TextBuffer} = require 'atom'

viewDefaults =
  readOnly: true
  softWrapped: false
  tabLength: 1
  softTabs: true
  lineNumberGutterVisible: false
  autoHeight: false

module.exports = (text, title, cmd)->
  parse = require './parse-sgr'
  _ = require 'lodash'
  buffer = new TextBuffer
  atom.grammars.assignLanguageMode buffer, 'text.plain'
  now = new Date()
  editor = new TextEditor(Object.assign {buffer}, viewDefaults)
  editor.getTitle = -> title
  editor.getLongTitle = -> title + ':' + cmd + ' @ ' + now.toLocaleString()
  editor.isModified = -> false
  {text, ranges} = parse text
  editor.buffer.setText text, bypassReadOnly:true
  xx = (arr)-> arr.sort().join ','
  _styles = _.uniq _.map(ranges, 0).map xx

  # _styles = _styles.map (s)-> styles[s]
  layers = {}
  unknownAnsi = editor.addMarkerLayer()
  editor.decorateMarkerLayer unknownAnsi, {type:'text', style:{color: 'red'}}
  for s in _styles
    unless style = styles[s]
      console.warn "ansi sgr not supported (yet)", [s]
      continue
    layer = editor.addMarkerLayer()
    editor.decorateMarkerLayer layer, {type:'text', style}
    layers[s] = layer
  for [ansi, range] in ranges
    layer = layers[xx(ansi)] ? unknownAnsi
    layer.markBufferRange range.map (p)-> buffer.positionForCharacterIndex p

  editor

styles = {
  "\u001b[1m": { 'font-weight': 'bold', color: '#eee' }
  "\u001b[31m": { color: 'pink' }
  "\u001b[32m": { color: 'lightgreen' }
  "\u001b[01;32m": { 'font-weight': 'bold', color: 'lightgreen' }
  "\u001b[33m": { color: 'lightyellow' }
  "\u001b[34m": { color: 'cornflowerblue' }
  "\u001b[01;34m": { 'font-weight': 'bold', color: 'cornflowerblue' }
  "\u001b[36m": { color: 'lightcyan' }
}

# styles = {
#   "\u001b[33m": 'ansi-yellow'
#   "\u001b[1m": 'ansi-bold'
#   "\u001b[36m": 'ansi-cyan'
#   "\u001b[32m": 'ansi-green'
# }
