local M = {}

local resolvers = {}

-- Higher priority wins. The normal resolver stays low as the fallback.
local function sort()
	table.sort(resolvers, function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)
end

---Register a resolver.
---@param r { name:string, priority?:number, renderable?:boolean,
---          detect:fun(bufnr:integer, winid:integer):boolean,
---          location:fun(bufnr:integer, winid:integer):table|nil,
---          range_location?:fun(bufnr:integer, start:integer, stop:integer):table|nil,
---          anchor?:fun(note:table, bufnr:integer):integer|nil }
function M.register(r)
	if not r or not r.name or type(r.detect) ~= "function" then
		return
	end
	r.priority = r.priority or 0
	r.renderable = r.renderable == true
	for i, existing in ipairs(resolvers) do
		if existing.name == r.name then
			resolvers[i] = r
			sort()
			return
		end
	end
	resolvers[#resolvers + 1] = r
	sort()
end

---First resolver whose detect() matches the buffer.
function M.detect(bufnr, winid)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	winid = winid or vim.api.nvim_get_current_win()
	for _, r in ipairs(resolvers) do
		local ok, matched = pcall(r.detect, bufnr, winid)
		if ok and matched then
			return r
		end
	end
end

---Resolve the location under the cursor. Falls back to nil on failure.
function M.location(bufnr, winid)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	winid = winid or vim.api.nvim_get_current_win()
	local r = M.detect(bufnr, winid)
	if not r or type(r.location) ~= "function" then
		return nil
	end
	local ok, loc = pcall(r.location, bufnr, winid)
	if ok and loc then
		loc.resolver = r.name
		loc.renderable = r.renderable
		return loc
	end
end

---Resolve a visual range (start/stop 1-based, inclusive) via the resolver.
function M.range_location(bufnr, start_line, stop_line)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local r = M.detect(bufnr, winid)
	if r and type(r.range_location) == "function" then
		local ok, loc = pcall(r.range_location, bufnr, start_line, stop_line)
		if ok and loc then
			loc.resolver = r.name
			loc.renderable = r.renderable
			return loc
		end
	end
	-- Fallback: single-line location if the resolver maps one line only.
	if r and type(r.location) == "function" then
		local ok, loc = pcall(r.location, bufnr, winid)
		if ok and loc then
			loc.line = start_line
			loc.line_end = stop_line
			loc.resolver = r.name
			loc.renderable = r.renderable
			return loc
		end
	end
end

---All resolvers (deep copy).
function M.all()
	return vim.deepcopy(resolvers)
end

return M
