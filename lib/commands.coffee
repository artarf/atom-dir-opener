path = require 'path'
fs = require 'fs'
os = require 'os'
electron = require 'electron'
X = require 'execa'
_ = require 'lodash'
futils = require './file-utils'
{getFields} = require './atom-utils'
git = require './git'
commit = require('./git-commit')

setTextToRegister = (vimState, text)->
  text += '\n' unless text.endsWith '\n'
  vimState.register.set(null, {text})

uniqueName = (dir, name)->
  names = await fs.promises.readdir(dir)
  return path.join dir, name if not names.includes name
  if rr = name.match(/_(\d+)$/)
    name = name.slice 0, rr.index
    start = 1 + parseInt rr[1]
  else
    start = 0
  m = _.keyBy names.filter (x)-> x.startsWith name + '_'
  for i in [start..999999] by 1 when name + '_' + i not of m
    return path.join dir, name + '_' + i

rimraf = (src)->
  stat = await fs.promises.lstat(src)
  if stat.isDirectory()
    await drimraf(src).then (count)-> fs.rmdir(src, ->); count
  else
    await fs.promises.unlink src
    1

plus = (a,b)-> a + b

drimraf = (dir)->
  names = await fs.promises.readdir(dir)
  results = await Promise.all names.map (name)-> rimraf path.join dir, name
  results.reduce plus, 0

copy = (src, tgt)->
  stat = await fs.promises.lstat(src)
  if stat.isDirectory()
    await dircopy src, tgt
  else
    await fs.promises.copyFile src, tgt
    1

dircopy = (src, tgt)->
  names = await fs.promises.readdir(src)
  await fs.promises.mkdir tgt, recursive:true
  results = await Promise.all names.map (name)->
    copy path.join(src, name), path.join(tgt, name)
  results.reduce plus, 0

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

rotateUp = (editor, amt = 1)-> rotateDown editor, -amt
rotateDown = (editor, amt = 1)->
  lrow = editor.getLastBufferRow()
  lrow-- if editor.lineTextForBufferRow(lrow) is ""
  {row, column} = editor.getCursorBufferPosition()
  row += amt
  row = if row > lrow then 5 else if row < 5 then lrow else row
  editor.setCursorBufferPosition {row, column}

toggleRow = ({editor, vimState})->
  return unless vimState
  {row} = editor.getCursorBufferPosition()
  return rotateDown(editor) if row < 5
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
  rotateDown(editor)

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
  {add, restore} = _.groupBy selected, (file)->
    file = file.slice 0, -1 if file.endsWith path.sep
    return unless s = status[file]
    if 'MCDARU'.includes s[0]
      "restore"
    else if s[1] isnt ' ' and s[1] isnt '!'
      "add"
  git 'add', add..., dir if add?
  git 'restore', '--staged', restore..., dir if restore?

copyFullpathsToClipboard = ({editor, selected, vimState})->
  uri = editor.getDirectoryPath()
  entries = selected.map (a)-> path.join uri, a
  setTextToRegister vimState, entries.join '\n'
  clearSelections(editor, vimState)

deleteSelected = (append)-> ({editor, selected, dir, vimState})->
  tmpdir = await fs.promises.mkdtemp path.join os.tmpdir(), 'dir-opener-'
  tmpnames = selected.map (a)-> path.join tmpdir, a
  for p, i in tmpnames
    await fs.promises.rename path.join(dir.directory, selected[i]), p
  files = tmpnames.join '\n'
  if append and x = vimState.register.get()
    files = x.text + files if x.type is 'linewise'
  setTextToRegister vimState, files
  listener = editor.onDidDestroy ->
    listener.dispose()
    fs.existsSync(tmpdir) and rimraf(tmpdir)
  "dir"

pasteFiles = ({dir})->
  filecount = 0
  errors = false
  for file in atom.clipboard.read().split('\n') when file.trim()
    unless file.startsWith path.sep
      file = path.join dir.directory, file
    filebase = path.basename file
    try
      target = await uniqueName dir.directory, filebase
      filecount += await copy file, target
    catch e
      errors = true
      console.error e
  atom.notifications.addInfo "Copied #{filecount} files" if filecount
  atom.notifications.addError "Some errors, see console" if errors
  'dir'

execute = ({fileAtCursor, selected, dir})->
  return unless fileAtCursor
  fs.access fileAtCursor, fs.constants.X_OK, (e)->
    return atom.notifications.addError e.message, dismissable: true if e
    selected = [] if selected.length is 1 and selected[0] is path.basename fileAtCursor
    try
      result = await X fileAtCursor, selected, {cwd: dir.directory, timeout:1000}
    catch result
    {stdout, stderr, exitCode, command} = result
    console.error command, 'exited with', exitCode if exitCode
    pane = atom.workspace.getActivePane()
    ansiViewer = require './ansi-viewer'
    if stdout.trim()
      pane.addItem item = ansiViewer(stdout, "stdout", command)
      pane.setActiveItem item
    if stderr.trim()
      pane.addItem item2 = ansiViewer(stderr, "stderr", command)
      pane.setActiveItem item2 unless item
    else if stdout.trim() is ''
      console.error result.stack if result.stack
      atom.notifications.addError "See log for errors", dismissable:true

notEmpty = (marker)-> not marker.getBufferRange().isEmpty()

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
  'dir-opener:paste-files': pasteFiles
  'dir-opener:delete-selected': deleteSelected(false)
  'dir-opener:delete-selected-append': deleteSelected(true)
  'dir-opener:execute-file-at-cursor': execute
  'dir-opener:edit': ({editor, dir})->
    {directory} = dir
    editor.setReadOnly false
    editor.element.classList.remove 'dir-opener'
    editor.element.classList.add 'dir-opener-edit'
    origText = editor.getText()
    layers = Array.from editor.displayLayer.displayMarkerLayersById.values()
    layers = _.keyBy layers, 'bufferMarkerLayer.role'
    ks = ['mode', 'user', 'group', 'name']
    origCols = {}
    for k in ks
      origCols[k] = x = []
      for m in layers[k].getMarkers()
        r = m.getBufferRange()
        if not r.isEmpty()
          x[r.start.row] = [r.start.column, r.end.column]
    # move cursor to start of file name of current row
    namecol = origCols.name[3][0]
    {row} = editor.getCursorBufferPosition()
    editor.setCursorBufferPosition [row, namecol]
    lc = editor.getLineCount()
    new Promise (resolve)->
      stop = ->
        _commands.dispose()
        editor.setReadOnly true
        editor.element.classList.add 'dir-opener'
        editor.element.classList.remove 'dir-opener-edit'
        resolve("force")
      _commands = atom.commands.add editor.element,
        'core:close': (ev)->
          ev.stopImmediatePropagation()
          stop()
        'core:save': (ev)->
          ev.stopImmediatePropagation()
          return stop() if origText is text = editor.getText()
          if lc isnt editor.getLineCount()
            atom.notifications.addWarning "Don't add or delete lines"
            return
          lines = editor.buffer.getLines()
          colspace = 2
          operations = []
          errors = []
          fields = ['mode', 'nlink', 'user', 'group', 'size', 'date', 'gitstatus', 'name', 'link']
          prot = (a,b,c,fieldname)->
            errors.push "field #{fieldname} is protected"
          for origline,i in origText.split('\n') when origline isnt lines[i]
            if i < 5
              atom.notifications.addError 'You may not change header lines', dismissable:true
              return
            filename = origline.slice origCols.name[i]...
            for k in ks
              if x = layers[k].findMarkers(startBufferRow: i).filter(notEmpty)[0]
                edited = editor.getTextInBufferRange x.getBufferRange()
                current = origline.slice origCols[k][i]...
                if current isnt edited
                  fn = ops[k]
                  fn current, edited, filename, directory, k, errors, operations
          if errors.length
            atom.notifications.addError 'errors detected', detail:errors.join('\n'), dismissable:true
            return
          if operations.length
            # "https://electronjs.org/docs/api/dialog#dialogshowmessageboxbrowserwindow-options"
            message = "Do you want to execute these operations?"
            detail = operations.map(_.first).join('\n')
            buttons = ["Ok", "Cancel"]
            atom.confirm {type:"question", message, buttons, detail}, (cancel)->
              return if cancel
              if await operate operations
                stop()
          else
            console.log "This should not happen"
            stop()
      _commands.add editor.onDidDestroy ->
        _commands.dispose()
        resolve("force")
  'dir-opener:activate-linewise-visual-mode': ({editor})->
    return if editor.getCursorBufferPosition().row < 3
    atom.commands.dispatch editor.element, 'vim-mode-plus:activate-linewise-visual-mode'
  'dir-opener:noop': -> console.log arguments

operate = (operations)->
  for [desc, fn], i in operations
    try
      await fn()
    catch e
      atom.notifications.addError "Operation failed", detail: desc+"\n"+e.message, dismissable: true
      rest = operations.slice(i+1)
      if rest.length
        atom.notifications.addWarning "Not executed", detail: rest.map(_.first).join('\n'), dismissable: true
      return false
  true

ops = {
  mode: (current, mode, file, directory, field, errors, operations)->
    return prot(null, null, null, 'file-format') if current[0] isnt mode[0]
    current = current.slice 1
    mode = mode.slice 1
    for ch, i in "rwxrwxrwx"
      unless mode[i] is '-' or mode[i] is ch
        errors.push "invalid mode #{mode} (file #{file})"
        break
    unless errors.length
      _mode = 0
      for rights,i in _.chunk(mode, 3)
        for flag,j in rights
          _mode |= (1 << (2 - j)) << (3 * (2 - i)) if flag isnt '-'
      oper = ->
        fs.promises.lchmod path.join(directory, file), _mode
      operations.push ["- chmod #{_mode.toString(8)} #{file}", oper]
  user: (current, owner, file, directory, field, errors, operations)->
    if uid = getId futils.users, owner
      p = path.join(directory, file)
      oper = ->
        stat = await fs.promises.lstat(p)
        return await fs.promises.chown path.join(directory, file), uid, stat.gid
      operations.push ["- chown #{owner} #{file}", oper]
    else
      errors.push "#{owner} is not a valid user"
  group: (current, group, file, directory, field, errors, operations)->
    if gid = getId futils.groups, group
      p = path.join(directory, file)
      oper = ->
        stat = await fs.promises.lstat(p)
        return await fs.promises.chown p, stat.uid, gid
      operations.push ["- chgrp #{group} #{file}", oper]
    else
      errors.push "#{group} is not a valid group"
  name: (current, name, file, directory, field, errors, operations)->
    valid = require 'valid-filename'
    newname = path.join(directory, name)
    if fs.existsSync newname
      errors.push "#{name} already exists"
    else if valid(name)
      oper = -> fs.promises.rename path.join(directory, file), newname
      operations.push ["- mv #{file} #{name}", oper]
    else
      errors.push "#{name} is not a valid file name"
}

keyForValue = (m, val)-> return k for [k,v] from m when v is val

getId = (m, val)->
  id = parseInt(val)
  if isNaN(id) then keyForValue(m, val) else m.has(id) and id
