_ = require 'lodash'

mFilter = (m, pred)-> val for val from m.values() when pred(val)

_getLayers = (editor, roles)->
  mFilter editor.displayLayer.displayMarkerLayersById, (x)-> roles.includes x.bufferMarkerLayer.role

getLayers = (editor, roles)->
  _.keyBy _getLayers(editor, roles), 'bufferMarkerLayer.role'

notEmpty = (marker)-> not marker.getBufferRange().isEmpty()

getFields = (editor, row, roles)->
  layers = _.keyBy _getLayers(editor, roles), 'bufferMarkerLayer.role'
  roles.map (role)->
    unless x = layers[role]?.findMarkers(startBufferRow: row).filter(notEmpty)[0]
      return ""
    editor.getTextInBufferRange x.getBufferRange()

deleteMarkers = (editor, row, roles)->
  editor.displayLayer.displayMarkerLayersById.forEach (layer)->
    if roles.includes layer.bufferMarkerLayer.role
      marker.destroy() for marker in layer.findMarkers(startBufferRow: row)

module.exports = {deleteMarkers, getFields, getLayers}
