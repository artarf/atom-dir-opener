"strict"

{TextEditor, TextBuffer} = require 'atom'
path = require 'path'

class DirectoryView extends TextEditor
  constructor: (params)->
    params = Object.assign {}, viewDefaults, params
    params.buffer ?= new TextBuffer()
    super params
  serialize: -> null
  getDirectoryPath: -> @_uri
  setPath: (uri)->
    return if @_uri is uri = path.resolve uri
    @_uri = uri
    @emitter.emit 'did-change-title'
  getTitle: -> path.basename(@getDirectoryPath()) + "/"
  getLongTitle: -> @getDirectoryPath() + "/"
  isModified: -> false

viewDefaults =
  readOnly: true
  softWrapped: false
  tabLength: 1
  softTabs: true
  lineNumberGutterVisible: false
  autoHeight: false

module.exports = (uri, fields)->
  editor = new DirectoryView()
  editor.setPath uri
  editor.getElement().classList.add 'dir-opener'
  for field in fields
    layer = editor.addMarkerLayer role: field
    editor.decorateMarkerLayer layer, type:'text', class: field
  editor
