# dir-opener package

Dired like view for navigating directories in Atom

## Purpose

Keyboard navigable directory browsing and editing and enable all nice
editor navigating features of
[vim-mode-plus](https://github.com/t9md/atom-vim-mode-plus).
Extra nicety is that you can select things (and copy) just like in normal editor.

Using trackpad causes me [RSI](https://en.wikipedia.org/wiki/Repetitive_strain_injury),
so I need a way to use keyboard for navigating directories.
Atom builtin [tree-view](https://github.com/atom/tree-view) can be used by keyboard
after some effort on customizing keybindings,
but it comes nowhere close to vim builtin
`netrw` with tpope's [`vinegar`](https://github.com/tpope/vim-vinegar)
or even emacs `dired-mode`.

Ultimate solutions would be something like [vifm](https://vifm.info/) or
[ranger](https://ranger.github.io/).
Emacs [ranger](https://github.com/ralesi/ranger.el) `deer-mode` is a major source of inspiration.

Also it's nice to have familiar `ls -al` format to _see_ directory contents.

## Features

- [x] `ls -al` format
- [x] Movements with vim keys h j k l
- [x] Selecting multiple files
- [x] Copy filenames of selected
- [x] Prevents automatic `untitled` file
- [x] Show git status
- [x] Show branch
- [ ] Config: whether to prevent `untitled`
- [ ] Sorting options (backed by config option)
- [ ] Hidden options .gitignore and atom-ignored-files (backed by config option)
- [ ] Deleting
- [ ] Renaming / moving
- [ ] Cycling current project roots
- [ ] Adding folders to current project
- [ ] Saving current project
- [ ] Renaming current project
- [ ] Cycling projects
- [ ] Changing owner/group
- [ ] Changing mode (toggle with keys `c m _ x`, `c m _ w`, `c m _ r` where \_ is none / `u` / `g` / `o`)
- [x] Toggle selected files to/from index
- [ ] Toggle selected files to/from ignored

## Limitations

- Depends on [vim-mode-plus](https://github.com/t9md/atom-vim-mode-plus) for multiple selections
- Works on macos
- Will work on linux
- Windows support depends on contributions
- Propably not very practical for mouse addicts; features are designed to be used with keyboard
- Needs git executable on path
- Tested only with Git 2.26.2

## Commands

- `dir-opener:open-parent-directory`
   Some explanation...
- `dir-opener:open-child`
- `dir-opener:go-home`
- `dir-opener:reload-directory`
- `dir-opener:open-external`
- `dir-opener:select-current`
- `dir-opener:copy-names-to-clipboard`
- `dir-opener:copy-fullpaths-to-clipboard`
- `dir-opener:toggle-selected-and-next-row`
- `dir-opener:activate-linewise-visual-mode`
- `dir-opener:git-toggle-staged`

## Default keybindings

    'atom-workspace':
      'cmd-|': 'dir-opener:open-directory'
    'atom-text-editor.dir':
      'h': 'dir-opener:open-parent-directory'
      'l': 'dir-opener:open-child'
      '~': 'dir-opener:go-home'
      'cmd-r': 'dir-opener:reload-directory'
      'shift-o': 'dir-opener:open-external'
      'v': 'dir-opener:activate-linewise-visual-mode'
      'V': 'dir-opener:activate-linewise-visual-mode'
      'f': 'dir-opener:toggle-selected-and-next-row'
      'shift-y shift-y': 'dir-opener:copy-names-to-clipboard'
      'shift-y f': 'dir-opener:copy-fullpaths-to-clipboard'
      'shift-y shift-f': 'dir-opener:copy-fullpaths-to-clipboard'
      'g i a': 'dir-opener:git-toggle-staged'
