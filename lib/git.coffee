execa = require 'execa'
path = require 'path'
fp = require 'lodash/fp'

git = (args..., dir)->
  timeout = 3000
  dir = dir.getWorkingDirectory?() ? dir
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

gitrc = (args..., cwd)->
  result = await execa 'git', args, {cwd, timeout: 9000, stdout:'ignore', stderr:'ignore', reject:false}
  result.exitCode isnt 0

git2 = (args..., p)-> git [args..., path.basename(p)], path.dirname(p)
git.safe = (process)->
  try
    await process
  catch error
    @lastError = error
    undefined

nocomment = (x)-> not x.startsWith '#'
repoForPath = (goalPath) ->
  for projectPath, i in atom.project.getPaths()
    if goalPath is projectPath or goalPath.indexOf(projectPath + path.sep) is 0
      return atom.project.getRepositories()[i]
  require('atom').GitRepository.open goalPath, {}

git.pull = (dir)-> git 'pull', dir
git.fetch = (dir)-> git 'fetch', dir
git.push = (dir)-> git 'push', dir
git.restore = (p)-> git2 'restore', '--staged', p
git.add = (p)-> git2 'add', p
git.root = (dir)-> git 'rev-parse', '--absolute-git-dir', dir
git.utils = (dir)-> repoForPath(dir).repo
git.repo = (dir)-> repoForPath(dir)
git.hasStaged = (dir)-> gitrc 'diff', '--no-ext-diff', '--cached', '--quiet', dir
git.hasChanges = (dir)-> gitrc 'diff', '--no-ext-diff', '--quiet', dir
git.balance = (dir)-> git 'rev-list', '--count', '--left-right', '@{upstream}...HEAD', dir
git.status = (dir)-> git 'status', '--porcelain', '--ignored', '--branch', dir
git.parseBranch = (stdout)-> stdout.slice 3, if ~(i=stdout.indexOf '\n') then i
git.parseStatus = (stdout, dirpath)->
  dirpath += path.sep if dirpath and not dirpath.endsWith path.sep
  b = ([n,f])-> n.startsWith dirpath
  c = ([n,f])-> [n.slice(dirpath.length).split(path.sep)[0],f]
  lines = fp.map toNameAndFlag, fp.filter(nocomment) stdout.split '\n'
  tmp = fp.filter(b) lines
  if tmp.length
    fp.mapValues(d) fp.groupBy 0, tmp.map(c)
  else if pp = path.dirname dirpath
    # try to derive from parent
    b = ([n,f])-> dirpath.startsWith n
    fp.fromPairs fp.filter(b)(lines).sort().slice(-1)

filepart = (statusRow)-> statusRow.slice 3
flag = (statusRow)-> statusRow.slice 0, 2
byDir = fp.groupBy (statusRow)-> path.dirname filepart statusRow
toNameAndFlag = (x)-> [filepart(x), flag(x)]
d = (x)->
  flags = x.reduce(mergeStatus, '  ')
  return flags if flags is '!!' or flags is '??'
  return '??' if flags is '?!' or flags is '!?'
  return flags.replace('!', ' ') if /!/.test flags
  flags
mergeFlag = (a,b)->
  if a is b then b
  else if a >= 'A' and b >= 'A' then 'X'
  else if a < b then b
  else a
mergeStatus = (r,[_, s])-> mergeFlag(r[0], s[0]) + mergeFlag(r[1], s[1])

module.exports = git
