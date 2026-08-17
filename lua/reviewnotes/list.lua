local M = {}

local function list_kind()
	local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
	return info and info.loclist == 1 and "location" or "quickfix"
end

local function list_for(kind)
	local fields = { all = 1 }
	if kind == "location" then
		return vim.fn.getloclist(0, fields)
	end
	return vim.fn.getqflist(fields)
end

local function filename(item, root)
	local file
	if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
		file = vim.api.nvim_buf_get_name(item.bufnr)
	end
	file = file ~= "" and file or item.filename or item.module
	if not file or file == "" then
		return
	end
	if root and file:find(root .. "/", 1, true) == 1 then
		return file:sub(#root + 2)
	end
	return file
end

local function stable_value(value, seen)
	if type(value) ~= "table" then
		local ok, encoded = pcall(vim.json.encode, value)
		return ok and encoded or type(value)
	end
	seen = seen or {}
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true
	local keys = vim.tbl_keys(value)
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = stable_value(key, seen) .. ":" .. stable_value(value[key], seen)
	end
	seen[value] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

function M.current()
	local kind = list_kind()
	local list = list_for(kind)
	local index = list.idx or vim.fn.line(".")
	return {
		kind = kind,
		id = list.id,
		index = index,
		title = list.title,
		context = list.context,
		list_key = stable_value({ kind = kind, title = list.title, context = list.context }),
		winid = kind == "location" and vim.api.nvim_get_current_win() or nil,
		item = list.items and list.items[index],
	}
end

function M.file(item, root)
	return filename(item, root)
end

function M.location(entry, root)
	local item = entry.item
	if not item then
		return
	end
	local file = filename(item, root)
	if not file then
		return
	end
	local line = math.max(1, tonumber(item.lnum) or 1)
	local line_end = tonumber(item.end_lnum)
	return {
		file = file,
		line = line,
		line_end = line_end and line_end > line and line_end or nil,
		item_key = stable_value({
			kind = entry.kind,
			list_key = entry.list_key,
			index = entry.index,
			file = file,
			line = line,
			line_end = line_end,
			col = item.col,
			end_col = item.end_col,
			type = item.type,
			nr = item.nr,
			module = item.module,
			pattern = item.pattern,
			text = item.text,
			user_data = item.user_data,
		}),
	}
end

function M.location_for(kind, item, root, list_key, index)
	return M.location({ kind = kind, item = item, list_key = list_key, index = index }, root)
end

function M.items()
	local kind = list_kind()
	local list = list_for(kind)
	return list, kind, stable_value({ kind = kind, title = list.title, context = list.context })
end

return M
