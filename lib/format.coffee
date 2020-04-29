{ftype, fflags} = utils = require './utils'
module.exports = ([name, stats, link])->
  moment = require 'moment'
  time = moment(stats.mtime).fromNow()
  [
    ftype(stats) + fflags(stats.mode)
    String stats.nlink
    utils.users.get(stats.uid) ? String stats.uid
    utils.groups.get(stats.gid) ? String stats.gid
    String stats.size
    time
    name + if stats.isDirectory() then "/" else ""
    if link then "-> " + link else ""
  ]
