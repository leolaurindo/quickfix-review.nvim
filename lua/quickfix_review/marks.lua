local M = {}
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local location = require("quickfix_review.location")
local resolver = require("quickfix_review.resolver")
local namespace = vim.api.nvim_create_namespace("quickfix_review")
local visible, configured, enabled = true, true, true
local hover_win
local glyph, float_enabled, float_delay, float_permanent = "▲", true, 500, false
local quickfix_inline, quickfix_float_enabled, quickfix_float_delay, quickfix_float_permanent, quickfix_command =
	true, true, 500, false, true

local function close_hover()
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		vim.api.nvim_win_close(hover_win, true)
	end
	hover_win = nil
end

local function anchor(r, note)
	if r and type(r.anchor) == "function" then
		local ok, line = pcall(r.anchor, note.location, vim.api.nvim_get_current_buf())
		if ok and line then
			return line
		end
	end
	return note.location.line_end or note.location.line
end

local function matches(note, current)
	local value = location.canonical(note.location)
	return value
		and current
		and value.root == current.root
		and value.path == current.path
		and (not value.side or value.side == current.side)
		and (not value.revision or value.revision == current.revision)
		and (not value.hash or value.hash == current.hash)
		and (not value.resolver or value.resolver == current.resolver)
end

local function collect()
	local out, seen = {}, {}
	local function add(target)
		lists.for_each_annotation(target, function(note)
			if not seen[note.id] then
				seen[note.id] = true
				out[#out + 1] = note
			end
		end)
	end
	local owned = lists.find_owned()
	if owned then
		add({ kind = "quickfix", id = owned.id })
	end
	local current = lists.current()
	if current then
		add({ kind = current.kind, id = current.id, winid = current.winid })
	end
	return out
end

function M.setup(opts)
	opts = opts or {}
	configured, glyph = opts.inline ~= false, opts.glyph == nil and "▲" or opts.glyph
	local float = opts.float or {}
	float_enabled, float_delay, float_permanent = float.enabled ~= false, float.delay or 500, float.permanent == true
	local quickfix = opts.quickfix or {}
	local quickfix_float = quickfix.float or {}
	quickfix_inline = quickfix.inline ~= false
	quickfix_float_enabled = quickfix_float.enabled ~= false
	quickfix_float_delay = quickfix_float.delay or 500
	quickfix_float_permanent = quickfix_float.permanent == true
	quickfix_command = quickfix_float.command ~= false
	vim.api.nvim_set_hl(0, "QuickfixReviewMark", { link = "DiagnosticInfo" })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("QuickfixReviewHighlights", { clear = true }),
		callback = function()
			vim.api.nvim_set_hl(0, "QuickfixReviewMark", { link = "DiagnosticInfo" })
		end,
	})
	visible = configured and enabled
end

function M.render(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	if not visible then
		return
	end
	if vim.bo[bufnr].buftype == "quickfix" then
		if not quickfix_inline then
			return
		end
		local current = lists.current()
		local owned = current
			and type(current.list.context) == "table"
			and type(current.list.context.quickfix_review) == "table"
			and current.list.context.quickfix_review.role == "notes"
		if current and not owned then
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			for index, item in ipairs(current.items) do
				local note = annotations.get(item)
				if note and index <= line_count and glyph and glyph ~= "" then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, index - 1, 0, {
						virt_text = { { "  " .. glyph, "QuickfixReviewMark" } },
						virt_text_pos = "eol",
						hl_mode = "combine",
					})
				end
			end
		end
		return
	end
	local r = resolver.detect(bufnr)
	local current = resolver.location(bufnr)
	if not r or not r.renderable or not current then
		return
	end
	local count = vim.api.nvim_buf_line_count(bufnr)
	for _, note in ipairs(collect()) do
		if matches(note, current) then
			local line = anchor(r, note)
			if line and line >= 1 and line <= count and glyph and glyph ~= "" then
				pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line - 1, 0, {
					virt_text = { { "  " .. glyph, "QuickfixReviewMark" } },
					virt_text_pos = "eol",
					priority = 200,
				})
			end
		end
	end
end

function M.float_delay()
	return visible and float_enabled and (float_permanent and 0 or float_delay) or nil
end

function M.quickfix_float_delay()
	if visible and quickfix_float_enabled then
		return quickfix_float_permanent and 0 or quickfix_float_delay
	end
end

function M.hover_qf(bufnr)
	if not quickfix_command or not visible then
		return
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "quickfix" then
		return M.hover(bufnr)
	end
	local current = lists.current()
	local note = current and current.item and annotations.get(current.item)
	if not note then
		return
	end
	local lines = vim.split(note.text or "", "\n", { plain = true })
	local _, win = vim.lsp.util.open_floating_preview(lines, "text", {
		border = "rounded",
		focusable = false,
		max_width = math.min(80, vim.o.columns - 8),
		title = " Quickfix note ",
		title_pos = "center",
		close_events = { "CursorMoved", "InsertCharPre", "BufLeave", "WinLeave" },
	})
	hover_win = win
end

function M.hover(bufnr)
	if bufnr and vim.bo[bufnr].buftype == "quickfix" then
		return M.hover_qf(bufnr)
	end
	if not M.float_delay() or (hover_win and vim.api.nvim_win_is_valid(hover_win)) then
		return
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local current, r = resolver.location(bufnr), resolver.detect(bufnr)
	if not current or not r then
		return
	end
	local line, lines = vim.api.nvim_win_get_cursor(0)[1], {}
	for _, note in ipairs(collect()) do
		if matches(note, current) and anchor(r, note) == line then
			if #lines > 0 then
				lines[#lines + 1] = ""
			end
			vim.list_extend(lines, vim.split(note.text or "", "\n", { plain = true }))
		end
	end
	if #lines == 0 then
		return
	end
	local _, win = vim.lsp.util.open_floating_preview(lines, "text", {
		border = "rounded",
		focusable = false,
		max_width = math.min(80, vim.o.columns - 8),
		title = " Quickfix note ",
		title_pos = "center",
		close_events = { "CursorMoved", "InsertCharPre", "BufLeave", "WinLeave" },
	})
	hover_win = win
end

function M.refresh()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		M.render(vim.api.nvim_win_get_buf(win))
	end
end
function M.hide()
	enabled, visible = false, false
	close_hover()
	M.refresh()
end
function M.show()
	enabled, visible = true, configured
	M.refresh()
end
function M.toggle()
	if enabled then
		M.hide()
	else
		M.show()
	end
	return enabled
end

return M
