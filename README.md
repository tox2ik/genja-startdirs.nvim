# genja-startdirs.nvim

A list of start directories: a plain text file plus a few dirs from setup,
with group switches, add/remove from the editor, jumps to the first entries
and a frecency ranking (use count x recency) for pickers. No picker of its own; callers get the
list from `dirs()` / `ranked()`.

## Setup

```lua
require('genja-startdirs').setup({
	dirs = { '~', vim.fn.stdpath('config') }, -- always listed, after the file
	file = vim.fn.stdpath('config') .. '/startdirs.txt',
	add_group = 'added',                        -- add() appends under [added]
	groups = {                                  -- missing groups are on
		windows = function() return vim.fn.has('win32') == 1 end,
		games = false,
	},
	usage_file = vim.fn.stdpath('data') .. '/startdirs.usage', -- false: no ranking
})
```

## File

```
# comment
HOME/notes
oil:///C/Users/me/ws/

[games]
C:/Games
```

- One directory per line; blank lines and `#` lines are skipped.
- `CONFIG`, `DATA`, `HOME` (alone, or followed by `/`) expand only at the
  start of a line, to `stdpath('config')`, `stdpath('data')` and the home dir.
- `oil://` is stripped; oil's `/C/…` becomes `C:/…` on Windows.
- `[name]` starts a group; setup's `groups` switches it on or off.
- Missing directories are left out; duplicates too (case-insensitive on
  Windows).
- `add()` writes paths back with those prefixes where they fit.

## API

| Function | |
|---|---|
| `dirs()` | paths: the file's entries (switched-on groups), then `opts.dirs` |
| `entries()` | the same with `group` and `from` (`file`/`opts`) |
| `ranked()` | `dirs()` by frecency: use count x4 (last use < 1 h), x2 (< 1 day), x0.5 (< 1 week), x0.25 older; ties keep file order |
| `touch(path)` | count one use, stamp the time |
| `go(path)` | `:cd`, `:edit` the dir, `touch` |
| `jump(n)` | `go` to the n-th entry of `dirs()` |
| `add(path, group?)` / `remove(path)` | change the file |
| `edit()` | open the file |
| `normalize(path)` | expand prefixes, forward slashes, strip `oil://` |

Commands: `:StartdirsEdit`, `:StartdirsAdd [dir]`, `:StartdirsRemove [dir]`
(default: the cwd).
