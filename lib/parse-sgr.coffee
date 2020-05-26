# taken from https://github.com/chalk/ansi-regex
RE =
  ///
  [\u001B\u009B][[\]()#;?]*(?:(?:(?:[a-zA-Z\d]*(?:;[-a-zA-Z\d\/#&.:=?%@~_]*)*)?\u0007)
  | (?:(?:\d{1,4}(?:;\d{0,4})*)?[\dA-PR-TZcf-ntqry=><~]))
  ///g

module.exports = (stdout)->
  RE.lastIndex = 0
  text = ''
  controls = []
  j = i = 0
  ranges = []
  while a = RE.exec(stdout)
    str = stdout.slice i, a.index
    if controls.length and str.length
      ranges.push [controls, [j, j + str.length]]
    if a[0] is '\u001b[m' or a[0] is '\u001b[0m' # todo add other resets
      controls = []
    else if controls.includes a[0]
      controls.splice controls.indexOf(a[0]), 1
    else
      controls.push a[0]
    text += str
    j += str.length
    i = RE.lastIndex
  text += stdout.slice i
  {text, ranges}
