local M = {}
local resolvers = {}

local function sort()
	table.sort(resolvers, function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)
end

function M.register(resolver)
	if not resolver or not resolver.name or type(resolver.detect) ~= "function" then
		return
	end
	resolver.priority = resolver.priority or 0
	resolver.renderable = resolver.renderable == true
	for index, existing in ipairs(resolvers) do
		if existing.name == resolver.name then
			resolvers[index] = resolver
			sort()
			return
		end
	end
	resolvers[#resolvers + 1] = resolver
	sort()
end

function M.detect(bufnr, winid)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	winid = winid or vim.api.nvim_get_current_win()
	for _, resolver in ipairs(resolvers) do
		local ok, matched = pcall(resolver.detect, bufnr, winid)
		if ok and matched then
			return resolver
		end
	end
end

function M.location(bufnr, winid)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	winid = winid or vim.api.nvim_get_current_win()
	local resolver = M.detect(bufnr, winid)
	if not resolver or type(resolver.location) ~= "function" then
		return nil
	end
	local ok, value = pcall(resolver.location, bufnr, winid)
	if ok and value then
		value.resolver = resolver.name
		value.renderable = resolver.renderable
		return require("quickreview.location").canonical(value)
	end
end

function M.range_location(bufnr, start_line, stop_line)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local resolver = M.detect(bufnr, winid)
	if not resolver or type(resolver.range_location) ~= "function" then
		return nil
	end
	local ok, value = pcall(resolver.range_location, bufnr, start_line, stop_line)
	if ok and value then
		value.resolver = resolver.name
		value.renderable = resolver.renderable
		return require("quickreview.location").canonical(value)
	end
end

function M.all()
	return vim.deepcopy(resolvers)
end

return M
