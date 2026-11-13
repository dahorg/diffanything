# diffanything.nvim

Diff two files, or two directories recursively, inside Neovim (0.10+).

```vim
:DiffAnything [path-a] [path-b]
```

With no arguments it opens a file browser to pick A, then B. With one argument
it only prompts for B.

## Standalone (TUI launcher)

`bin/diffanything` starts Neovim straight into the picker and quits when you
press `q` in the file list (or cancel the picker):

```sh
ln -s ~/dev/diffanything/bin/diffanything ~/.local/bin/diffanything
diffanything            # pick A, then B
diffanything A          # pick B
diffanything A B        # diff right away
```

Picker keys: `<CR>` open dir / select file, `<Space>` select the entry under
the cursor (file or dir), `.` select the current dir, `-` up, `H` toggle hidden
files, `e` type a path (with completion), `q` cancel.

- **Two files** open side by side in a new tab with `:diffthis` applied.
- **Two directories** open a new tab with a file list on the left and the two
  sides of the selected file next to it. Files are compared by content.
  - `~` modified, `-` only in A, `+` only in B.
  - Binary files show a placeholder instead of a text diff.

## Directory view keys (in the file list)

| Key         | Action                                        |
| ----------- | --------------------------------------------- |
| `<CR>`      | open the diff and move focus to it            |
| `o`         | open the diff, stay in the list               |
| `]f` / `[f` | next / previous changed file (opens it)       |
| `i`         | toggle showing identical files                |
| `r`         | rescan both directories                       |
| `q`         | close the tab                                 |

Inside the diff windows the usual `]c`, `[c`, `do`, `dp` work.

## Install (lazy.nvim)

```lua
{
  "danielholter/diffanything.nvim", -- or dir = "~/dev/diffanything"
  cmd = "DiffAnything",
  opts = {
    ignore = { ".git", "node_modules" }, -- basenames skipped in directory mode
    show_identical = false,
    panel_width = 40,
  },
}
```

Highlights (`DiffAnythingModified`, `DiffAnythingAdded`, `DiffAnythingRemoved`,
`DiffAnythingSame`) link to `Changed`, `Added`, `Removed` and `Comment`.
# diffanything
