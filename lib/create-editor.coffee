"strict"

{TextBuffer} = require 'atom'
fs = require('fs').promises
path = require 'path'
setDir = require './set-dir'

constantly = (val)-> -> val

# Prevents event propagation to original commands
# - no need to do it manually in every overridden command
# - done only in commands which need it
# overrideHandler = (f)-> (event)->
#   event.stopImmediatePropagation()
#   f event
# overrideKeybindings = (target)->
#   # Override all other packages that might use same keybindings
#   commandMap = require './commands'
#   _commandMap = Object.assign {}, commandMap
#   for command, fn of commandMap
#     keys = atom.keymaps.findKeyBindings {command, target}
#     for {keystrokes} in keys
#       bindings = atom.keymaps.findKeyBindings {keystrokes, target}
#       for b in bindings when b.command isnt command
#         cmd = b.command
#         if orig = atom.commands.selectorBasedListenersByCommandName[cmd]?[0]
#           do (orig, cmd)->
#             fn.original = (event)->
#               console.log event
#               event = Object.assign {}, event, type: cmd
#               console.log event
#               # orig.didDispatch.call this, event
#         _commandMap[b.command] = overrideHandler fn
#   _commandMap

module.exports = (uri)->
  params =
    buffer: new TextBuffer()
    readOnly: true
    softWrapped: false
    tabLength: 1
    softTabs: true
    lineNumberGutterVisible: false
    autoHeight: false
  params.buffer.release = -> # maybe needed, was somewhere, test without
  editor = atom.textEditors.build(params)
  # x = atom.commands.add editor.getElement(), commandMap
  # editor.onDidDestroy -> x.dispose()
  editor.getElement().classList.add 'dir'
  _myPackage = {uri: ''}
  for field in setDir.fields.concat ['link', 'directory', 'filename']
    layer = params.buffer.addMarkerLayer role: field
    editor.decorateMarkerLayer layer, type:'text', class: field
    _myPackage[field] = layer
  Object.assign editor, {_myPackage},
    isModified : constantly false
    serialize : constantly null
    #getPath : -> @_myPackage.uri
    getURI : -> @_myPackage.uri
    getTitle : -> path.basename(@_myPackage.uri) + '/'
    getLongTitle : -> @getTitle() + ' - ' + path.dirname(@_myPackage.uri)
  setDir editor, uri
  target = editor.element
  # delay until all packages have inserted their classes
  once2 = atom.workspace.onDidOpen ({item})->
    return unless item is editor
    once2.dispose()
    # x = atom.commands.add editor.getElement(), overrideKeybindings(target)
    x = atom.commands.add target, require './commands'
    xx = editor.onDidChangeCursorPosition (e)->
      return if e.textChanged or not e.cursor.editor.element.classList.contains 'visual-mode'
      row = 3 - e.newBufferPosition.row
      e.cursor.moveDown row if row > 0
    # xxx = atom.commands.add target, 'core:copy': (e)->
    #   e.stopImmediatePropagation()
    #   atom.commands.dispatch(e.currentTarget, 'my-package:copy-selected-to-clipboard')
    editor.onDidDestroy ->
      x.dispose()
      xx.dispose()
      # xxx.dispose()
  editor
