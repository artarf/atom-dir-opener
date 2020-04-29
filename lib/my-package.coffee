{CompositeDisposable} = require 'atom'
path = require 'path'
# utils = require './utils'
# require './format'
# require './commands'

defaultDir = ->
  os = require 'os'
  p = atom.project.getDirectories()[0]
  p?.path ? os.homedir()

opener = (uri, x)->
  fs = require 'fs'
  setDir = require './set-dir'
  return if uri.startsWith 'atom:'
  try
    if uri.endsWith(path.sep) or uri is '~' or fs.statSync(uri).isDirectory()
      if existing = atom.workspace.getActivePane().items.find (x)-> x._myPackage?
        setDir existing, uri
        existing
      else
        createEditor = require './create-editor'
        createEditor uri
  catch e

module.exports = MyPackage =
  subscriptions: null

  activate: ->
    await require('atom-package-deps').install('my-package')
    keymapFile = path.join path.dirname(__dirname), 'keymaps', 'my-package.cson'
    atom.keymaps.reloadKeymap keymapFile, priority: 1
    once = atom.workspace.observeTextEditors (e)->
      if (not e.getPath?()) and e.getTitle() is 'untitled'
        console.log "remove untitled"
        atom.workspace.getActivePane()?.close()
        if dir = atom.project.rootDirectories[0]
          atom.workspace.open dir.path + '/'
      setTimeout -> once.dispose()

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.addOpener(opener)
    if atom.textEditors.editors.size is 0
      if dir = atom.project.rootDirectories[0]
        atom.workspace.open dir.path + '/'

    @subscriptions.add atom.commands.add 'atom-workspace',
      'my-package:open-directory': ->
        if e = atom.workspace.getActivePaneItem()
          if e._myPackage?
            console.log "should cycle project dirs"
            return
          if _path = e?.getPath?()
            return atom.workspace.open _path + path.sep
        atom.workspace.open defaultDir()
  useVimModePlus: (vmp)->

  deactivate: -> @subscriptions?.dispose()
