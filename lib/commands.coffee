path = require 'path'
os = require 'os'
electron = require 'electron'
_ = require 'lodash'
{getFields} = require './utils'
git = require './git'

setDir = (editor, uri)-> editor.buffer.setPath uri

fileAtCursor = (event)->
  editor = event.currentTarget.getModel()
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  uri = editor.getPath()
  path.normalize path.join uri, getFields(editor, row, ['name'])[0]

openExternal = (event)->
  editor = event.currentTarget.getModel()
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  electron.shell.openItem fileAtCursor(event)

goHome = (event)->
  editor = event.currentTarget.getModel()
  setDir editor, os.homedir()

openParent = (event)->
  editor = event.currentTarget.getModel()
  setDir editor, path.dirname editor.getPath()

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
  pos = editor.getCursorBufferPosition()
  sel = editor.getSelectedBufferRange()
  pos = pos.translate [-1, 0] if pos.isEqual(sel.end) and pos.isGreaterThan(sel.start)
  editor.setCursorBufferPosition(pos)

getSelectedEntries = (event)->
  editor = event.currentTarget.getModel()
  vimstate = vimState(editor)
  sels = vimstate.getPersistentSelectionBufferRanges()
  unless sels.length
    sels = editor.getSelectedBufferRanges()
  a = new Map
  uri = editor.getPath()
  for {start, end} in sels
    for i in [start.row .. end.row - (end.column is 0)] by 1
      a.set i, _.first getFields editor, i, ['name']
  unless a.size
    a.set 0, getFields(editor, sels[0].start.row, ['name'])[0]
  a

openChild = (event)->
  editor = event.currentTarget.getModel()
  uri = path.normalize editor.getPath()
  {row} = editor.getCursorBufferPosition()
  return if row < 1
  [name, link] = getFields editor, row, ['name', 'link']
  return unless name
  return openParent event if name.startsWith '..'
  newuri = path.normalize path.join uri, name
  if (name + link).endsWith path.sep
    setDir editor, newuri
  else
    if await atom.workspace.open newuri
      atom.workspace.paneForItem(editor)?.destroyItem(editor)

copyNamesToClipboard = (event)->
  entries = Array.from getSelectedEntries(event).values()
  atom.clipboard.write entries.join '\n'
  editor = event.currentTarget.getModel()
  clearSelections(editor)

gitReset = (event)->
  file = fileAtCursor(event)
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  getSelectedEntries(event).forEach (file)->
    _file = path.join _base, file
    repo.checkoutHead _file

gitToggleStaged = (event)->
  return unless file = fileAtCursor(event)
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  dir = path.dirname file
  restore = []
  dirs = []
  getSelectedEntries(event).forEach (file)->
    if file.endsWith path.sep
      dirs.push file
      return
    _file = path.join _base, file
    if repo.isPathStaged _file
      restore.push file
    else
      repo.add _file
  if restore.length
    await git 'restore', '--staged', restore..., dir
  if dirs.length
    atom.notifications.addWarning "Directories not toggled: #{dirs.join ', '}", dismissable: true

copyFullpathsToClipboard = (event)->
  editor = event.currentTarget.getModel()
  uri = editor.getPath()
  entries = Array.from getSelectedEntries(event), (a)-> path.join uri, a[1]
  atom.clipboard.write entries.join '\n'
  clearSelections(editor)

module.exports =
  'my-package:open-parent-directory': openParent
  'my-package:open-child': openChild
  'my-package:go-home': goHome
  'my-package:open-external': openExternal
  'my-package:copy-names-to-clipboard': copyNamesToClipboard
  'my-package:copy-fullpaths-to-clipboard': copyFullpathsToClipboard
  'my-package:toggle-selected-and-next-row': toggleRow
  'my-package:git-toggle-staged': gitToggleStaged
  'my-package:git-reset-head': gitReset
  'my-package:activate-linewise-visual-mode': (event)->
    return if event.currentTarget.getModel().getCursorBufferPosition().row < 3
    atom.commands.dispatch event.currentTarget, 'vim-mode-plus:activate-linewise-visual-mode'
  'my-package:noop': -> console.log arguments
