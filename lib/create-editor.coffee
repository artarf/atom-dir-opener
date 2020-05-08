"strict"

{TextEditor, TextBuffer} = require 'atom'
path = require 'path'

class DirectoryBuffer extends TextBuffer
  release: -> # maybe needed, was somewhere, test without
  isModified: -> false
  # disable buffer.getPath() because project wants to start watching if it is a git repo.
  # - It might be big and then git-utils repo.getPath() will then hang everything
  getPath: ->
  setPath: (uri)->
    return if uri is @getPath()
    @setFile {
      getPath: -> uri
      existsSync: -> true
    }

class DirectoryView extends TextEditor
  constructor: (params)->
    params = Object.assign {}, viewDefaults, params
    params.buffer ?= new DirectoryBuffer()
    super params
  serialize: -> null
  getPath: -> @buffer.file.getPath()
  getTitle: -> @getFileName() + "/"

viewDefaults =
  readOnly: true
  softWrapped: false
  tabLength: 1
  softTabs: true
  lineNumberGutterVisible: false
  autoHeight: false

module.exports = (uri, fields)->
  editor = new DirectoryView()
  editor.buffer.setPath uri
  editor.getElement().classList.add 'dir'
  for field in fields
    layer = editor.addMarkerLayer role: field
    editor.decorateMarkerLayer layer, type:'text', class: field
  editor
