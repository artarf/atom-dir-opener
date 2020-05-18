Path = require 'path'
fs = require('fs').promises
git = require './git'

# scissorsLine = '# ------------------------ >8 ------------------------'

re_git_instructions = /\s*\(.*\)\n/g
comment = (str)-> '# ' + str.trim().replace(/\n/g, "\n# ").slice(0, -3)
content = (arr)-> arr.filter((x)-> x?.trim()).join '\n'

commitWithEditor = (gitRoot, amend)->
  commitMessageFile = Path.join(gitRoot, 'COMMIT_EDITMSG')
  dir = Path.dirname gitRoot
  try
    if amend
      lastCommit = await getLastCommit(dir)
    else
      template = await getTemplate(dir)
    status = await git 'status', dir
    status = status.stdout.replace(re_git_instructions, "\n")
    await fs.writeFile commitMessageFile, content [lastCommit, template, comment(status)]
    if pane = atom.workspace.paneForURI(commitMessageFile)
      e = pane.itemForURI(commitMessageFile)
      pane.activate()
      pane.activateItem(e)
    else
      e = await atom.workspace.open commitMessageFile
    listener0 = e.onDidDestroy ->
      listener0?.dispose()
      listener?.dispose()
    listener = e.onDidSave ->
      listener.dispose()
      args = ['commit', "--cleanup=strip", "--file=#{commitMessageFile}"]
      args.push '--amend' if amend
      await git args, dir
      atom.workspace.paneForURI(commitMessageFile).itemForURI(commitMessageFile)?.destroy()
  catch e
    console.error e
    atom.notifications.addError "Commit failed", detail: e.stderr, dismissable:true

getTemplate = (dir)->
  try
    tmpl = await git 'config', 'commit.template', dir
    template = await fs.readFile(tmpl.stdout, 'utf8')
  catch e
    console.warn 'git template:', e.message

getLastCommit = (dir)->
  {stdout} = await git 'whatchanged', '-1', '--format=%s%n%n%b%x00', dir
  stdout.slice(0, stdout.indexOf('\0'))

amendWithSameMessage = (gitRoot)->
  commitMessageFile = Path.join(gitRoot, 'COMMIT_EDITMSG')
  dir = Path.dirname gitRoot
  try
    await fs.writeFile commitMessageFile, await getLastCommit(dir)
    await git 'commit', "--cleanup=strip", '--amend', "--file=#{commitMessageFile}", dir
  catch e
    console.error e
    atom.notifications.addError "Commit failed", detail: e.stdout, dismissable:true

module.exports = {commitWithEditor, amendWithSameMessage}
