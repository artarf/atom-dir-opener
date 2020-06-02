path = require 'path'
fs = require 'fs'
_ = require 'lodash'
valid = require 'valid-filename'
futils = require './file-utils'

module.exports = ({editor, dir})->
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

ops = {
  mode: (current, mode, file, directory, field, errors, operations)->
    return prot(null, null, null, 'file-format') if current[0] isnt mode[0]
    current = current.slice 1
    mode = mode.slice 1
    if err = futils.validateMode(mode)
      errors.push err
    else
      _mode = futils.parseMode mode
      oper = ->
        fs.promises.lchmod path.join(directory, file), _mode
      operations.push ["- chmod #{_mode.toString(8)} #{file}", oper]
  user: (current, owner, file, directory, field, errors, operations)->
    if uid = futils.getUid owner
      p = path.join(directory, file)
      oper = ->
        stat = await fs.promises.lstat(p)
        return await fs.promises.chown path.join(directory, file), uid, stat.gid
      operations.push ["- chown #{owner} #{file}", oper]
    else
      errors.push "#{owner} is not a valid user"
  group: (current, group, file, directory, field, errors, operations)->
    if gid = futils.getGid group
      p = path.join(directory, file)
      oper = ->
        stat = await fs.promises.lstat(p)
        return await fs.promises.chown p, stat.uid, gid
      operations.push ["- chgrp #{group} #{file}", oper]
    else
      errors.push "#{group} is not a valid group"
  name: (current, name, file, directory, field, errors, operations)->
    newname = path.join(directory, name)
    if fs.existsSync newname
      errors.push "#{name} already exists"
    else if valid(name)
      oper = -> fs.promises.rename path.join(directory, file), newname
      operations.push ["- mv #{file} #{name}", oper]
    else
      errors.push "#{name} is not a valid file name"
}
