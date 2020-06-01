utils = require './file-utils'
timeFormat = git = null

statsRow = ([name, stats])->
  git ?= require './git'
  timeFormat ?= require('speed-date')('YYYY-MM-DD HH:mm:ss')
  return ['','','','','','','  ', name] unless stats
  [name, link] = name.split '//'
  time = timeFormat(stats.mtime)
  [
    utils.ftype(stats) + utils.fflags(stats.mode)
    String stats.nlink
    utils.users.get(stats.uid) ? String stats.uid
    utils.groups.get(stats.gid) ? String stats.gid
    String stats.size
    time
    '  '
    name
    if link then '-> ' + link else ''
  ]

balance = (balance)->
  return '' unless balance
  if balance
    if balance is '0\t0'
      ' u='
    else
      balance = balance.split /\s+/
      if balance[0] is '0'
        ' u+' + balance[1]
      else if balance[1] is '0'
        ' u-' + balance[0]
      else
        ' u+' + balance.reverse().join('-')

module.exports = {statsRow, balance}
