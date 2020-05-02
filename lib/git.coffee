{ GitRepository } = require "atom"
execa = require 'execa'
path = require 'path'

git = (args..., dir)->
  if typeof dir is 'object'
    dir = dir.getWorkingDirectory()
  if arguments.length is 2
    if Array.isArray args[0]
      execa 'git', args[0], cwd:dir
    else if typeof args[0] is 'string'
      execa 'git', args[0].split(' '), cwd:dir
    else
      throw new Error "when 2 arguments, first argument must be a string or an array"
  else if arguments.length is 1
    throw new Error "At least 2 arguments needed"
  else
    execa 'git', args, cwd:dir

git2 = (args..., p)-> git [args..., path.basename(p)], path.dirname(p)

repoForPath = (goalPath) ->
  for projectPath, i in atom.project.getPaths()
    if goalPath is projectPath or goalPath.indexOf(projectPath + path.sep) is 0
      return atom.project.getRepositories()[i]
  GitRepository.open goalPath, {}

git.pull = (dir)-> git 'pull', dir
git.push = (dir)-> git 'push', dir
git.restore = (p)-> git2 'restore', '--staged', p
git.add = (p)-> git2 'add', p
git.ls = (dir)->
  r = await git 'ls-tree --name-only -z HEAD', dir
  r.stdout.slice(0, -1).split '\0'
git.utils = (dir)-> repoForPath(dir).repo
git.repo = (dir)-> repoForPath(dir)
git.status =
  modified: (s)-> s & modifiedStatusFlags
  ignored: (s)-> s & statusIgnored
  staged: (s)-> s & indexStatusFlags
  newfile: (s)-> s & newStatusFlags
  deleted: (s)-> s & deletedStatusFlags

statusIndexNew = 1 << 0
statusIndexModified = 1 << 1
statusIndexDeleted = 1 << 2
statusIndexRenamed = 1 << 3
statusIndexTypeChange = 1 << 4
statusWorkingDirNew = 1 << 7
statusWorkingDirModified = 1 << 8
statusWorkingDirDelete = 1 << 9
statusWorkingDirTypeChange = 1 << 10
statusIgnored = 1 << 14

modifiedStatusFlags =
  statusWorkingDirModified |
  statusIndexModified |
  statusWorkingDirDelete |
  statusIndexDeleted |
  statusWorkingDirTypeChange |
  statusIndexTypeChange

newStatusFlags = statusWorkingDirNew | statusIndexNew

deletedStatusFlags = statusWorkingDirDelete | statusIndexDeleted

indexStatusFlags =
  statusIndexNew |
  statusIndexModified |
  statusIndexDeleted |
  statusIndexRenamed |
  statusIndexTypeChange

module.exports = git
