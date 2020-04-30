path = require 'path'
setDir = require './set-dir'
os = require 'os'
electron = require 'electron'
git = require './git'

fileAtCursor = (event)->
  editor = event.currentTarget.getModel()
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  {uri, entries} = editor._myPackage
  [name, stats, link] = entries[row-1]
  path.join uri, name

openExternal = (event)->
  editor = event.currentTarget.getModel()
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  {uri, entries} = editor._myPackage
  [name, stats, link] = entries[row-1]
  electron.shell.openItem path.join uri, name

# selectCurrent = (event)->
#   return if event.currentTarget.getModel()?.getCursorBufferPosition().row < 3
#   atom.commands.dispatch event.currentTarget, 'vim-mode-plus:activate-linewise-visual-mode'
#   atom.commands.dispatch event.currentTarget, 'vim-mode-plus:toggle-persistent-selection'

reload = (event)->
  editor = event.currentTarget.getModel()
  setDir editor, editor._myPackage.uri, true

goHome = (event)->
  editor = event.currentTarget.getModel()
  setDir editor, os.homedir()

openParent = (event)->
  editor = event.currentTarget.getModel()
  vimState(editor).clearPersistentSelections()
  {uri} = editor._myPackage
  setDir editor, path.dirname uri

vimState = (editor)-> atom.packages.getActivePackage('vim-mode-plus').mainModule.getEditorState(editor)

toggleRow = (event)->
  editor = event.currentTarget.getModel()
  {row} = editor.getCursorBufferPosition()
  return editor.moveDown(1) if row < 3
  {buffer} = editor
  range = buffer.clipRange [[row, 0], [row+1, 0]]
  # console.log JSON.stringify range
  vimstate = vimState(editor)
  x = vimstate.persistentSelection.getMarkers().filter (m)-> m.getBufferRange().intersectsWith range, true
  # console.log JSON.stringify vimstate.getPersistentSelectionBufferRanges()
  for marker in x
    r = marker.getBufferRange()
    if r.containsRange(range) and not (r.start.isEqual(range.start) and r.end.isEqual(range.end))
      # console.log 'a'
      vimstate.persistentSelection.markBufferRange buffer.clipRange [r.start, range.start]
      vimstate.persistentSelection.markBufferRange buffer.clipRange [range.end, r.end]
      marker.destroy()
    else if r.containsPoint range.start, true
      # console.log 'b'
      vimstate.persistentSelection.markBufferRange buffer.clipRange [range.start, r.start]
      marker.destroy()
    else
      # console.log 'c'
      vimstate.persistentSelection.markBufferRange buffer.clipRange [r.end, range.end]
      marker.destroy()
  unless x.length
    vimstate.persistentSelection.markBufferRange range
  editor.moveDown(1)

clearSelections = (editor)->
  vimState(editor).clearPersistentSelections()
  if -1 is editor.getSelections().indexOf (s)-> not s.getBufferRange().isEmpty()
    pos = editor.getCursorBufferPosition()
    range = editor.getSelectedBufferRanges().find (r)-> r.containsPoint pos
    i = if pos.row is range.end.row and not range.isSingleLine() then -1 else 0
    editor.clearSelections()
    editor.setCursorBufferPosition pos.translate [i, 0]
  else editor.clearSelections()

getSelectedEntries = (event)->
  editor = event.currentTarget.getModel()
  vimstate = vimState(editor)
  sels = vimstate.getPersistentSelectionBufferRanges()
  unless sels.length
    sels = editor.getSelectedBufferRanges()
  a = new Map
  {uri, entries} = editor._myPackage
  for {start, end} in sels
    for i in [start.row .. end.row - (end.column is 0)] by 1
      a.set i - 1, entries[i - 1] if i > 2
  unless a.size
    i = sels[0].start.row
    a.set i - 1, entries[i - 1] if i > 2
  a

openChild = (event)->
  editor = event.currentTarget.getModel()
  {uri, entries} = editor._myPackage
  {row} = editor.getCursorBufferPosition()
  return if row < 2
  [name, stats, link] = entries[row-1]
  return openParent event if name is '..'
  vimState(editor).clearPersistentSelections()
  newuri = path.join uri, name
  if stats.isDirectory() or link?.endsWith path.sep
    editor._myPackage.current = null
    setDir editor, newuri
  else
    atom.workspace.open newuri

copyNamesToClipboard = (event)->
  entries = Array.from getSelectedEntries(event).values(), (a)-> a[0]
  atom.clipboard.write entries.join '\n'
  editor = event.currentTarget.getModel()
  clearSelections(editor)

gitToggleStaged = (event)->
  file = fileAtCursor(event)
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  dir = path.dirname file
  restore = []
  getSelectedEntries(event).forEach ([file])->
    _file = path.join _base, file
    if repo.isPathStaged _file
      restore.push file
    else
      repo.add _file
  editor = event.currentTarget.getModel()
  uri = editor._myPackage.uri
  if restore.length
    await git 'restore', '--staged', restore..., dir
  setDir editor, uri, true

copyFullpathsToClipboard = (event)->
  editor = event.currentTarget.getModel()
  {uri} = editor._myPackage
  entries = Array.from getSelectedEntries(event).values(), (a)-> path.join uri, a[0]
  atom.clipboard.write entries.join '\n'
  clearSelections(editor)

module.exports =
  'my-package:open-parent-directory': openParent
  'my-package:open-child': openChild
  'my-package:go-home': goHome
  'my-package:reload-directory': reload
  'my-package:open-external': openExternal
  # 'my-package:select-current': selectCurrent
  'my-package:copy-names-to-clipboard': copyNamesToClipboard
  'my-package:copy-fullpaths-to-clipboard': copyFullpathsToClipboard
  'my-package:toggle-selected-and-next-row': toggleRow
  'my-package:git-toggle-staged': gitToggleStaged
  'my-package:activate-linewise-visual-mode': (event)->
    return if event.currentTarget.getModel().getCursorBufferPosition().row < 3
    atom.commands.dispatch event.currentTarget, 'vim-mode-plus:activate-linewise-visual-mode'
  'my-package:noop': -> console.log arguments
