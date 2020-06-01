{TextEditor, TextBuffer} = require 'atom'
module.exports = (uri)->
  return unless uri.startsWith 'asar://'
  file = uri.slice(7).replace(/\/\/\.\.$/, '')
  opts =
    buffer: new TextBuffer
    readOnly: true
    autoHeight: false
  opts.buffer.setPath file
  require('fs').readFile file, 'utf8', (err, text)->
    return console.error err if err
    megabyte = 1024 * 1024
    if text.length > megabyte
      atom.notifications.addWarning "File too big (#{text.length}). Truncated to 1Mb."
      opts.buffer.setText text.slice(0,megabyte)
    else
      opts.buffer.setText text
    editor.setCursorBufferPosition([0,0])
    editor.scrollToTop()
  setTimeout (-> editor.element.focus()), 100
  editor = Object.assign new TextEditor(opts), {isModified: -> false}
