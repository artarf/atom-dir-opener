{CompositeDisposable} = require 'atom'
path = require 'path'
fs = require 'fs'
_ = require 'lodash'
{getLayers, getFields, leftpad, rightpad, listFiles} = utils = require './utils'
git = require './git'
formatEntry = require './format'

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
  os = require 'os'
  p = atom.project.getDirectories()[0]
  p?.path ? os.homedir()

fields = ['mode', 'nlink', 'user', 'group', 'size', 'date', 'gitstatus', 'name', 'link']
padding = l: leftpad, r: rightpad
plus = (a,b)-> a + b
commands = require './commands'

module.exports = MyPackage =
  subscriptions: null
  editors: new Map
  directories: new Map
  repositories: new Map
  sortOrder: "dirThenName"

  activate: ->
    await require('atom-package-deps').install('my-package')
    keymapFile = path.join path.dirname(__dirname), 'keymaps', 'my-package.cson'
    atom.keymaps.reloadKeymap keymapFile, priority: 1
    once = atom.workspace.observeTextEditors (e)->
      if (not e.getPath?()) and e.getTitle() is 'untitled'
        atom.workspace.paneForItem(e)?.destroyItem(e)
        if dir = atom.project.rootDirectories[0]
          atom.workspace.open dir.path + '/'
      setTimeout -> once.dispose()

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.addOpener (uri)=>
      orig = uri
      return if uri.startsWith 'atom:'
      if uri.endsWith path.sep
        uri = path.resolve uri
        if not fs.statSync(uri).isDirectory()
          selected = uri
          uri = path.dirname(uri) + path.sep
      try
        if uri.endsWith(path.sep) or uri is '~' or fs.statSync(uri).isDirectory()
          unless editor = atom.workspace.getActivePane().items.find (x)=> @editors.has(x)
            editor = require('./create-editor')(uri, fields)
            subscriptions = new CompositeDisposable
            subscriptions.add atom.commands.add editor.element, commands
            subscriptions.add editor.onDidChangePath =>
              @editors.get(editor).gitStatus = null
              @scheduleUpdate()
            subscriptions.add editor.onDidDestroy =>
              subscriptions.dispose()
              @editors.delete editor
            @scheduleUpdate()
            history = [selected] if selected?
            uri = stats = gitStatus = null
            @editors.set editor, {subscriptions, uri, stats, gitStatus, history}
      catch e
        console.error e.stack
      editor
    if atom.textEditors.editors.size is 0
      if dir = atom.project.rootDirectories[0]
        atom.workspace.open dir.path + '/'

    @subscriptions.add atom.commands.add 'atom-workspace',
      'my-package:open-directory': =>
        if e = atom.workspace.getActivePaneItem()
          if @editors.has(e)
            # # TODO: cycle project dirs
            return
          if _path = e?.getPath?()
            return atom.workspace.open _path + path.sep
        atom.workspace.open defaultDir()
  useVimModePlus: (vmp)->
  scheduleUpdate: ->
    @_timer ?= window.requestAnimationFrame =>
      @_timer = null
      for [editor, state] from @editors
        p = editor.getPath()
        dirState = @directories.get(path.resolve p)
        if dirState?.stats
          sortChanged = @sortOrder isnt state.sortOrder
          uriChanged = state.uri isnt p
          if sortChanged or uriChanged or dirState.stats isnt state.stats
            state.sortOrder = @sortOrder
            state.stats = dirState.stats
            if statsChanged = writeStats editor, dirState.stats, @sortOrder, updateHistory editor, state
              state.gitStatus = null
              @scheduleUpdate()
          else if dirState.gitRoot
            if repo = @repositories.get dirState.gitRoot
              if statsChanged or sortChanged or uriChanged or repo.status isnt state.gitStatus
                state.gitStatus = repo.status
                writeGitStatus editor, repo.status, state.stats, @sortOrder, dirState.gitRoot
        else
          @fetchDir p
          @fetchGit p
  fetchDir: (dir)->
    return if @directories.get(path.resolve dir)?.stats?
    try
      if stats = await utils.getStats(dir)
        watch = @directories.get(path.resolve dir)?.watch ? fs.watch dir, (type, file)=>
          watch.close()
          p = path.resolve dir
          if x = @directories.get(p).gitRoot
            @reloadGit x
          @directories.delete p
          @scheduleUpdate()
        @directories.set path.resolve(dir), {stats, watch}
        @scheduleUpdate()
    catch e # revert editors with failing dir
      console.error e.message
      for [editor, state] from @editors
        if dir is editor.getPath()
          state.history.push dir
          editor.buffer.setPath path.dirname dir
  fetchGit: (dir)->
    if dirstate = @directories.get(path.resolve dir)
      if root = await git.safe git.root dir
        root = root.stdout.trim()
        root = path.normalize root
        dirstate.gitRoot = root
        @fetchGitRoot(root)
      else
        dirstate.gitRoot = null
    else
      window.requestAnimationFrame => @fetchGit(dir)

  reloadGit: (root)->
    @gitraf = null
    return unless repo = @repositories.get(root)
    repo.watch?.close()
    @repositories.delete root
    @fetchGitRoot(root)

  fetchGitRoot: (root)->
    return @scheduleUpdate() if @repositories.get(root)
    workdir = path.dirname root
    if status = await git.safe git.status workdir
      @repositories.set root, tmp = {root, status: status.stdout}
      @scheduleUpdate()
      # getting status causes index recreate after the command has returned
      # => start watching after a short break
      await sleep 100
      # fetchGitRoot might have been called again during the break
      if @repositories.get(root) is tmp
        tmp.watch = fs.watch path.join(root, 'index'), (type, filename)=>
          @gitraf ?= window.requestAnimationFrame => @reloadGit root
    else
      console.error git.lastError
  deactivate: ->
    @subscriptions?.dispose()
    subscriptions.dispose() for [_, {subscriptions}] from @editors
    @editors.clear()
    for [root, x] from @directories
      x.watch?.close()
    @directories.clear()
    for [root, x] from @repositories
      x.watch?.close()
    @repositories.clear()

# updates history, makes sure it does not grow too big
# returns the item that shoud be selected
updateHistory = (editor, state)->
  history = state.history ?= []
  uri = editor.getPath()
  {row} = editor.getCursorBufferPosition()
  if row > 0
    if name = getFields editor, row, ['name']
      selected = name[0]
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
  branch = git.parseBranch status
  dir = editor.buffer.lineForRow 0
  range = editor.buffer.clipRange [[0,0], [0, dir.length]]
  editor.setTextInBufferRange range, "#{dir} (#{branch})", bypassReadOnly: true
  items = Object.entries(stats).sort comparers[sortOrder]
  status = git.parseStatus status
  p = editor.getPath()
  relPath = p.slice (path.dirname root).length + p.endsWith(path.sep)
  relPath = relPath.slice(0, -1) if relPath.endsWith path.sep
  relPath = relPath or "."
  return unless statuses = status[relPath]
  layer = getLayers(editor, ['gitstatus'])[0]
  for [item], i in items
    item = item.slice(0, -1) if item.endsWith path.sep
    if x = layer.findMarkers(startBufferRow: i + 3)?[0]
      s = statuses[item] ? '  '
      range = x.getBufferRange()
      if s isnt editor.getTextInBufferRange range
        editor.setTextInBufferRange x.getBufferRange(), s, bypassReadOnly: true

writeStats = (editor, stats, sortOrder, selected)->
  items = Object.entries(stats).sort comparers[sortOrder]
  dir = editor.getPath()
  dot = ['./', fs.lstatSync dir]
  dotdot = ['../', fs.lstatSync path.dirname dir]
  x = items.map formatEntry
  x.unshift formatEntry(dot), formatEntry(dotdot)
  lengths = []
  for row in x
    for cell,i in row
      lengths[i] = Math.max cell.length, lengths[i] ? 0
  colspace = 2
  for row, i in x
    name = row[row.length - 2]
    name = name.slice(0, -1) if name.endsWith path.sep
    selectedRow = i+1 if selected is name
    for d,j in 'rlrrll'
      row[j] = padding[d](row[j], lengths[j])
  f = (row)-> row.join(' '.repeat colspace) + '\n'
  text = dir + '\n' + x.map(f).join('')
  return false if text is editor.buffer.getText()
  clearMarkers(editor)
  editor.setText text, bypassReadOnly: true
  selectedRow ?= 2 + (items.length > 0)
  editor.setCursorBufferPosition [selectedRow, 0]
  editor.element.scrollToTop() if selectedRow <= screenHeight(editor)
  paintColors editor, _.chunk(x, 300), 1, colspace, editor.getPath()
  return true

screenHeight = (editor)->
  Math.floor editor.element.getHeight() / editor.getLineHeightInPixels()
