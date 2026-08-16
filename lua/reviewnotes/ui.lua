local M = {}

---Floating note editor. callback(result) with result = { text } or nil.
---@param opts { location: table, existing?: table }
---@param callback fun(result: { text: string }|nil)
function M.note_input(opts, callback)
	opts = opts or {}
	local loc = opts.location or {}

	local prev_win = vim.api.nvim_get_current_win()
	local width = math.min(76, math.max(48, vim.o.columns - 8))
	local height = math.min(14, math.max(7, vim.o.lines - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " " .. M.title(loc) .. " ",
		title_pos = "center",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
	})

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	-- Plain text filetype: markdown would trigger render-markdown's per-keystroke
	-- re-render (visible as cursor blinking in the float).
	vim.bo[buf].filetype = "text"

	local initial = opts.existing and opts.existing.text or ""
	vim.api.nvim_buf_set_lines(
		buf,
		0,
		-1,
		false,
		initial ~= "" and vim.split(initial, "\n", { plain = true }) or { "" }
	)

	local closed = false

	local function update_footer()
		vim.api.nvim_buf_set_extmark(
			buf,
			vim.api.nvim_create_namespace("reviewnotes_ui"),
			math.max(0, vim.api.nvim_buf_line_count(buf) - 1),
			0,
			{
				virt_text = { { "  |  <C-s> save  q/:q close (saves)  ", "Comment" } },
				virt_text_pos = "right_align",
			}
		)
	end

	local function close(result)
		if closed then
			return
		end
		closed = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if prev_win and vim.api.nvim_win_is_valid(prev_win) then
			vim.api.nvim_set_current_win(prev_win)
		end
		vim.cmd("stopinsert")
		callback(result)
	end

	local function save()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		while #lines > 0 and lines[#lines] == "" do
			lines[#lines] = nil
		end
		local text = table.concat(lines, "\n")
		if text == "" then
			close(nil)
		else
			close({ text = text })
		end
	end

	update_footer()
	vim.keymap.set({ "n", "i" }, "<C-s>", save, { buffer = buf, nowait = true })
	-- q / :q close the float; save if there's text (discard if empty).
	vim.keymap.set("n", "q", save, { buffer = buf, nowait = true })
	vim.api.nvim_buf_create_user_command(buf, "ReviewnotesQuit", save, { nargs = 0 })

	vim.api.nvim_set_current_win(win)
	vim.cmd("cnoreabbrev <expr> <buffer> q getcmdtype() ==# ':' && getcmdline() ==# 'q' ? 'ReviewnotesQuit' : 'q'")
	vim.cmd("startinsert")
end

function M.title(loc)
	local parts = {}
	if loc.file then
		parts[#parts + 1] = loc.file
	end
	if loc.line then
		local suffix = loc.line_end and loc.line_end ~= loc.line and ("-%d"):format(loc.line_end) or ""
		parts[#parts + 1] = "L" .. loc.line .. suffix
	end
	if loc.side then
		parts[#parts + 1] = loc.side
	end
	if loc.branch then
		parts[#parts + 1] = loc.branch
	end
	if loc.hash then
		parts[#parts + 1] = loc.hash:sub(1, 7)
	end
	return #parts > 0 and table.concat(parts, " | ") or "reviewnotes"
end

return M
