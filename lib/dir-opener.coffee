{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs'
os = require 'os'
assert = require 'assert'
_ = require 'lodash'
utils = require './file-utils'
{getFields, getLayers, deleteMarkers} = require './atom-utils'
git = require './git'
GitWatch = require './git-watch'
format = require './format'
PREFIX = 'dir-opener:/'

sleep = (ms)-> new Promise (resolve)-> setTimeout resolve, ms

arrows = "↑↓"
clearMarkers = (editor)->
  for id, layer of editor.buffer.markerLayers when layer.role isnt 'selections'
    layer.clear()

comparers =
  name: ([a],[b])-> a.localeCompare b
  dirThenName: ([a],[b])-> b.endsWith('/') - a.endsWith('/') or a.localeCompare b

HISTORY_LIMIT = 200

defaultDir = ->
  p = atom.project.getDirectories()[0]
  p?.path ? os.homedir()

fields = ['mode', 'nlink', 'user', 'group', 'size', 'date', 'gitstatus', 'name', 'link']
padding = l: utils.leftpad, r: utils.rightpad
commands = require './commands'

module.exports =
  subscriptions: null
  editors: new Map
  directories: new Map
  repositories: new Map
  sortOrder: "dirThenName"

  activate: ->
    await require('atom-package-deps').install('dir-opener')
    keymapFile = path.join path.dirname(__dirname), 'keymaps', 'dir-opener.cson'
    atom.keymaps.reloadKeymap keymapFile, priority: 1
    once = atom.workspace.observeTextEditors (e)->
      if (not e.getDirectoryPath?()) and e.getTitle() is 'untitled'
        atom.workspace.paneForItem(e)?.destroyItem(e)
        if dir = atom.project.rootDirectories[0]
          atom.workspace.open dir.path + '/'
      setTimeout -> once.dispose()

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.observeTextEditors (e)->
      return unless e.constructor.name is 'DirectoryView'
      if tab = getTab(e)
        tab.classList.add('icon','icon-file-directory')
    @subscriptions.add atom.workspace.addOpener (uri)=>
      uri = uri.slice PREFIX.length if uri.startsWith PREFIX
      uri = uri.replace '~', os.homedir()
      if uri.endsWith '/..'
        selected = path.resolve uri.slice 0, -3
      uri = path.resolve uri
      try
        return if not utils.pointsToDirectorySync(uri)
      catch e
        return
      if editor = atom.workspace.getActivePane().items.find (x)=> @editors.has(x)
        editor.setPath uri
        if selected
          dirstate = @directories.get(uri)
          items = Object.entries(dirstate.stats).sort comparers[@sortOrder]
          i = items.findIndex ([name])=> name is path.basename selected
          if i > -1
            editor.setCursorBufferPosition [i + 5, 0]
      else
        editor = require('./create-editor')(uri, fields)
        subscriptions = new CompositeDisposable
        subscriptions.add atom.commands.add editor.element, _.mapValues commands, runCommand(editor, this)
        subscriptions.add editor.onDidChangeTitle => @scheduleUpdate()
        subscriptions.add editor.onDidDestroy =>
          subscriptions.dispose()
          @editors.delete editor
        @scheduleUpdate()
        history = [selected] if selected?
        @editors.set editor, {subscriptions, history}
      editor
    if atom.textEditors.editors.size is 0
      if dir = atom.project.rootDirectories[0]
        atom.workspace.open PREFIX + dir.path + '/'

    @subscriptions.add atom.commands.add 'atom-workspace',
      'dir-opener:open-directory': =>
        if e = atom.workspace.getActivePaneItem()
          if @editors.has(e)
            # cycle projects roots
            # - if somewhere below root -> select root
            # - if dir is a root -> select next root
            paths = atom.project.getPaths()
            return if paths.length < 1
            p = e.getDirectoryPath()
            i = paths.findIndex (pp)-> p.startsWith pp
            e.setPath paths[i + (p is paths[i])] ? paths[0]
            e.element.focus()
            return
          if _path = e?.getPath?()
            # Fool other openers that are extension based
            return atom.workspace.open PREFIX + _path + path.sep + '..'
        atom.workspace.open defaultDir()
    @subscriptions.add atom.project.onDidChangePaths => @scheduleUpdate()
  useVimModePlus: (@vmp)->
  scheduleUpdate: ->
    window.cancelAnimationFrame @_timer
    @_timer = window.requestAnimationFrame => @update()
  update: ->
    if true
      @_timer = null
      for [editor, estate] from @editors
        p = path.resolve editor.getDirectoryPath() # drop trailing /
        unless dirstate = @directories.get(p)
          dirstate = {directory: p, stats: null}
          @directories.set p, dirstate
          @getGitRoot(p)
          checkdir(p, this)
        continue unless stats = dirstate.stats
        prev = estate.prevState
        proj = atom.project.getPaths().find (d)-> p.startsWith d
        if estate.stats isnt prev?.stats or p isnt prev?.uri or sortOrder isnt @sortOrder or proj isnt prev?.proj
          writeStats editor, stats, proj, @sortOrder, estate.uri, updateHistory editor, estate
          estate.prevState = {uri:p, @sortOrder, stats, proj}
        if groot = dirstate.gitRoot
          if repo = @repositories.get(groot)
            writeGitSummary editor, repo
            status = repo.watch.status
            continue unless status?
            unless getTab(editor)
              @scheduleUpdate()
              continue
            writeGitStatus editor, status, stats, @sortOrder, groot
        else
          setTabIconColor(editor, null)

  backoff: (dir)->
      for [editor, state] from @editors
        if dir is path.resolve editor.getDirectoryPath()
          state.history.push editor.getDirectoryPath()
          editor.setPath path.dirname dir
      @scheduleUpdate()

  getGitRoot: (dir)->
    if root = await git.safe git.root dir
      root = root.stdout.trim()
      root = path.normalize root
      # dirstate does not exist if there was an error opening it
      return unless dirstate = @directories.get(dir)
      dirstate.gitRoot = root
      if not @repositories.has root
        @repositories.set root, {root, watch: new GitWatch root, @scheduleUpdate.bind(this)}

  deactivate: ->
    @subscriptions?.dispose()
    subscriptions.dispose() for [_, {subscriptions}] from @editors
    @editors.clear()
    for [root, x] from @directories
      x.watch?.close()
    @directories.clear()
    for [root, x] from @repositories
      x.watch.dispose()
    @repositories.clear()

notEmpty = (marker)-> not marker.getBufferRange().isEmpty()
runCommand = (editor, {directories, repositories, editors, vmp})->
  pack = arguments[1]
  (f)-> (event)->
    {history} = pack.editors.get(editor)
    p = path.resolve editor.getDirectoryPath()
    return unless dir = directories.get(p)
    repo = repositories.get(dir.gitRoot) if dir.gitRoot
    vimState = vmp.getEditorState(editor)
    selectedRows = getSelectedRows(editor, vimState)
    fileAtCursor = _fileAtCursor(editor)
    layer = getLayers(editor, ['name'])['name']
    selected = selectedRows.map (row)->
      if marker = layer.findMarkers(startBufferRow: row).filter(notEmpty)[0]
        editor.getTextInBufferRange marker.getBufferRange()
    selected = _.filter selected
    try
      upd = await f {event, editor, dir, repo, vimState, selectedRows, selected, fileAtCursor, history}
    catch e
      console.log event, dir, repo, fileAtCursor
      console.error e
    if upd is 'dir'
      checkdir p, pack, "do not create new watch"
    else if upd is 'force'
      pack.scheduleUpdate()

_fileAtCursor = (editor)->
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  uri = editor.getDirectoryPath()
  path.normalize path.join uri, getFields(editor, row, ['name'])[0]

getSelectedRows = (editor, vimstate)->
  sels = vimstate?.getPersistentSelectionBufferRanges()
  unless sels?.length
    sels = editor.getSelectedBufferRanges()
  a = new Set
  for {start, end} in sels
    for i in [start.row .. end.row - (end.column is 0)] by 1
      a.add i
  a.add sels[0].start.row if a.size is 0
  Array.from(a).sort()

checkdir = (p, pack, watch)->
  try
    assert utils.pointsToDirectorySync(p)
    dirstate = pack.directories.get(p)
    stats = await utils.getStats(p)
    unless _.isEqualWith stats, dirstate.stats, utils.statsEqual
      dirstate.stats = stats
      if dirstate.gitRoot and repo = pack.repositories.get(dirstate.gitRoot)
        repo.watch.scheduleCheck()
      pack.scheduleUpdate()
    unless watch?
      dirstate.watch = watch = fs.watch p, -> checkdir p, pack, watch
  catch e
    watch?.close?()
    pack.directories.delete p
    atom.notifications.addWarning p, detail:e.message, dismissable: true
    pack.backoff p
  return

# updates history, makes sure it does not grow too big
# returns the item that shoud be selected
updateHistory = (editor, state)->
  history = state.history ?= []
  uri = editor.getDirectoryPath()
  {row} = editor.getCursorBufferPosition()
  if row > 0
    if name = getFields editor, row, ['name']
      selected = name[0]
      selected = selected.slice 0, -1 if selected.endsWith path.sep
  if uri is state.uri
    # only updating changed file system => keep current selected item
    selected
  else
    # dir changed => get selected from history and add current to history
    if history.length > 2 * HISTORY_LIMIT
      history = history.slice -(HISTORY_LIMIT)

    selected = path.join state.uri, selected if row > 0
    selected ?= state.uri
    history.push selected if selected and _.last(history) isnt selected
    state.uri = uri

    for _uri in history.slice().reverse()
      if _uri.startsWith(uri) and _uri.length > uri.length
        a = _uri.slice(uri.length)
        if a.startsWith(path.sep) or uri.endsWith(path.sep)
          return a.replace(/^\//, '').split(path.sep)[0]

paintColors = (editor, chunks, startRow, colspace, p)->
  return unless x = chunks.shift()
  return if p isnt editor.getDirectoryPath() # user has moved on
  for row, i in x
    r = startRow + i
    start = 0
    layers = _.keyBy Object.values(editor.buffer.markerLayers), 'role'
    for field, j in fields
      end = start + x[i][j].length
      range = editor.buffer.clipRange {start: [r, start], end: [r, end]}
      layers[field].markRange range, exclusive: false, invalidate: 'never'
      start = end + colspace
    [..., name, link] = x[i]
    rowClasses = []
    if link
      rowClasses.push 'link-to-directory' if link.endsWith '/'
    else if name.endsWith '/'
      rowClasses.push 'directory'
    else if x[i][0].includes 'x'
      rowClasses.push 'executable'
    if rowClasses.length
      range = editor.buffer.clipRange {start: [r, 0], end: [r, start]}
      marker = editor.markBufferRange range, exclusive: false
      editor.decorateMarker marker, type:'line', class: rowClasses.join ' '
  window.requestAnimationFrame -> paintColors editor, chunks, startRow + 300, colspace, p

IGNORED = 'status-ignored-icon'
STAGED = 'status-staged-icon'
CHANGES = 'status-modified-icon'
UNTRACKED = 'status-untracked-icon'

getTab = (dirview)->
  return unless pane = atom.workspace.paneForItem(dirview)
  i = pane.items.findIndex (x)-> x is dirview
  return if i < 0
  bar = pane.element.querySelector('.tab-bar')
  bar.childNodes[i].firstChild

setTabIconColor = (editor, cls)->
  return unless tab = getTab(editor)
  tab?.classList.remove CHANGES, IGNORED, STAGED, UNTRACKED
  tab.classList.add cls if cls?

writeGitStatus = (editor, status, stats, sortOrder, root)->
  workdir = path.dirname(root)
  dir = editor.getDirectoryPath()
  statuses = git.parseStatus status, path.relative workdir, dir
  statusValues = Object.values(statuses)
  summary = statusValues.reduce git.mergeStatus, '  '
  cls = switch summary
    when '  ' then break;
    when '!!'
      # tricky: when we are inside ignored directory statuses is
      # {"": "!!"} or like {"some/thing/": "!!"}
      if statusValues.length is 1
        k = Object.keys(statuses)[0]
        IGNORED if k is "" or k.endsWith path.sep
    when '??' then UNTRACKED
    else
      if '?! '.includes(summary[0]) then CHANGES else STAGED
  setTabIconColor editor, cls
  _stats = Object.entries(stats)
  for name, s of statuses when s[0] is 'D' or s[1] is 'D'
    _stats.push [name]
  items = _stats.sort comparers[sortOrder]
  _status = (name)-> statuses[name] ? '  '
  ks = Object.keys(statuses)
  if ks.length is 1 and (ks[0] is '' or ks[0].endsWith path.sep)
    _s = statuses[ks[0]]
    _status = -> _s
  layers = getLayers editor, 'gitstatus,link,name,mode'.split ','
  writeGitStatusPart(editor, _status, layers, _.chunk(items, 50), 5, dir)

writeGitStatusPart = (editor, statuses, layers, chunks, i, p)->
  return if editor.getDirectoryPath() isnt p or chunks.length is 0
  items = chunks.shift()
  for [item, stats] in items
    item = item.slice(0, -1) if item.endsWith path.sep
    row = i++
    if x = layers.gitstatus.findMarkers(startBufferRow: row)?[0]
      ss = statuses item
      s = ss.slice 0, 2
      range = x.getBufferRange()
      oldval = editor.getTextInBufferRange range
      if stats? and editor.buffer.lineForRow(row)[0] is ' '
        # row for deleted file must be deleted
        deleteMarkers(editor, row, fields)
        editor.setTextInBufferRange [[row, 0],[row + 1, 0]], '', bypassReadOnly: true
      if not stats?
        x = layers.name.findMarkers(startBufferRow: row)[0]
        name = editor.getTextInBufferRange x.getBufferRange()
        if item isnt name
          insertRow(row++, item, statuses, layers, editor)
        else if s isnt oldval
          editor.setTextInBufferRange range, s, bypassReadOnly: true
      else if s isnt oldval
        editor.setTextInBufferRange range, s, bypassReadOnly: true
        if oldval[0] is 'R'
          r = layers.link.findMarkers(startBufferRow: row)?[0].getBufferRange()
          editor.setTextInBufferRange r, '', bypassReadOnly: true
        else if ss.length > 2
          r = layers.link.findMarkers(startBufferRow: row)?[0].getBufferRange()
          editor.setTextInBufferRange r, "(was #{ss.slice 2})", bypassReadOnly: true
    else
      insertRow(row++, item, statuses, layers, editor)
  editor.buffer.clearUndoStack()
  window.requestAnimationFrame -> writeGitStatusPart(editor, statuses, layers, chunks, i, p)

insertRow = (row, item, statuses, layers, editor)->
  ss = statuses item
  s = ss.slice 0, 2
  statusCol = layers.gitstatus.findMarkers(startBufferRow: 3)[0].getBufferRange().start.column
  nameCol = statusCol + 4
  modex = layers.mode.findMarkers(startBufferRow: row)[0]
  modexRange = modex.getBufferRange().translate [1,0] if modex
  # insert new row
  text = ' '.repeat(statusCol)
  text += s + '  '
  text += item + '\n'
  statusRange = {start:[row, statusCol], end:[row, statusCol + 2]}
  nameRange = {start:[row, nameCol], end:[row, nameCol + text.length]}
  editor.setTextInBufferRange [[row, 0], [row, 0]], text, bypassReadOnly: true
  modex.setBufferRange modexRange if modex
  layers.gitstatus.markBufferRange statusRange, exclusive: false, invalidate: 'never'
  layers.name.markBufferRange nameRange, exclusive: false, invalidate: 'never'

writeGitSummary = (editor, repo)->
  {hasStaged, hasChanges, balance, branch} = repo.watch
  # return unless hasStaged? or hasChanges or balance or branch
  return unless branch
  if hasStaged
    branch += ' +'
  else if hasChanges
    branch += ' *'
  branch += format.balance balance
  workdir = path.dirname(repo.root)
  mark editor, [[1, 0], [1, workdir.length]], 'git-root'
  dir = editor.getDirectoryPath()
  range = editor.buffer.clipRange [[1,dir.length], [1, (editor.buffer.lineForRow 1).length]]
  editor.setTextInBufferRange range, " (#{branch})", bypassReadOnly: true
  editor.buffer.clearUndoStack()

writeStats = (editor, stats, proj, sortOrder, prevUri, selected)->
  items = Object.entries(stats).sort comparers[sortOrder]
  dir = editor.getDirectoryPath()
  x = items.map format.statsRow
  x.unshift format.statsRow ['../', fs.lstatSync path.dirname dir]
  x.unshift format.statsRow ['./', fs.lstatSync dir]
  lengths = utils.getLengths(x)
  colspace = 2
  for row, i in x
    name = row[row.length - 2]
    name = name.slice(0, -1) if name.endsWith path.sep
    selectedRow = i+3 if selected is name
    for d,j in 'rlrrll'
      row[j] = padding[d](row[j], lengths[j])
  f = (row)-> row.join(' '.repeat colspace) + '\n'
  text = '\n' + dir + '\n\n' + x.map(f).join('')
  clearMarkers(editor)
  if not selectedRow? and dir is prevUri
    selectedRow = editor.getCursorBufferPosition().row
    selectedRow = Math.min selectedRow, 4 + items.length
  editor.setText text, bypassReadOnly: true
  if proj
    mark editor, [[1, 0], [1, proj.length]], 'project'
  selectedRow ?= 4 + (items.length > 0)
  editor.setCursorBufferPosition [selectedRow, 0]
  editor.element.scrollToTop() if selectedRow <= editor.getRowsPerPage() - 1
  editor.buffer.clearUndoStack()
  paintColors editor, _.chunk(x, 300), 3, colspace, editor.getDirectoryPath()
  return

mark = (editor, range, cls)->
  marker = editor.markBufferRange range, invalidate:'never', exclusive: true
  editor.decorateMarker marker, type:'text', class:cls
