path = require 'path'
fp = require 'lodash/fp'

git = (args..., dir)->
  timeout = 3000
  if typeof dir is 'object'
    dir = dir.getWorkingDirectory()
  if arguments.length is 2
    if Array.isArray args[0]
      execa 'git', args[0], {cwd:dir, timeout}
    else if typeof args[0] is 'string'
      execa 'git', args[0].split(' '), {cwd:dir, timeout}
    else
      throw new Error "when 2 arguments, first argument must be a string or an array"
  else if arguments.length is 1
    throw new Error "At least 2 arguments needed"
  else
    execa 'git', args, {cwd:dir, timeout}

git2 = (args..., p)-> git [args..., path.basename(p)], path.dirname(p)
git.safe = (process)->
  try
    await process
  catch error
    @lastError = error
    undefined


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
git.status = (dir)-> git 'status', '--porcelain', '--ignored', dir
git.parseStatus = (stdout)->
  fp.mapValues((x)-> fp.fromPairs fp.map toNameAndFlag, x) byDir(stdout.split '\n')

filepart = (statusRow)-> statusRow.slice 3
flag = (statusRow)-> statusRow.slice 0, 2
byDir = fp.groupBy (statusRow)-> path.dirname filepart statusRow
toNameAndFlag = (x)-> [path.basename(filepart x), flag x]

module.exports = git
