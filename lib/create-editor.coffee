"strict"

{TextEditor, TextBuffer} = require 'atom'
path = require 'path'
fs = require 'fs'

class DirectoryView extends TextEditor
  constructor: (params)->
    params = Object.assign {}, viewDefaults, params
    params.buffer ?= new TextBuffer()
    super params
  serialize: -> null
  getDirectoryPath: -> @_uri
  setPath: (uri)->
    return if @_uri is uri = path.resolve uri
    return unless fs.existsSync(uri)
    @_uri = uri
    @emitter.emit 'did-change-title'
  getTitle: -> path.basename(@getDirectoryPath()) + "/"
  getLongTitle: -> @getDirectoryPath() + "/"
  isModified: -> false
  editMode: (opts)-> editMode this, opts

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

editMode = (editor, {cls, validator, save, vimState})->
  editor.setReadOnly false
  editor.element.classList.remove 'dir-opener'
  editor.element.classList.add cls
  origText = editor.getText()
  new Promise (resolve)->
    stop = ->
      _commands.dispose()
      editor.setReadOnly true
      editor.element.classList.add 'dir-opener'
      editor.element.classList.remove cls
      resolve("force")
    _commands = atom.commands.add editor.element,
      'core:close': (ev)->
        ev.stopImmediatePropagation()
        stop()
      'core:save': (ev)->
        ev.stopImmediatePropagation()
        return stop() if origText is text = editor.getText()
        stop() if await save()
    cp = editor.createCheckpoint()
    illegalEdit = (msg)->
      atom.notifications.addWarning "Illegal edit", detail:msg, dismissable:true
      _cp = cp # nextNormalMode may change cp
      vimState.activate "normal"
      cp = _cp
      editor.revertToCheckpoint(cp)
    _commands.add editor.onDidStopChanging ->
      if err = validator arguments...
        return illegalEdit err
      nextNormalMode vimState, -> cp = editor.createCheckpoint()
    _commands.add editor.onDidDestroy ->
      _commands.dispose()
      resolve("force")

nextNormalMode = (vimState, fn)->
  return fn() if vimState.mode is 'normal'
  once = vimState.onDidActivateMode ({mode})->
    return unless mode is 'normal'
    once.dispose()
    fn()
