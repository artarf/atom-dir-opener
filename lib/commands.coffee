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

gitCommit = (_, {editor, repo})->
  return unless repo
  dir = editor.getPath()
  unless repo.watch.status.split('\n').some (x)=> 'MCDARU'.includes x[0]
    atom.notifications.addInfo "Nothing to commit"
    return
  commit = require './git-commit'
  commit repo.root

undoLastGitCommit = (_, {repo})->
  return unless repo
  try
    await git 'reset', '--soft', 'HEAD~', path.dirname repo.root
  catch e
    atom.notifications.addError 'Undo commit failed', detail: e.message, dismissable: true

ToggleInProject = (_, {editor})->
  ep = editor.getPath()
  pp = atom.project.getPaths().filter (pp)-> pp isnt ep and pp.startsWith ep
  if pp.length
    atom.notifications.addError "This is parent for other project", dismissable: true, detail:pp.join '\n'
  else if pp = atom.project.getPaths().find (pp)-> ep.startsWith pp
    atom.project.removePath pp
  else atom.project.addPath ep

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

gitToggleStaged = (_, {selected, editor, repo})->
  return unless selected.length
  return unless repo
  dir = editor.getPath()
  status = git.parseStatus repo.watch.status, path.relative path.dirname(repo.root), dir
  add = []
  restore = []
  dirs = []
  for file in selected
    continue unless s = status[file]
    if file.endsWith path.sep
      dirs.push file
    else if 'MCDARU'.includes s[0]
      restore.push file
    else if s[1] isnt ' ' and s[1] isnt '!'
      add.push file
  if add.length
    git 'add', add..., dir
  if restore.length
    git 'restore', '--staged', restore..., dir
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
  'dir-opener:toggle-in-project': ToggleInProject
  'dir-opener:git-commit': gitCommit
  'dir-opener:undo-last-commit': undoLastGitCommit
  'dir-opener:activate-linewise-visual-mode': (_, {editor})->
    return if editor.getCursorBufferPosition().row < 3
    atom.commands.dispatch editor.element, 'vim-mode-plus:activate-linewise-visual-mode'
  'dir-opener:noop': -> console.log arguments
