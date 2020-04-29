fs = require 'fs'
_fs = fs.promises
path = require 'path'
formatEntry = require './format'
{leftpad, rightpad, listFiles} = require './utils'

fields = ['mode', 'nlink', 'user', 'group', 'size', 'date']
padding = l: leftpad, r: rightpad
plus = (a,b)-> a + b

append = (e, text, opts)->
  p = e.buffer.getEndPosition()
  e.setTextInBufferRange({start: p, end: p}, text, opts)

clearMarkers = (pkg)->
  for field in fields.concat ['link', 'directory', 'filename']
    for m in pkg[field].getMarkers()
      m.destroy()

paintColors = (editor, x, startRow, lengths, colspace)->
  {entries} = editor._myPackage
  for row, i in x
    r = startRow + i
    start = 0
    for field, j in fields
      end = start + lengths[j]
      range = editor.buffer.clipRange {start: [r, start], end: [r, end]}
      editor._myPackage[field].markRange range, exclusive: true
      start = end + colspace
    [_, stats] = entries[i]
    start = 6 * colspace + lengths.slice(0, 6).reduce plus, 0
    end = start + x[i][6].length
    range = editor.buffer.clipRange {start: [r, start], end: [r, end]}
    {directory, link, filename} = editor._myPackage
    if stats.isDirectory()
      directory.markRange range, exclusive: true
    else if stats.isSymbolicLink()
      if row[row.length - 1].endsWith '/'
        linkrange = editor.buffer.clipRange {start: [r, end + 5], end: [r, 999]}
        directory.markRange linkrange, exclusive: true
      link.markRange range, exclusive: true
    else
      filename.markRange range, exclusive: true

getStats = (p)->
  stat = await _fs.lstat p
  return [path.basename(p), stat] unless stat.isSymbolicLink()
  link = await _fs.readlink(p)
  try
    followed = await _fs.stat(p)
    link += '/' if followed.isDirectory() and not link.endsWith '/'
    [path.basename(p), stat, link]
  catch e
    # Exception thrown when link target does not exist
    [path.basename(p), stat, link]

readDir = (uri)->
  try
    entries = await listFiles uri, true
    entries = entries.map (e)-> path.join uri, e
    await Promise.all entries.map (e)-> await getStats e
  catch e
    console.error e.stack
    atom.notifications.addError e.message, dismissable: true
    return

isDir = ([_, stats, link])-> stats.isDirectory() or (link?.endsWith('/') ? false)

module.exports = (editor, uri, force = false)->
  {_myPackage} = editor
  if uri.endsWith '/'
    uri = path.resolve uri
    unless fs.statSync(uri).isDirectory()
      _myPackage.uri = uri
      uri = path.dirname uri
  return if _myPackage.uri is uri and force is false
  origrow = editor.getCursorBufferPosition().row
  return unless entries = await readDir uri
  entries.sort (a,b)-> isDir(b) - isDir(a) or a[0].localeCompare b[0]
  entries.unshift (await getStats uri), (await getStats path.dirname uri)
  entries[0][0] = "."
  entries[1][0] = ".."
  _myPackage.entries = entries
  clearMarkers(_myPackage)
  editor.setText uri + '\n', bypassReadOnly: true
  x = await Promise.all entries.map formatEntry
  lengths = []
  for row in x
    for cell,i in row
      lengths[i] = Math.max cell.length, lengths[i] ? 0
  colspace = 2
  for row, i in x
    for d,j in 'rlrrll'
      row[j] = padding[d](row[j], lengths[j])
  f = (row)-> row.join(' '.repeat colspace).trimEnd() + '\n'
  startRow = editor.buffer.getRange().end.row
  append editor, x.map(f).join(''), bypassReadOnly: true

  if _myPackage.uri is uri
    row = origrow
  else if _myPackage.uri.startsWith uri
    current = _myPackage.uri.slice uri.length
    current = current.split(path.sep).find (x)-> x
    row = 1 + entries.findIndex ([name])-> name is current
    row = Math.min(x.length, 3) if row is 0
  else
    row = Math.min(x.length, 3)
  editor.setCursorBufferPosition {row, column: 0}
  if row < 22
    editor.scrollToBufferPosition row:0, column: 0
  setTimeout paintColors, 5, editor, x, startRow, lengths, colspace
  _myPackage.uri = uri
  editor.emitter.emit('did-change-title')
  return

module.exports.fields = fields
