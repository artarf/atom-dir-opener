path = require 'path'
fs = require 'fs'
valid = require 'valid-filename'

module.exports = ({editor, dir, vimState})->
  {directory} = dir
  headerRange = [[0,0],[5,0]]
  origHeader = editor.getTextInBufferRange headerRange
  for layer from editor.displayLayer.displayMarkerLayersById.values()
    nameLayer = layer if layer.bufferMarkerLayer.role is 'name'
    modeLayer = layer if layer.bufferMarkerLayer.role is 'mode'
    break if nameLayer and modeLayer
  namecol = nameLayer.getMarkers()[0].getBufferRange().start.column
  {row} = editor.getCursorBufferPosition()
  row++
  p = [row, 0]
  indent = ' '.repeat(namecol)
  orig0 = editor.getTextInBufferRange(start:[0,0], end:p) + indent
  orig1 = editor.getTextInBufferRange {start:p, end:editor.buffer.getEndPosition()}
  editor.setTextInBufferRange [[row, 0],[row, 0]], indent + '\n', bypassReadOnly: true
  editor.setCursorBufferPosition [row, namecol]
  vimState.activate "insert"
  lc = editor.getLineCount()
  editor.editMode
    cls:'dir-opener-insert'
    save: ->
      newname = editor.buffer.lineForRow(row).slice(namecol)
      _path = []
      if newname.includes path.sep
        [_path..., newname] = newname.split path.sep
      if err = validate directory, _path, newname
        atom.notifications.addError err
        return false
      try
        p = path.join(directory, _path...)
        await fs.promises.mkdir p, recursive:true if _path.length
        fd = await fs.promises.open path.join(p, newname), fs.constants.O_CREAT
        await fd.close()
        return true
      catch err
        atom.notifications.addError err.message, detail:err.stack, dismissable:true
        return false
    vimState:vimState
    validator: ({changes})->
      if lc isnt editor.getLineCount() or
          orig0 isnt editor.getTextInBufferRange {start:[0,0], end:[row, namecol]} or
          orig1 isnt editor.getTextInBufferRange {start:[row+1, 0], end:editor.buffer.getEndPosition()}
        return "You must edit just the name"


validate = (directory, p, name)->
  if not p.every valid
    "Path to file is not valid: #{p.join path.sep}"
  else if not name
    "Empty name"
  else if fs.existsSync path.join(directory, name)
    "#{name} already exists"
  else if not valid(name)
    "#{name} is not a valid file name"
