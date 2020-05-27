fs = require 'fs'
path = require 'path'
assert = require 'assert'
{pointsToDirectorySync} = require './file-utils'
git = require './git'

sleep = (ms)-> new Promise (resolve)-> setTimeout resolve, ms

class GitWatch
  constructor: (root, @callback)->
    @root = path.resolve root
    assert pointsToDirectorySync(@root)
    @working = false
    @status = @branch = @balance = @hasStaged = @hasChanges = null
    @index = path.join @root, 'index'
    @workdir = path.dirname @root
    @scheduleCheck()
  send: ->
    @callback()
    # atom GitRepository does not correctly follow changes -> Help it!
    if r = atom?.project.repositories.find (r)=> r.getPath() is @root
        await sleep(10)
        r.refreshIndex()
        r.refreshStatus()
  setProperty: (name, value)->
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
    @watch?.close()
    clearTimeout @sendRequest if @sendRequest?
    @working = @watch = @status = @branch = @balance = @hasStaged = @hasChanges = @sendRequest = null
    @scheduleCheck = @check = @send = ->
    return
  indexChanged: ->
    return if @working
    @watch.close()
    @watch = null
    return @dispose() if not pointsToDirectorySync(@root) # root is deleted
    @scheduleCheck()
  scheduleCheck: ->
    window.cancelAnimationFrame @schedule
    @schedule = window.requestAnimationFrame =>
      return @scheduleCheck() if @working or not fs.existsSync @index
      @watch?.close()
      @working = true
      await check(this)
      await sleep(10)
      @watch = fs.watch @index, @indexChanged.bind this
      @working = false
module.exports = GitWatch

check = (cache)->
  promises = []
  promises.push git.branch(cache.workdir).then (result)=> cache.setBranch result.stdout
  promises.push git.hasStaged(cache.workdir).then cache.setHasStaged.bind(cache)
  promises.push git.hasChanges(cache.workdir).then cache.setHasChanges.bind(cache)
  promises.push git.remote(cache.workdir).then (result)=>
    if result?.stdout?.trim()
      git.balance(cache.workdir).then (x)=> cache.setBalance x.stdout
  promise = git.status(cache.workdir)
    .then (s)-> cache.setStatus s.stdout
    .catch (e)-> console.error cache.workdir, e
  promises.push promise
  Promise.all(promises)
