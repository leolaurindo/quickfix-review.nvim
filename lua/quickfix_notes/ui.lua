local M = {}

function M.title(loc)
	local parts = {}
	if loc.path or loc.file then
		parts[#parts + 1] = loc.path or loc.file
	end
	if loc.line then
		parts[#parts + 1] = "L"
			.. loc.line
			.. (loc.line_end and loc.line_end ~= loc.line and ("-" .. loc.line_end) or "")
	end
	if loc.side then
		parts[#parts + 1] = loc.side
	end
	if loc.revision then
		parts[#parts + 1] = tostring(loc.revision):sub(1, 7)
	end
	return #parts > 0 and table.concat(parts, " | ") or "Quickfix Notes"
end

function M.note_input(opts, callback)
	opts = opts or {}
	local previous = vim.api.nvim_get_current_win()
	local width = math.min(76, math.max(48, vim.o.columns - 8))
	local height = math.min(14, math.max(7, vim.o.lines - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " " .. M.title(opts.location or {}) .. " ",
		title_pos = "center",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
	})
	vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].filetype = "acwrite", "wipe", "text"
	local initial = opts.existing and opts.existing.text or ""
	vim.api.nvim_buf_set_lines(
		buf,
		0,
		-1,
		false,
		initial ~= "" and vim.split(initial, "\n", { plain = true }) or { "" }
	)
	local closed = false
	local function close(result)
		if closed then
			return
		end
		closed = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_win_is_valid(previous) then
			vim.api.nvim_set_current_win(previous)
		end
		vim.cmd("stopinsert")
		callback(result)
	end
	local function save()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		while #lines > 0 and lines[#lines] == "" do
			table.remove(lines)
		end
		close(#lines > 0 and { text = table.concat(lines, "\n") } or nil)
	end
	vim.keymap.set({ "n", "i" }, "<C-s>", save, { buffer = buf, nowait = true })
	vim.keymap.set("n", "q", save, { buffer = buf, nowait = true })
	vim.api.nvim_buf_create_user_command(buf, "QuickfixNotesQuit", save, { nargs = 0 })
	vim.api.nvim_set_current_win(win)
	vim.cmd("cnoreabbrev <expr> <buffer> q getcmdtype() ==# ':' && getcmdline() ==# 'q' ? 'QuickfixNotesQuit' : 'q'")
	vim.cmd("startinsert")
end

return M
