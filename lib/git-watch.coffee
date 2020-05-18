fs = require 'fs'
path = require 'path'
assert = require 'assert'
git = require './git'

swallow = (f)->
  try
    f()
  catch e

sleep = (ms)-> new Promise (resolve)-> setTimeout resolve, ms
isDir = (p)-> swallow -> fs.statSync(p).isDirectory()
isFile = (p)-> swallow -> fs.statSync(p).isFile()

class GitWatch
  constructor: (root, @callback)->
    @root = path.resolve root
    assert isDir(@root)
    @working = @closed = false
    @status = @branch = @balance = @hasStaged = @hasChanges = null
    @index = path.join @root, 'index'
    @workdir = path.dirname @root
    setTimeout @check.bind(this)
  send: ->
    return if @closed
    @sendRequest = null
    # atom GitRepository does not correctly follow changes -> Help it!
    if r = atom?.project.repositories.find (r)=> r.getPath() is @root
      setTimeout ->
        r.refreshIndex()
        r.refreshStatus()
    @callback()
  setProperty: (name, value)->
    return if @closed
    return if this[name] is value
    this[name] = value
    clearTimeout @sendRequest if @sendRequest?
    @sendRequest = setTimeout @send.bind(this), 100
  setHasChanges: (hasChanges)-> @setProperty 'hasChanges', hasChanges
  setHasStaged: (hasStaged)-> @setProperty 'hasStaged', hasStaged
  setBranch: (branch)-> @setProperty 'branch', branch
  setBalance: (balance)-> @setProperty 'balance', balance
  setStatus: (status)-> @setProperty 'status', status
  dispose: ->
    return if @closed
    @watch?.close()
    clearTimeout @sendRequest if @sendRequest?
    @working = @watch = @status = @branch = @balance = @hasStaged = @hasChanges = @sendRequest = null
    @closed = true
    return
  indexChanged: ->
    return if @working or @closed
    @watch.close()
    @watch = null
    return @dispose() if not isDir(@root) # root is deleted
    setTimeout @check.bind(this)
  check: ->
    return if @closed
    if (not isFile @index) or @working
      clearTimeout @checkLock if @checkLock?
      @checkLock = setTimeout @check.bind(this), 10
      return
    @watch?.close()
    @working = true
    promises = []
    promises.push git.branch(@workdir).then (result)=> @setBranch result.stdout
    promises.push git.hasStaged(@workdir).then @setHasStaged.bind(this)
    promises.push git.hasChanges(@workdir).then @setHasChanges.bind(this)
    promises.push git.remote(@workdir).then (result)=>
      if result?.stdout?.trim()
        git.balance(@workdir).then (x)=> @setBalance x.stdout
    promises.push git.status(@workdir).then (result)=> @setStatus result.stdout
    await Promise.all(promises)
    await sleep(10)
    @checkLock = null
    @working = false
    @watch = fs.watch @index, @indexChanged.bind this
    return
module.exports = GitWatch
