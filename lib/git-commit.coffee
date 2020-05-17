Path = require 'path'
fs = require('fs').promises
git = require './git'

# scissorsLine = '# ------------------------ >8 ------------------------'

re_git_instructions = /\s*\(.*\)\n/g
comment = (str)-> '# ' + str.trim().replace(/\n/g, "\n# ").slice(0, -3)
content = (arr)-> arr.filter((x)-> x?.trim()).join '\n'

prepFile = ({status, commitMessageFile, template}) ->
  status = status.replace(re_git_instructions, "\n")
  fs.writeFile commitMessageFile, content [template, comment(status)]

commit = (commitMessageFile) ->
  dir = Path.dirname Path.dirname commitMessageFile
  git 'commit', "--cleanup=strip", "--file=#{commitMessageFile}", dir

commitWithEditor = (gitRoot)->
  commitMessageFile = Path.join(gitRoot, 'COMMIT_EDITMSG')
  dir = Path.dirname gitRoot
  try
    tmpl = await git 'config', 'commit.template', dir
    template = await fs.readFile(tmpl.stdout, 'utf8')
  catch e
    console.warn 'git template:', e.message
  try
    status = await git 'status', dir
    await prepFile {status:status.stdout, commitMessageFile, template}
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
      await commit(commitMessageFile)
      atom.workspace.paneForURI(commitMessageFile).itemForURI(commitMessageFile)?.destroy()
  catch e
    console.error e
    atom.notifications.addError "Commit failed", detail: e, dismissable:true

amendWithSameMessage = (gitRoot)->
  commitMessageFile = Path.join(gitRoot, 'COMMIT_EDITMSG')
  dir = Path.dirname gitRoot
  try
    {stdout} = await git 'whatchanged', '-1', '--format=%s%n%n%b%x00', dir
    await fs.writeFile commitMessageFile, stdout.slice(0, stdout.indexOf('\0'))
    await git 'commit', "--cleanup=strip", '--amend', "--file=#{commitMessageFile}", dir
  catch e
    console.error e
    atom.notifications.addError "Commit failed", detail: e.stdout, dismissable:true

module.exports = {commitWithEditor, amendWithSameMessage}
