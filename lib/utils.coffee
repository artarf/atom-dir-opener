fs = require 'fs'
_fs = fs.promises
path = require 'path'
X = require 'execa'
git = require './git'


ftype = (stats)->
  if stats.isBlockDevice() then 'b'
  else if stats.isCharacterDevice() then 'c'
  else if stats.isDirectory() then 'd'
  else if stats.isFIFO() then 'p'
  else if stats.isSocket() then 's'
  else if stats.isSymbolicLink() then 'l'
  else if stats.isFile() then '-'

flagset = (n)->
  r = ''
  r += if n & 4 then 'r' else '-'
  r += if n & 2 then 'w' else '-'
  r += if n & 1 then 'x' else '-'
  r

fflags = (n)-> flagset(n >> 6) + flagset(n >> 3) + flagset(n)

leftpad = (s, n, ch=' ')-> ch.repeat(n - s.length) + s
rightpad = (s, n, ch=' ')-> s + ch.repeat(n - s.length)

repoForPath = (goalPath) ->
  for projectPath, i in atom.project.getPaths()
    if goalPath is projectPath or goalPath.indexOf(projectPath + path.sep) is 0
      return atom.project.getRepositories()[i]
  null

listFiles = (dir, ignore)->
  # core.ignoredNames
  entries = await _fs.readdir dir, encoding: 'utf8'
  return entries unless repo = repoForPath(dir)
  _base = repo.relativize dir
  index = {}
  entries = entries.map (p, i)->
    index[p] = i
    [p, repo.repo.getStatus(path.join _base, p) or -1]
  return entries if repo.repo.isIgnored(_base)
  gitfiles = await git.ls(dir)
  for p in gitfiles
    if p of index
      i = index[p]
      if entries[i][1] is -1
        entries[i][1] = 0
    else
      entries.push [p, repo.repo.getStatus path.join _base, p]
  entries

splitter = (out, sep)->
  out.split('\n').map (row)-> row.split(sep)

if process.platform is 'darwin'
  assoc = (map, [v, k])-> map.set parseInt(k), v.trim()
  mapSplitter = (out)-> splitter(out, /\s+/).reduce assoc, new Map
  _users = X 'dscl', ['.', '-list', '/Users', 'UniqueID',]
  _groups = X 'dscl', ['.', '-list', '/Groups', 'gid',]
  _users.then (x)-> module.exports.users = mapSplitter x.stdout
  _groups.then (x)-> module.exports.groups = mapSplitter x.stdout
  _users.catch (err)-> console.error err.stack
  _groups.catch (err)-> console.error err.stack

else if process.platform is 'linux'
  assoc = (map, [v, _, k])->
    k = parseInt k
    return map if Number.isNaN(k)
    map.set k, v.trim()
  mapSplitter = (out)-> splitter(out, ':').reduce assoc, new Map
  fs.readFile '/etc/group', 'utf8', (err, data)->
    return console.error err.stack if err
    module.exports.groups = mapSplitter(data)
  fs.readFile '/etc/passwd', 'utf8', (err, data)->
    return console.error err.stack if err
    module.exports.users = mapSplitter(data)

users = groups = new Map
module.exports = {ftype, fflags, leftpad, rightpad, listFiles, users, groups}
