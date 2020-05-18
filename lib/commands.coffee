path = require 'path'
os = require 'os'
electron = require 'electron'
_ = require 'lodash'
{getFields} = require './utils'
git = require './git'
commit = require('./git-commit')

setTextToRegister = (vimState, text)->
  text += '\n' unless text.endsWith '\n'
  vimState.register.set(null, {text})

openExternal = ({fileAtCursor})-> electron.shell.openItem fileAtCursor if fileAtCursor?

goHome = ({editor})-> editor.setPath os.homedir()

openParent = ({editor})-> editor.setPath path.dirname editor.getDirectoryPath()

assertHasStaged = (repo)->
  return true if repo.watch.status.split('\n').some (x)=> 'MCDARU'.includes x[0]
  atom.notifications.addInfo "Nothing to commit"
  return false

isLastPushed = (repo)->
  return unless balance = repo.watch.balance
  balance = balance.split /\s+/
  if balance[1] is '0'
    atom.notifications.addWarning "Last commit is already pushed", dismissable: true
    return true

quickAmend = ({editor, repo})->
  return unless repo
  return if isLastPushed repo
  if assertHasStaged(repo)
    require('./git-commit').amendWithSameMessage repo.root

gitAmend = ({editor, repo})->
  return unless repo
  return if isLastPushed repo
  require('./git-commit').commitWithEditor repo.root, true

gitCommit = ({editor, repo})->
  if repo and assertHasStaged(repo)
    require('./git-commit').commitWithEditor repo.root

undoLastGitCommit = ({repo})->
  return unless repo
  try
    await git 'reset', '--soft', 'HEAD~', path.dirname repo.root
  catch e
    atom.notifications.addError 'Undo commit failed', detail: e.message, dismissable: true

ToggleInProject = ({editor})->
  ep = editor.getDirectoryPath()
  pp = atom.project.getPaths().filter (pp)-> pp isnt ep and pp.startsWith ep
  if pp.length
    atom.notifications.addError "This is parent for other project", dismissable: true, detail:pp.join '\n'
  else if pp = atom.project.getPaths().find (pp)-> ep.startsWith pp
    atom.project.removePath pp
  else atom.project.addPath ep

moveDown = (editor)->
  lrow = editor.getLastBufferRow()
  lrow-- if editor.lineTextForBufferRow(lrow) is ""
  pos = editor.getCursorBufferPosition()
  if pos.row is lrow
    editor.setCursorBufferPosition row:5, column: pos.column if lrow > 5
  else
    editor.moveDown(1)

toggleRow = ({editor, vimState})->
  return unless vimState
  {row} = editor.getCursorBufferPosition()
  return moveDown(editor) if row < 5
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
  moveDown(editor)

clearSelections = (editor, vimState)->
  vimState?.clearPersistentSelections()
  pos = editor.getCursorBufferPosition()
  sel = editor.getSelectedBufferRange()
  pos = pos.translate [-1, 0] if pos.row > sel.start.row
  editor.setCursorBufferPosition(pos)

openChild = ({editor, fileAtCursor})->
  {row} = editor.getCursorBufferPosition()
  return if row < 4
  if fileAtCursor.endsWith path.sep
    editor.setPath fileAtCursor
  else
    if editor isnt await atom.workspace.open fileAtCursor
      atom.workspace.paneForItem(editor)?.destroyItem(editor)

copyNamesToClipboard = ({editor, vimState, selected})->
  setTextToRegister vimState, selected.join '\n'
  clearSelections(editor, vimState)

gitReset = ({fileAtCursor, selected})->
  return unless file = fileAtCursor
  return unless repo = git.utils file
  _file = repo.relativize file
  _base = path.dirname _file
  for file in selected
    _file = path.join _base, file
    repo.checkoutHead _file

gitToggleStaged = ({selected, editor, repo})->
  return unless selected.length
  return unless repo
  dir = editor.getDirectoryPath()
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

copyFullpathsToClipboard = ({editor, selected, vimState})->
  uri = editor.getDirectoryPath()
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
  'dir-opener:quick-amend': quickAmend
  'dir-opener:git-amend': gitAmend
  'dir-opener:undo-last-commit': undoLastGitCommit
  'dir-opener:activate-linewise-visual-mode': ({editor})->
    return if editor.getCursorBufferPosition().row < 3
    atom.commands.dispatch editor.element, 'vim-mode-plus:activate-linewise-visual-mode'
  'dir-opener:noop': -> console.log arguments
