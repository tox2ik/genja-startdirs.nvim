# genja-startdirs.nvim

Start directories from a text file plus setup dirs. Loaded from disk by the
config's `../../lua/lazyp/new/genja-startdirs.lua` (keys, cmds, or the first
`require('genja-startdirs')`). Read README.md and `doc/genja-startdirs.txt`.

How this file is kept: one heading per feature, one bullet per decision.
Unmarked bullets were stated by jaro. `(inferred)` marks Claude's reading of the
code or history: confirm or delete. `Hint:` is a working note for Claude.

## Layout

- `lua/genja-startdirs/init.lua`: everything (setup, file parsing, list, ranking, add/remove, jump, commands).
- Option or function changes go into README.md and `doc/genja-startdirs.txt` too.

## Decisions

- Replaces the config's global `START_DIRS` (removed); callers use `dirs()` / `ranked()`.
- The spec keeps only home and the config dir (`opts.dirs`); everything else lives in the file.
- The config's file: `lua/genja/local/startdirs.txt`, gitignored; `startdirs.example.txt` next to it.
- `CONFIG/` and `DATA/` (and `HOME/`) expand only at the start of a line.
- `[group]` headers in the file; switches in the spec's `opts.groups`: a boolean or a function returning one.
- harpoon-like parts: `<M-1>`…`<M-4>` jump to the first four entries (file order); use counts in `stdpath('data')/startdirs.usage` rank the mydirs picker.
- Ranking is frecency: count x recency weight (genja-recent's weights, copied, not required); the usage file keeps the last-use time.
- Keys (config): `<leader>s…` and `<leader>jA`/`je`/`jD`; oil `,s`/`,S` add/remove under `[oil]`.
- Plain text file, not JSON: easy to edit by hand. (inferred from the choice of format)
- The plugin must not require `genja.*`; mappings and the picker stay in the config. (inferred, as in the other plug-wip plugins)
