path = require 'path'
fs = require 'fs'
_ = require 'lodash'
valid = require 'valid-filename'
futils = require './file-utils'

module.exports = ({editor, dir, vimState})->
  {directory} = dir
  origText = editor.getText()
  headerRange = [[0,0],[5,0]]
  origHeader = editor.getTextInBufferRange headerRange
  layers = Array.from editor.displayLayer.displayMarkerLayersById.values()
  layers = _.keyBy layers, 'bufferMarkerLayer.role'
  origCols = getRanges(layers)
  # move cursor to start of file name of current row
  namecol = origCols.name[3][0]
  {row} = editor.getCursorBufferPosition()
  editor.setCursorBufferPosition [row, namecol]
  lc = editor.getLineCount()
  save = ->
        lines = editor.buffer.getLines()
        colspace = 2
        operations = []
        errors = []
        for origline,i in origText.split('\n') when origline isnt lines[i]
          filename = origline.slice origCols.name[i]...
          for k in Object.keys(origCols)
            if x = layers[k].findMarkers(startBufferRow: i).filter(notEmpty)[0]
              edited = editor.getTextInBufferRange x.getBufferRange()
              current = origline.slice origCols[k][i]...
              if current isnt edited
                if err = validate[k](edited, directory, current, filename)
                  errors.push err
                else if errors.length is 0
                  operations.push [ops[k], edited, filename]
        if errors.length
          atom.notifications.addError 'errors detected', detail:errors.join('\n'), dismissable:true
          return false
        if operations.length
          operations = operations.map ([fn, edited, filename])->
            fn edited, filename, directory
          # "https://electronjs.org/docs/api/dialog#dialogshowmessageboxbrowserwindow-options"
          message = "Do you want to execute these operations?"
          detail = operations.map(_.first).join('\n')
          buttons = ["Ok", "Cancel"]
          new Promise (resolve)->
            atom.confirm {type:"question", message, buttons, detail}, (cancel)->
              resolve false if cancel
              resolve await operate operations
        else
          console.log "This should not happen"
          return true
  validator = ({changes})->
    if changes.some (c)-> c.oldRange.start.row < 5
      if origHeader isnt editor.getTextInBufferRange headerRange
        return "Header may not be changed."
    if lc isnt editor.getLineCount()
      return "Don't add or delete lines"
  editor.editMode {cls:'dir-opener-edit', validator, save, vimState}

notEmpty = (marker)-> not marker.getBufferRange().isEmpty()

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

validate = {
  mode: (mode, _, current, file)->
    return "field file-format is protected" if current[0] isnt mode[0]
    futils.validateMode mode.slice(1), file
  user: (user)-> if not futils.getUid(user) then "#{owner} is not a valid user"
  group: (group)-> if not futils.getGid(group) then "#{group} is not a valid group"
  name: (name, directory, current)->
    if fs.existsSync path.join(directory, name) and name.toLowerCase() isnt current.toLowerCase()
      "#{name} already exists"
    else if not valid(name)
      "#{name} is not a valid file name"
}

ops = {
  mode: (mode, file, directory)->
    mode = futils.parseMode mode.slice 1
    [
      "- chmod #{mode.toString(8)} #{file}"
      -> fs.promises.lchmod path.join(directory, file), mode
    ]
  user: (owner, file, directory)->
    uid = futils.getUid owner
    p = path.join(directory, file)
    oper = ->
      stat = await fs.promises.lstat(p)
      return await fs.promises.chown p, uid, stat.gid
    ["- chown #{owner} #{file}", oper]
  group: (group, file, directory)->
    gid = futils.getGid group
    p = path.join(directory, file)
    oper = ->
      stat = await fs.promises.lstat(p)
      return await fs.promises.chown p, stat.uid, gid
    ["- chgrp #{group} #{file}", oper]
  name: (name, file, directory)-> [
      "- mv #{file} #{name}"
      -> fs.promises.rename path.join(directory, file), path.join(directory, name)
    ]
}

getRanges = (layers)->
  origCols = {}
  for k in ['mode', 'user', 'group', 'name']
    origCols[k] = x = []
    for m in layers[k].getMarkers()
      r = m.getBufferRange()
      if not r.isEmpty()
        x[r.start.row] = [r.start.column, r.end.column]
  origCols
