path = require 'path'
os = require 'os'
electron = require 'electron'
_ = require 'lodash'
{getFields} = require './utils'
git = require './git'

setTextToRegister = (vimState, text)->
  text += '\n' unless text.endsWith '\n'
  vimState.register.set(null, {text})

openExternal = (_, {fileAtCursor})-> electron.shell.openItem fileAtCursor if fileAtCursor?

goHome = (_, {editor})-> editor.buffer.setPath os.homedir()

openParent = (_, {editor})-> editor.buffer.setPath path.dirname editor.getPath()

toggleRow = (_, {editor, vimState})->
  return unless vimState
  {row} = editor.getCursorBufferPosition()
  return editor.moveDown(1) if row < 3
  {buffer} = editor
  range = buffer.clipRange [[row, 0], [row+1, 0]]
  x = vimState.persistentSelection.getMarkers().filter (m)-> m.getBufferRange().intersectsWith range, true
  for marker in x
    r = marker.getBufferRange()
    if r.isEqual(range)
      marker.destroy()
    else if r.containsRange(range) and not (r.start.isEqual(range.start) or r.end.isEqual(range.end))
      marker.setBufferRange [r.start, range.start]
      vimState.persistentSelection.markBufferRange buffer.clipRange [range.end, r.end]
    else if r.containsPoint range.start, true
      marker.setBufferRange [range.start, r.start]
    else
      marker.setBufferRange buffer.clipRange [r.end, range.end]
  unless x.length
    vimState.persistentSelection.markBufferRange range
  editor.moveDown(1)

clearSelections = (editor, vimState)->
  vimState?.clearPersistentSelections()
  pos = editor.getCursorBufferPosition()
  sel = editor.getSelectedBufferRange()
  pos = pos.translate [-1, 0] if pos.row > sel.start.row
  editor.setCursorBufferPosition(pos)

openChild = (_, {editor, fileAtCursor})->
  {row} = editor.getCursorBufferPosition()
  return if row < 4
  if fileAtCursor.endsWith path.sep
    editor.buffer.setPath fileAtCursor
  else
    if editor isnt await atom.workspace.open fileAtCursor
      atom.workspace.paneForItem(editor)?.destroyItem(editor)

copyNamesToClipboard = (_, {editor, vimState, selected})->
  setTextToRegister vimState, selected.join '\n'
  clearSelections(editor, vimState)

gitReset = (_, {fileAtCursor, selected})->
  return unless file = fileAtCursor
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  for file in selected
    _file = path.join _base, file
    repo.checkoutHead _file

gitToggleStaged = (_, {fileAtCursor, selected})->
  return unless file = fileAtCursor
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  dir = path.dirname file
  restore = []
  dirs = []
  for file in selected
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

copyFullpathsToClipboard = (_, {editor, selected, vimState})->
  uri = editor.getPath()
  entries = selected.map (a)-> path.join uri, a
  setTextToRegister vimState, entries.join '\n'
  clearSelections(editor, vimState)

module.exports =
  'dir-opener:open-parent-directory': openParent
  'dir-opener:open-child': openChild
  'dir-opener:go-home': goHome
  'dir-opener:open-external': openExternal
  'dir-opener:copy-names-to-clipboard': copyNamesToClipboard
  'dir-opener:copy-fullpaths-to-clipboard': copyFullpathsToClipboard
  'dir-opener:toggle-selected-and-next-row': toggleRow
  'dir-opener:git-toggle-staged': gitToggleStaged
  'dir-opener:git-reset-head': gitReset
  'dir-opener:activate-linewise-visual-mode': (_, {editor})->
    return if editor.getCursorBufferPosition().row < 3
    atom.commands.dispatch editor.element, 'vim-mode-plus:activate-linewise-visual-mode'
  'dir-opener:noop': -> console.log arguments
