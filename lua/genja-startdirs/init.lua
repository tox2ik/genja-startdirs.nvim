-- genja-startdirs: a list of start directories from a plain text file plus setup opts,
-- with group switches, add/remove/edit, jumps to the most used entries and a usage ranking.
-- File format and options: README.md, doc/genja-startdirs.txt.
local SRC = 'genja-startdirs/init.lua: '

local M = {}

---@alias genja-startdirs.Switch boolean|fun(): boolean

---@class genja-startdirs.Opts
---@field dirs? string[] always listed, after the file's entries (default: home, stdpath('config'))
---@field file? string the startdirs text file (default: stdpath('config')/startdirs.txt)
---@field groups? table<string, genja-startdirs.Switch> `[group]` on/off; missing groups are on
---@field add_group? string group that add() appends to (default 'added')
---@field usage_file? string|false use counts for ranked() (default: stdpath('data')/startdirs.usage); false: off

---@class genja-startdirs.Entry
---@field path string normalized, forward slashes
---@field group? string nil: before any header, or from opts.dirs
---@field from 'file'|'opts'

---@type genja-startdirs.Opts
local defaults = {
	dirs = { '~', vim.fn.stdpath('config') },
	file = vim.fn.stdpath('config') .. '/startdirs.txt',
	groups = {},
	add_group = 'added',
	usage_file = vim.fn.stdpath('data') .. '/startdirs.usage',
}

---@type genja-startdirs.Opts
M.config = vim.deepcopy(defaults)

-- {{{ paths

---@return string
local function home()
	local h = vim.env.USERPROFILE or vim.env.HOME or '~'
	return (h:gsub('\\', '/'))
end

--- `CONFIG/`, `DATA/`, `HOME/` (and `~`) at the start of the text become real directories.
---@param text string
---@return string
local function expand_prefix(text)
	local prefixes = {
		{ 'CONFIG', vim.fn.stdpath('config') },
		{ 'DATA', vim.fn.stdpath('data') },
		{ 'HOME', home() },
	}
	for _, p in ipairs(prefixes) do
		local name, dir = p[1], p[2]
		if text == name then
			return dir
		end
		if text:sub(1, #name + 1) == name .. '/' then
			return dir .. text:sub(#name + 1)
		end
	end
	if text == '~' or text:sub(1, 2) == '~/' then
		return home() .. text:sub(2)
	end
	return text
end

--- Forward slashes, no `oil://`, no trailing slash (but `C:/` and `/` stay).
---@param path string
---@return string
function M.normalize(path)
	local p = vim.trim(path)
	p = p:gsub('^oil://', '')
	p = p:gsub('\\', '/')
	p = expand_prefix(p)
	p = p:gsub('\\', '/')
	-- oil on Windows: /C/Users -> C:/Users
	local drive, rest = p:match('^/(%a)/(.*)$')
	if drive and vim.fn.has('win32') == 1 then
		p = drive:upper() .. ':/' .. rest
	end
	if #p > 1 and p:sub(-1) == '/' and not p:match('^%a:/$') then
		p = p:sub(1, -2)
	end
	if p:match('^%a:$') then
		p = p .. '/'
	end
	return p
end

--- The reverse of expand_prefix, for lines written by add(): config and data dirs first
--- (they sit under home), then home.
---@param path string normalized
---@return string
local function compact(path)
	local prefixes = {
		{ 'CONFIG', vim.fs.normalize(vim.fn.stdpath('config')) },
		{ 'DATA', vim.fs.normalize(vim.fn.stdpath('data')) },
		{ 'HOME', home() },
	}
	local key = path
	if vim.fn.has('win32') == 1 then
		key = path:lower()
	end
	for _, p in ipairs(prefixes) do
		local name, dir = p[1], p[2]
		local dkey = dir
		if vim.fn.has('win32') == 1 then
			dkey = dir:lower()
		end
		if key == dkey then
			return name
		end
		if key:sub(1, #dkey + 1) == dkey .. '/' then
			return name .. path:sub(#dir + 1)
		end
	end
	return path
end

--- Key for comparing paths: case-insensitive on Windows.
---@param path string
---@return string
local function same_key(path)
	if vim.fn.has('win32') == 1 then
		return path:lower()
	end
	return path
end
-- }}}

-- {{{ file

---@param name string
---@return boolean
local function group_on(name)
	local switch = M.config.groups[name]
	if switch == nil then
		return true
	end
	if type(switch) == 'function' then
		local ok, result = pcall(switch)
		if not ok then
			vim.notify(SRC .. 'group ' .. name .. ': switch failed: ' .. tostring(result), vim.log.levels.WARN)
			return false
		end
		return result == true
	end
	return switch == true
end

---@return string[] # empty when the file is missing
local function read_lines()
	local file = M.config.file
	if vim.fn.filereadable(file) == 0 then
		return {}
	end
	return vim.fn.readfile(file)
end

--- All entries of the file with their group, switched-off groups included.
---@return {path: string, group?: string, line: integer}[]
local function parse()
	local out = {}
	local group = nil
	for i, raw in ipairs(read_lines()) do
		local line = vim.trim(raw)
		local header = line:match('^%[(.-)%]$')
		if header then
			group = vim.trim(header)
		elseif line ~= '' and line:sub(1, 1) ~= '#' then
			table.insert(out, { path = M.normalize(line), group = group, line = i })
		end
	end
	return out
end
-- }}}

-- {{{ list

--- Entries in order: the file's (switched-on groups), then opts.dirs. Only existing
--- directories, no duplicates.
---@return genja-startdirs.Entry[]
function M.entries()
	local out = {}
	local seen = {}
	---@param path string
	---@param group? string
	---@param from 'file'|'opts'
	local function push(path, group, from)
		local key = same_key(path)
		if seen[key] or vim.fn.isdirectory(path) == 0 then
			return
		end
		seen[key] = true
		table.insert(out, { path = path, group = group, from = from })
	end
	for _, e in ipairs(parse()) do
		if e.group == nil or group_on(e.group) then
			push(e.path, e.group, 'file')
		end
	end
	for _, d in ipairs(M.config.dirs or {}) do
		push(M.normalize(d), nil, 'opts')
	end
	return out
end

--- Paths only, in file order (see entries()).
---@return string[]
function M.dirs()
	local out = {}
	for _, e in ipairs(M.entries()) do
		table.insert(out, e.path)
	end
	return out
end
-- }}}

-- {{{ usage ranking

---@class genja-startdirs.Usage
---@field count integer
---@field last integer unix time of the last use; 0 for old lines without one

-- Recency weight, zoxide style (same weights as genja-recent's frecency, copied so the
-- plugins stay apart): x4 within an hour, x2 within a day, x0.5 within a week, x0.25 older.
local HOUR = 3600
local DAY = 24 * HOUR
local WEEK = 7 * DAY

---@param age number seconds since the last use
---@return number
local function recency(age)
	if age < HOUR then
		return 4
	end
	if age < DAY then
		return 2
	end
	if age < WEEK then
		return 0.5
	end
	return 0.25
end

-- Lines: `count<TAB>last<TAB>path`; older `count<TAB>path` lines still read (last = 0).
---@return table<string, genja-startdirs.Usage> key -> usage
local function read_usage()
	local file = M.config.usage_file
	local usage = {}
	if not file or vim.fn.filereadable(file) == 0 then
		return usage
	end
	for _, line in ipairs(vim.fn.readfile(file)) do
		local n, last, path = line:match('^(%d+)	(%d+)	(.+)$')
		if not n then
			last = '0'
			n, path = line:match('^(%d+)	(.+)$')
		end
		if n then
			usage[same_key(path)] = { count = tonumber(n), last = tonumber(last) }
		end
	end
	return usage
end

--- Count one use of `path` (a cd from the picker; jumps don't count) and stamp the time.
---@param path string
function M.touch(path)
	local file = M.config.usage_file
	if not file then
		return
	end
	local usage = read_usage()
	local key = same_key(M.normalize(path))
	local u = usage[key]
	if u == nil then
		u = { count = 0, last = 0 }
		usage[key] = u
	end
	u.count = u.count + 1
	u.last = os.time()
	local lines = {}
	for k, v in pairs(usage) do
		table.insert(lines, v.count .. '	' .. v.last .. '	' .. k)
	end
	table.sort(lines)
	vim.fn.mkdir(vim.fs.dirname(file), 'p')
	vim.fn.writefile(lines, file)
end

--- Delete the usage file: every use count and last-use time; ranked() falls back to file order.
function M.reset_usage()
	local file = M.config.usage_file
	if not file or vim.fn.filereadable(file) == 0 then
		vim.notify(SRC .. 'no usage file to delete')
		return
	end
	if vim.fn.delete(file) ~= 0 then
		vim.notify(SRC .. 'could not delete ' .. file, vim.log.levels.ERROR)
		return
	end
	vim.notify(SRC .. 'deleted ' .. file)
end

--- dirs() sorted by frecency (use count x recency weight), highest first; ties keep file order.
---@return string[]
function M.ranked()
	local usage = read_usage()
	local now = os.time()
	local list = M.dirs()
	local order = {}
	local score = {}
	for i, p in ipairs(list) do
		order[p] = i
		score[p] = 0
		local u = usage[same_key(p)]
		if u then
			score[p] = u.count * recency(now - u.last)
		end
	end
	table.sort(list, function(a, b)
		if score[a] ~= score[b] then
			return score[a] > score[b]
		end
		return order[a] < order[b]
	end)
	return list
end
-- }}}

-- {{{ change the file

--- Append `path` under `[group]` (default config.add_group); creates the file and header.
---@param path string
---@param group? string
function M.add(path, group)
	group = group or M.config.add_group
	local p = M.normalize(path)
	for _, e in ipairs(parse()) do
		if same_key(e.path) == same_key(p) then
			local where = ''
			if e.group then
				where = ' [' .. e.group .. ']'
				if not group_on(e.group) then
					where = where .. ', switched off in opts.groups'
				end
			end
			vim.notify(SRC .. 'already listed: ' .. p .. where)
			return
		end
	end
	local lines = read_lines()
	-- insert after the last entry of the group, else a new header at the end
	local insert_at = nil
	local in_group = false
	for i, raw in ipairs(lines) do
		local header = vim.trim(raw):match('^%[(.-)%]$')
		if header then
			in_group = vim.trim(header) == group
			if in_group then
				insert_at = i
			end
		elseif in_group and vim.trim(raw) ~= '' then
			insert_at = i
		end
	end
	local text = compact(p)
	if insert_at then
		table.insert(lines, insert_at + 1, text)
	else
		if #lines > 0 and vim.trim(lines[#lines]) ~= '' then
			table.insert(lines, '')
		end
		table.insert(lines, '[' .. group .. ']')
		table.insert(lines, text)
	end
	vim.fn.mkdir(vim.fs.dirname(M.config.file), 'p')
	vim.fn.writefile(lines, M.config.file)
	vim.notify(SRC .. 'added ' .. text .. ' [' .. group .. ']')
end

--- Remove the file's lines for `path`. Dirs from opts.dirs can't be removed here.
---@param path string
function M.remove(path)
	local p = M.normalize(path)
	local drop = {}
	for _, e in ipairs(parse()) do
		if same_key(e.path) == same_key(p) then
			drop[e.line] = true
		end
	end
	if next(drop) == nil then
		for _, d in ipairs(M.config.dirs or {}) do
			if same_key(M.normalize(d)) == same_key(p) then
				vim.notify(SRC .. p .. ' comes from the spec (opts.dirs), not the file')
				return
			end
		end
		vim.notify(SRC .. 'not listed: ' .. p)
		return
	end
	local kept = {}
	for i, line in ipairs(read_lines()) do
		if not drop[i] then
			table.insert(kept, line)
		end
	end
	vim.fn.writefile(kept, M.config.file)
	vim.notify(SRC .. 'removed ' .. p)
end

--- Open the file for editing.
function M.edit()
	vim.fn.mkdir(vim.fs.dirname(M.config.file), 'p')
	vim.cmd.edit(vim.fn.fnameescape(M.config.file))
end
-- }}}

-- {{{ jump

--- cd to `path` and open it (oil shows directories).
---@param path string
local function open_dir(path)
	vim.cmd.chdir(vim.fn.fnameescape(path))
	vim.cmd.edit(vim.fn.fnameescape(path))
end

--- cd to the n-th entry of ranked() (most used first) and open it.
--- Not counted as a use: counting would reorder the slots the keys point at.
---@param n integer
function M.jump(n)
	local list = M.ranked()
	local path = list[n]
	if not path then
		vim.notify(SRC .. 'no start dir #' .. n .. ' (' .. #list .. ' listed)')
		return
	end
	open_dir(path)
end

--- cd to `path`, open it, count a use.
---@param path string
function M.go(path)
	open_dir(path)
	M.touch(path)
end
-- }}}

---@param opts? genja-startdirs.Opts
function M.setup(opts)
	M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
	-- lists replace, not merge
	if opts and opts.dirs then
		M.config.dirs = opts.dirs
	end

	vim.api.nvim_create_user_command('StartdirsEdit', function() M.edit() end,
		{ desc = 'Startdirs: edit the file' })
	vim.api.nvim_create_user_command('StartdirsAdd', function(o)
		local path = o.args
		if path == '' then
			path = vim.fn.getcwd()
		end
		M.add(path)
	end, { nargs = '?', complete = 'dir', desc = 'Startdirs: add a dir (default: cwd)' })
	vim.api.nvim_create_user_command('StartdirsRemove', function(o)
		local path = o.args
		if path == '' then
			path = vim.fn.getcwd()
		end
		M.remove(path)
	end, { nargs = '?', complete = 'dir', desc = 'Startdirs: remove a dir (default: cwd)' })
end

return M
