local M = { name = "deltaview", priority = 105, renderable = true }

local function buffer_var(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	return ok and value or nil
end

local function parsed_line(dataset, row)
	if type(dataset) ~= "table" then
		return nil
	end
	for _, file in ipairs(dataset) do
		for _, hunk in ipairs(file.hunks or {}) do
			for _, line in ipairs(hunk.lines or {}) do
				local formatted_row = tonumber(line.formatted_diff_line_num)
				if formatted_row and formatted_row + 1 == row then
					return line, file
				end
			end
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
	local line, file = parsed_line(buffer_var(bufnr, "delta_diff_data_set"), row)
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
		path, source_line, side = file.old_path, old_line, "old"
	elseif added or kind == "context" or kind == " " or (old_line and new_line) then
		path, source_line, side = file.new_path, new_line, "new"
	end
	local normalized_path = type(path) == "string" and vim.fs.normalize(path) or ""
	if normalized_path == "" or normalized_path == ".." or normalized_path:find("^%.%.[/\\\\]")
		or normalized_path:sub(1, 1) == "/" or normalized_path:match("^%a:[/\\\\]") or not source_line then
		return nil, "DeltaView cursor is not on a mappable diff line"
	end
	return { root = root, path = normalized_path, line = source_line, side = side }
end

function M.display_lines(value, bufnr)
	local rows = {}
	for _, file in ipairs(buffer_var(bufnr, "delta_diff_data_set") or {}) do
		for _, hunk in ipairs(file.hunks or {}) do
			for _, line in ipairs(hunk.lines or {}) do
				local row = tonumber(line.formatted_diff_line_num)
				local old_match = value.side ~= "new"
					and file.old_path == value.path
					and tonumber(line.old_line_num) == tonumber(value.line)
				local new_match = value.side ~= "old"
					and file.new_path == value.path
					and tonumber(line.new_line_num) == tonumber(value.line)
				if row and (old_match or new_match) then
					rows[#rows + 1] = row + 1
				end
			end
		end
	end
	return rows
end

return M
