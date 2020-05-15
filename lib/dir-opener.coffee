{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs'
os = require 'os'
assert = require 'assert'
_ = require 'lodash'
{getLengths, getLayers, getFields, leftpad, rightpad, listFiles} = utils = require './utils'
git = require './git'
GitWatch = require './git-watch'
formatEntry = require './format'
PREFIX = 'dir-opener:/'

sleep = (ms)-> new Promise (resolve)-> setTimeout resolve, ms

arrows = "↑↓"
clearMarkers = (editor)->
  for id, layer of editor.buffer.markerLayers when layer.role isnt 'selections'
    layer.clear()

isDir = (name)-> name.endsWith('/')

comparers =
  name: ([a],[b])-> a.localeCompare b
  dirThenName: ([a],[b])-> isDir(b) - isDir(a) or a.localeCompare b

HISTORY_LIMIT = 200

defaultDir = ->
  p = atom.project.getDirectories()[0]
  p?.path ? os.homedir()

fields = ['mode', 'nlink', 'user', 'group', 'size', 'date', 'gitstatus', 'name', 'link']
padding = l: leftpad, r: rightpad
plus = (a,b)-> a + b
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
      if (not e.getPath?()) and e.getTitle() is 'untitled'
        atom.workspace.paneForItem(e)?.destroyItem(e)
        if dir = atom.project.rootDirectories[0]
          atom.workspace.open dir.path + '/'
      setTimeout -> once.dispose()

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.addOpener (uri)=>
      uri = uri.slice PREFIX.length if uri.startsWith PREFIX
      uri = uri.replace '~', os.homedir()
      if uri.endsWith '/..'
        selected = path.resolve uri.slice 0, -3
      uri = path.resolve uri
      try
        return if not fs.statSync(uri).isDirectory()
      catch e
        return
      if editor = atom.workspace.getActivePane().items.find (x)=> @editors.has(x)
        editor.buffer.setPath uri
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
        subscriptions.add editor.onDidChangePath => @scheduleUpdate()
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
            # # TODO: cycle project dirs
            return
          if _path = e?.getPath?()
            # Fool other openers that are extension based
            return atom.workspace.open PREFIX + _path + path.sep + '..'
        atom.workspace.open defaultDir()
  useVimModePlus: (@vmp)->
  scheduleUpdate: ->
    @_timer ?= window.requestAnimationFrame =>
      @_timer = null
      for [editor, estate] from @editors
        p = path.resolve editor.getPath() # drop trailing /
        unless dirstate = @directories.get(p)
          proj = atom.project.getPaths().find (d)-> p.startsWith d
          dirstate = {directory: p, stats: null, proj}
          @directories.set p, dirstate
          @getGitRoot(p)
          checkdir(p, this)
        continue unless stats = dirstate.stats
        return if @_timer? # abort if new update was triggered while waiting
        if _stateChange = stateChanged estate.prevState, stats, @sortOrder, p
          writeStats editor, stats, dirstate.proj, @sortOrder, updateHistory editor, estate
          estate.prevState = {uri:p, @sortOrder, stats}
        if groot = dirstate.gitRoot
          return if @_timer?
          if repo = @repositories.get(groot)
            repo.watch.check() if _stateChange
            writeGitSummary editor, repo
            continue unless status = repo.watch.status
            return if @_timer?
            writeGitStatus editor, status, stats, @sortOrder, groot

  backoff: (dir)->
      for [editor, state] from @editors
        if dir is path.resolve editor.getPath()
          state.history.push editor.getPath()
          editor.buffer.setPath path.dirname dir
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

runCommand = (editor, {directories, repositories, editors, vmp})->
  (f)-> (event)->
    p = path.resolve editor.getPath()
    dir = directories.get(p)
    repo = repositories.get(dir.gitRoot) if dir.gitRoot
    vimState = vmp.getEditorState(editor)
    f event, Object.assign {editor, dir, repo, vimState},
      fileAtCursor:fileAtCursor(editor)
      selected:getSelectedEntries(editor, vimState)

fileAtCursor = (editor)->
  {row} = editor.getCursorBufferPosition()
  return if row < 3
  uri = editor.getPath()
  path.normalize path.join uri, getFields(editor, row, ['name'])[0]

getSelectedEntries = (editor, vimstate)->
  sels = vimstate?.getPersistentSelectionBufferRanges()
  unless sels?.length
    sels = editor.getSelectedBufferRanges()
  a = new Set
  for {start, end} in sels
    for i in [start.row .. end.row - (end.column is 0)] by 1
      a.add _.first getFields editor, i, ['name']
  return Array.from a.values() if a.size
  getFields(editor, sels[0].start.row, ['name'])

stateChanged = (prev = {}, stats, sortOrder, uri)->
  return true if uri isnt prev.uri
  return true if sortOrder isnt prev.sortOrder
  not _.isEqualWith stats, prev.stats, utils.statsEqual

checkdir = (p, pack, watch)->
  try
    assert (await fs.promises.stat p).isDirectory()
    dirstate = pack.directories.get(p)
    dirstate.stats = await utils.getStats(p)
    pack.scheduleUpdate()
    unless watch?
      dirstate.watch = watch = fs.watch p, -> checkdir p, pack, watch
    true
  catch e
    watch?.close()
    pack.directories.delete p
    atom.notifications.addWarning p, detail:e.message, dismissable: true
    pack.backoff p
    false

# updates history, makes sure it does not grow too big
# returns the item that shoud be selected
updateHistory = (editor, state)->
  history = state.history ?= []
  uri = editor.getPath()
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
  return if p isnt editor.getPath() # user has moved on
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

writeGitStatus = (editor, status, stats, sortOrder, root)->
  workdir = path.dirname(root)
  dir = editor.getPath()
  items = Object.entries(stats).sort comparers[sortOrder]
  p = editor.getPath()
  statuses = git.parseStatus status, path.relative workdir, p
  _status = (name)-> statuses[name] ? '  '
  ks = Object.keys(statuses)
  if ks.length is 1 and (ks[0] is '' or ks[0].endsWith path.sep)
    _s = statuses[ks[0]]
    _status = -> _s
  layer = getLayers(editor, ['gitstatus'])[0]
  linkLayer = getLayers(editor, ['link'])[0]
  writeGitStatusPart(editor, _status, layer, linkLayer, _.chunk(items, 50), 5, p)

writeGitStatusPart = (editor, statuses, layer, linkLayer, chunks, i, p)->
  return if editor.getPath() isnt p or chunks.length is 0
  items = chunks.shift()
  for [item] in items
    item = item.slice(0, -1) if item.endsWith path.sep
    row = i++
    if x = layer.findMarkers(startBufferRow: row)?[0]
      ss = statuses item
      s = ss.slice 0, 2
      range = x.getBufferRange()
      oldval = editor.getTextInBufferRange range
      if s isnt oldval
        editor.setTextInBufferRange range, s, bypassReadOnly: true
        if oldval[0] is 'R'
          r = linkLayer.findMarkers(startBufferRow: row)?[0].getBufferRange()
          editor.setTextInBufferRange r, '', bypassReadOnly: true
        else if ss.length > 2
          r = linkLayer.findMarkers(startBufferRow: row)?[0].getBufferRange()
          editor.setTextInBufferRange r, "(was #{ss.slice 2})", bypassReadOnly: true
  editor.buffer.clearUndoStack()
  window.requestAnimationFrame -> writeGitStatusPart(editor, statuses, layer, linkLayer, chunks, i, p)

writeGitSummary = (editor, repo)->
  {hasStaged, hasChanges, balance, branch} = repo.watch
  # return unless hasStaged? or hasChanges or balance or branch
  return unless branch
  if hasStaged
    branch += ' +'
  else if hasChanges
    branch += ' *'
  branch += formatBalance balance
  workdir = path.dirname(repo.root)
  mark editor, [[1, 0], [1, workdir.length]], 'git-root'
  dir = editor.getPath()
  range = editor.buffer.clipRange [[1,dir.length], [1, (editor.buffer.lineForRow 1).length]]
  editor.setTextInBufferRange range, " (#{branch})", bypassReadOnly: true
  editor.buffer.clearUndoStack()

formatBalance = (balance)->
  return '' unless balance
  if balance
    if balance is '0\t0'
      ' u='
    else
      balance = balance.split /\s+/
      if balance[0] is '0'
        ' u+' + balance[1]
      else if balance[1] is '0'
        ' u-' + balance[0]
      else
        ' u+' + balance.reverse().join('-')

writeStats = (editor, stats, proj, sortOrder, selected)->
  items = Object.entries(stats).sort comparers[sortOrder]
  dir = editor.getPath()
  x = items.map formatEntry
  x.unshift formatEntry ['../', fs.lstatSync path.dirname dir]
  x.unshift formatEntry ['./', fs.lstatSync dir]
  lengths = getLengths(x)
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
  editor.setText text, bypassReadOnly: true
  if proj
    mark editor, [[1, 0], [1, proj.length]], 'project'
  selectedRow ?= 4 + (items.length > 0)
  editor.setCursorBufferPosition [selectedRow, 0]
  editor.element.scrollToTop() if selectedRow <= screenHeight(editor)
  editor.buffer.clearUndoStack()
  paintColors editor, _.chunk(x, 300), 3, colspace, editor.getPath()
  return

mark = (editor, range, cls)->
  marker = editor.markBufferRange range, invalidate:'never', exclusive: true
  editor.decorateMarker marker, type:'text', class:cls

screenHeight = (editor)->
  Math.floor editor.element.getHeight() / editor.getLineHeightInPixels()
