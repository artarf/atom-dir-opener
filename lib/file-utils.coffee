fs = require 'fs'
_fs = fs.promises
path = require 'path'
_ = require 'lodash'
X = require 'execa'

statsEqual = (a, b)->
  return unless a instanceof fs.Stats
  return unless b instanceof fs.Stats
  a.mode is b.mode and
  a.size is b.size and
  a.nlink is b.nlink and
  a.mtimeMs is b.mtimeMs and
  a.uid is b.uid and
  a.gid is b.gid

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

splitter = (out, sep)->
  out.split('\n').map (row)-> row.split(sep)

dirext = (link, stat)-> link + if stat.isDirectory() and not link.endsWith '/' then "/" else ""

getStat = (dir, name)->
  file = path.join dir, name
  stat = await _fs.lstat file
  return [dirext(name, stat), stat] unless stat.isSymbolicLink()
  name += '//' + await _fs.readlink(file)
  try
    s = await _fs.stat(file)
    [dirext(name, s), stat]
  catch error
    console.error error.message if error.code isnt 'ENOENT'
    [name, stat]

getStats = (dir)->
  entries = await _fs.readdir(dir, encoding: 'utf8')
  try
    _.fromPairs await Promise.all entries.map (x)-> getStat(dir, x)
  catch error
    console.log error.stack
    {}

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

getLengths = (x)->
  lengths = []
  for row in x
    for cell,i in row
      lengths[i] = Math.max cell.length, lengths[i] ? 0
  lengths

users = groups = new Map
module.exports = {statsEqual, ftype, fflags, leftpad, rightpad, getStat, getStats, users, groups, getLengths}
