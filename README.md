# my-package package

Dired like view for navigating directories in Atom

## Purpose

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

## Commands

- `my-package:open-parent-directory`
   Some explanation...
- `my-package:open-child`
- `my-package:go-home`
- `my-package:reload-directory`
- `my-package:open-external`
- `my-package:select-current`
- `my-package:copy-names-to-clipboard`
- `my-package:copy-fullpaths-to-clipboard`
- `my-package:toggle-selected-and-next-row`
- `my-package:activate-linewise-visual-mode`
- `my-package:git-toggle-staged`

## Default keybindings

    'atom-workspace':
      'cmd-|': 'my-package:open-directory'
    'atom-text-editor.dir':
      'h': 'my-package:open-parent-directory'
      'l': 'my-package:open-child'
      '~': 'my-package:go-home'
      'cmd-r': 'my-package:reload-directory'
      'shift-o': 'my-package:open-external'
      'v': 'my-package:activate-linewise-visual-mode'
      'V': 'my-package:activate-linewise-visual-mode'
      'f': 'my-package:toggle-selected-and-next-row'
      'shift-y shift-y': 'my-package:copy-names-to-clipboard'
      'shift-y f': 'my-package:copy-fullpaths-to-clipboard'
      'shift-y shift-f': 'my-package:copy-fullpaths-to-clipboard'
      'g i a': 'my-package:git-toggle-staged'
