{ftype, fflags} = utils = require './utils'
timeFormat = git = null

module.exports = ([name, stats])->
  git ?= require './git'
  timeFormat ?= require('speed-date')('YYYY-MM-DD HH:mm:ss')
  return ['','','','','','','  ', name] unless stats
  [name, link] = name.split '//'
  time = timeFormat(stats.mtime)
  [
    ftype(stats) + fflags(stats.mode)
    String stats.nlink
    utils.users.get(stats.uid) ? String stats.uid
    utils.groups.get(stats.gid) ? String stats.gid
    String stats.size
    time
    '  '
    name
    if link then '-> ' + link else ''
  ]
