local M = { name = "deltaview", priority = 105, renderable = true }

local function buffer_var(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	return ok and value or nil
end

local function parsed_line(dataset, row)
	if type(dataset) ~= "table" then
		return nil
	end
	for _, line in pairs(dataset) do
		local formatted_row = type(line) == "table" and tonumber(line.formatted_diff_line_num)
		if formatted_row and formatted_row + 1 == row then
			return line
		end
	end
end

local function first_number(...)
	for index = 1, select("#", ...) do
		local number = tonumber(select(index, ...))
		if number and number > 0 then
			return number
		end
	end
end

function M.detect(bufnr)
	return vim.api.nvim_buf_get_name(bufnr):find("^deltaview://diff/") ~= nil
end

function M.location(bufnr, winid)
	local row = vim.api.nvim_win_get_cursor(winid)[1]
	local line = parsed_line(buffer_var(bufnr, "delta_diff_data_set"), row)
	local root = buffer_var(bufnr, "git_root")
	if not line or type(root) ~= "string" or root == "" then
		return nil, "DeltaView cursor is not on a mappable diff line"
	end

	local kind = tostring(line.line_type or line.type or line.kind or line.diff_type or ""):lower()
	local old_line = first_number(line.old_line_num, line.old_line_number, line.old_line, line.old_lnum)
	local new_line = first_number(line.new_line_num, line.new_line_number, line.new_line, line.new_lnum)
	local deleted = kind == "deleted" or kind == "delete" or kind == "old" or kind == "-"
	local added = kind == "added" or kind == "add" or kind == "new" or kind == "+"
	if kind == "context" or kind == " " then
		deleted = false
		added = false
	elseif not deleted and not added then
		deleted = old_line ~= nil and new_line == nil
		added = new_line ~= nil
	end

	local path, source_line, side
	if deleted then
		path, source_line, side = line.old_path, old_line, "old"
	elseif added or kind == "context" or kind == " " or (old_line and new_line) then
		path, source_line, side = line.new_path, new_line, "new"
	end
	local normalized_path = type(path) == "string" and vim.fs.normalize(path) or ""
	if normalized_path == "" or normalized_path == ".." or normalized_path:find("^%.%.[/\\\\]")
		or normalized_path:sub(1, 1) == "/" or normalized_path:match("^%a:[/\\\\]") or not source_line then
		return nil, "DeltaView cursor is not on a mappable diff line"
	end
	return { root = root, path = normalized_path, line = source_line, side = side }
end

return M
