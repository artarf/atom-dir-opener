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
git.remote = (dir)-> git 'remote', dir
git.branch = (dir)-> git 'rev-parse', '--abbrev-ref', 'HEAD', dir
git.repo = (dir)-> repoForPath(dir)
git.hasStaged = (dir)-> gitrc 'diff', '--no-ext-diff', '--cached', '--quiet', dir
git.hasChanges = (dir)-> gitrc 'diff', '--no-ext-diff', '--quiet', dir
git.balance = (dir)-> git 'rev-list', '--count', '--left-right', '@{upstream}...HEAD', dir
git.status = (dir)-> git 'status', '--porcelain', '--ignored', dir
git.parseStatus = (stdout, dirpath)->
  dirpath += path.sep if dirpath and not dirpath.endsWith path.sep
  b = ([n,f])-> n.startsWith dirpath
  c = ([n,f])-> [n.slice(dirpath.length).split(path.sep)[0..1],f]
  lines = fp.map toNameAndFlag, fp.filter(nocomment) stdout.split '\n'
  tmp = fp.filter(b) lines
  if tmp.length
    fp.mapValues(d) fp.groupBy '0.0', tmp.map(c)
  else if pp = path.dirname dirpath
    # try to derive from parent
    b = ([n,f])-> dirpath.startsWith n
    fp.fromPairs fp.filter(b)(lines).sort().slice(-1)

filepart = (statusRow)-> statusRow.slice 3
flag = (statusRow)-> statusRow.slice 0, 2
byDir = fp.groupBy (statusRow)-> path.dirname filepart statusRow
stripQuotes = (str)->
  return str unless str[0] is '"'
  str = str.slice 1, -1
  str.replace /\\"/g, '"'

toNameAndFlag = (x)->
  xx = filepart(x).split ' -> '
  renamed = if xx.length is 1 then '' else xx[0]
  [stripQuotes(fp.last(xx)), flag(x) + stripQuotes(renamed)]
d = (x)->
  flags = x.map(fp.last).reduce(git.mergeStatus, '  ')
  if flags is '!!'
    return '  ' if x.length > 1
    [a,b] = x[0][0]
    return if b then '  ' else '!!'
  return flags if flags is '??'
  return '??' if flags is '?!' or flags is '!?'
  return flags.replace('!', ' ') if /!/.test flags
  flags
mergeFlag = (a,b)->
  if a is b then b
  else if a >= 'A' and b >= 'A' then 'X'
  else if a < b then b
  else a
git.mergeStatus = (r,s)-> mergeFlag(r[0], s[0]) + mergeFlag(r[1], s[1]) + s.slice 2

module.exports = git
