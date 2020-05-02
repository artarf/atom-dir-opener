{ftype, fflags} = utils = require './utils'
git = require './git'
module.exports = ([name, stats, link, status])->
  moment = require 'moment'
  return ['','','','','','',status, name] unless stats
  time = moment(stats.mtime).fromNow()
  [
    ftype(stats) + fflags(stats.mode)
    String stats.nlink
    utils.users.get(stats.uid) ? String stats.uid
    utils.groups.get(stats.gid) ? String stats.gid
    String stats.size
    time
    status
    name + if stats.isDirectory() then "/" else ""
    if link then "-> " + link else ""
  ]
