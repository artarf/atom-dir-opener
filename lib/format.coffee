{ftype, fflags} = utils = require './utils'
git = require './git'
module.exports = ([name, stats, link, status])->
  moment = require 'moment'
  return ['','','','','','',formatGitStatus(status), name] unless stats
  time = moment(stats.mtime).fromNow()
  [
    ftype(stats) + fflags(stats.mode)
    String stats.nlink
    utils.users.get(stats.uid) ? String stats.uid
    utils.groups.get(stats.gid) ? String stats.gid
    String stats.size
    time
    formatGitStatus(status)
    name + if stats.isDirectory() then "/" else ""
    if link then "-> " + link else ""
  ]

formatGitStatus = (status)->
  return '  ' unless status
  return '!!' if  git.status.ignored status
  return '!!' if status is -1
  newfile = git.status.newfile status
  return 'A ' if newfile and git.status.staged status
  return '??' if newfile
  x = if git.status.deleted(status) then 'D'
  else if git.status.modified(status) then 'M'
  else ' '
  if git.status.staged(status) then x + ' ' else ' ' + x
