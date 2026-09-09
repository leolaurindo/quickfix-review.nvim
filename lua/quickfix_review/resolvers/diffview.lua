local M = { name = "diffview", priority = 95, renderable = true }

local function current_file(bufnr)
	local ok, lib = pcall(require, "diffview.lib")
	if not ok or type(lib.get_current_view) ~= "function" then
		return
	end
	local view = lib.get_current_view()
	if not view or view.tabpage ~= vim.api.nvim_get_current_tabpage() then
		return
	end
	local entry = view.cur_entry
	local layout = entry and entry.layout
	if not layout or type(layout.files) ~= "function" then
		return
	end
	for _, file in ipairs(layout:files()) do
		if file.bufnr == bufnr then
			return view, entry, file
		end
	end
end

local function revision(file)
	local rev = file.rev
	if not rev or type(rev.object_name) ~= "function" then
		return nil
	end
	local ok, value = pcall(rev.object_name, rev, 40)
	if ok and value and value ~= "LOCAL" and value ~= "UNKNOWN" then
		return value
	end
	return nil
end

local function layout_name(layout)
	if not layout or not layout.class then
		return ""
	end
	local ok, value = pcall(function()
		return layout.class:name()
	end)
	return ok and value or ""
end

function M.detect(bufnr)
	return current_file(bufnr) ~= nil
end

function M.location(bufnr, winid)
	local view, _, file = current_file(bufnr)
	if not view or not file or not file.path then
		return nil
	end
	local hash = revision(file)
	return {
		root = view.adapter.ctx.toplevel,
		path = file.path,
		line = vim.api.nvim_win_get_cursor(winid)[1],
		side = file.symbol == "a" and "old" or "new",
		revision = hash,
		hash = hash,
	}
end

function M.range_location(bufnr, start_line, stop_line)
	local view, entry, file = current_file(bufnr)
	if not view or not entry or not file or layout_name(entry.layout):lower():find("inline", 1, true) then
		return nil
	end
	local value = M.location(bufnr, vim.api.nvim_get_current_win())
	if value then
		value.line, value.line_end = start_line, stop_line
	end
	return value
end

function M.anchor(note)
	return note.line_end or note.line
end

return M
