local M = {}
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local location = require("quickfix_review.location")
local resolver = require("quickfix_review.resolver")
local namespace = vim.api.nvim_create_namespace("quickfix_review")
local visible, configured, enabled = true, true, true
local hover_win
local hover_all = {}
local hover_all_refreshing = false
local glyph, float_enabled, float_delay, float_permanent = "󰏫", true, 500, false
local quickfix_inline, quickfix_float_enabled, quickfix_float_delay, quickfix_float_permanent, quickfix_command =
	true, true, 500, false, true
local agent_label_enabled, agent_label_text = true, "󰚩"

local function indicator(note, quickfix)
	if annotations.origin(note) == "agent" then
		return (not quickfix or agent_label_enabled) and agent_label_text or nil
	end
	return glyph
end

local function close_hover()
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		vim.api.nvim_win_close(hover_win, true)
	end
	hover_win = nil
end

local function anchor(r, note, bufnr)
	if r and type(r.anchor) == "function" then
		local ok, line = pcall(r.anchor, note.location, bufnr or vim.api.nvim_get_current_buf())
		if ok and line then
			return line
		end
	end
	return note.location.line_end or note.location.line
end

local function contains(note, line)
	local first = note.location.line
	local last = note.location.line_end or first
	return first and line >= math.min(first, last) and line <= math.max(first, last)
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
end

local function display_lines(r, note, bufnr)
	if r and type(r.display_lines) == "function" then
		local ok, lines = pcall(r.display_lines, note.location, bufnr or vim.api.nvim_get_current_buf())
		if ok and type(lines) == "table" then
			return lines
		end
		return {}
	end
	local first, last = note.location.line, anchor(r, note, bufnr)
	return first == last and { first } or { first, last }
end

local function at_endpoint(r, note, line, bufnr)
	for _, endpoint in ipairs(display_lines(r, note, bufnr)) do
		if line == endpoint then
			return true
		end
	end
	return false
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

local function close_hover_all(winid, disable)
	local state = hover_all[winid]
	if not state then
		return
	end
	for _, popup in ipairs(state.popups) do
		if vim.api.nvim_win_is_valid(popup) then
			vim.api.nvim_win_close(popup, true)
		end
	end
	state.popups = {}
	if disable then
		hover_all[winid] = nil
	end
end

local function close_all_hover_all()
	for winid in pairs(hover_all) do
		close_hover_all(winid, true)
	end
end

local function visible_range(winid)
	local first, last
	vim.api.nvim_win_call(winid, function()
		first, last = vim.fn.line("w0"), vim.fn.line("w$")
	end)
	return first, last
end

local function open_note_popup(state, note, line, offset)
	local lines = vim.split(note.text or "", "\n", { plain = true })
	local source_width = vim.api.nvim_win_get_width(state.winid)
	local width = 1
	for _, text in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(text))
	end
	width = math.min(width, math.max(1, source_width - 4))
	local height = math.max(1, math.min(#lines, 10))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	local popup = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = state.winid,
		bufpos = { line - 1, 0 },
		row = 1,
		col = math.max(0, source_width - width - 4 - offset * 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 60 + offset,
		title = annotations.origin(note) == "agent" and " Agent note " or " Quickfix note ",
		title_pos = "center",
	})
	vim.wo[popup].wrap = true
	state.popups[#state.popups + 1] = popup
end

local function refresh_hover_all(winid)
	local state = hover_all[winid]
	if hover_all_refreshing or not state then
		return
	end
	if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= state.bufnr then
		close_hover_all(winid, true)
		return
	end
	hover_all_refreshing = true
	close_hover_all(winid, false)
	local current, r = resolver.location(state.bufnr, winid), resolver.detect(state.bufnr, winid)
	if current and r then
		local first_visible, last_visible = visible_range(winid)
		local offsets = {}
		for _, note in ipairs(collect()) do
			if matches(note, current) then
				for _, line in ipairs(display_lines(r, note, state.bufnr)) do
					if line and line >= first_visible and line <= last_visible then
						offsets[line] = (offsets[line] or 0) + 1
						open_note_popup(state, note, line, offsets[line] - 1)
						break
					end
				end
			end
		end
	end
	hover_all_refreshing = false
end

function M.setup(opts)
	opts = opts or {}
	close_all_hover_all()
	local nerd_font = opts.nerd_font ~= false
	configured, glyph = opts.inline ~= false, opts.glyph == nil and (nerd_font and "󰏫" or "✎") or opts.glyph
	local float = opts.float or {}
	float_enabled, float_delay, float_permanent = float.enabled ~= false, float.delay or 500, float.permanent == true
	local quickfix = opts.quickfix or {}
	local quickfix_float = quickfix.float or {}
	quickfix_inline = quickfix.inline ~= false
	local agent_label = quickfix.agent_label or {}
	agent_label_enabled = agent_label.enabled ~= false
	agent_label_text = agent_label.text == nil and (nerd_font and "󰚩" or "AGENT") or agent_label.text
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
	local hover_group = vim.api.nvim_create_augroup("QuickfixReviewHoverAll", { clear = true })
	vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
		group = hover_group,
		callback = function()
			for winid in pairs(hover_all) do
				refresh_hover_all(winid)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = hover_group,
		callback = function()
			close_hover_all(vim.api.nvim_get_current_win(), true)
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
		if current then
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			for index, item in ipairs(current.items) do
				local note = annotations.get(item)
				local text = note and indicator(note, true)
				local highlight = text and "QuickfixReviewMark" or nil
				if text and text ~= "" and index <= line_count then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, index - 1, 0, {
						virt_text = { { "  " .. text, highlight } },
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
			local text = indicator(note)
			for _, line in ipairs(display_lines(r, note, bufnr)) do
				if line and line >= 1 and line <= count and text and text ~= "" then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line - 1, 0, {
						virt_text = { { "  " .. text, "QuickfixReviewMark" } },
						virt_text_pos = "eol",
						priority = 200,
					})
				end
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

local function append_note(lines, note)
	if #lines > 0 then
		lines[#lines + 1] = ""
	end
	vim.list_extend(lines, vim.split(note.text or "", "\n", { plain = true }))
end

local function open_hover(lines, title)
	if #lines == 0 then
		return
	end
	local _, win = vim.lsp.util.open_floating_preview(lines, "text", {
		border = "rounded",
		focusable = false,
		max_width = math.min(80, vim.o.columns - 8),
		title = title,
		title_pos = "center",
		close_events = { "CursorMoved", "InsertCharPre", "BufLeave", "WinLeave" },
	})
	hover_win = win
end

function M.hover_qf(bufnr, opts)
	if not quickfix_command or not visible then
		return
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "quickfix" then
		return M.hover(bufnr, opts)
	end
	local current = lists.current()
	local note = current and current.item and annotations.get(current.item)
	if not note then
		return
	end
	local title = annotations.origin(note) == "agent" and " Agent note " or " Quickfix note "
	open_hover(vim.split(note.text or "", "\n", { plain = true }), title)
end

function M.hover(bufnr, opts)
	opts = opts or {}
	if bufnr and vim.bo[bufnr].buftype == "quickfix" then
		return M.hover_qf(bufnr, opts)
	end
	if not opts.force and not M.float_delay() then
		return
	end
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		if not opts.force then
			return
		end
		close_hover()
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local current, r = resolver.location(bufnr), resolver.detect(bufnr)
	if not current or not r then
		return
	end
	local line, lines = vim.api.nvim_win_get_cursor(0)[1], {}
	for _, note in ipairs(collect()) do
		local at_line = opts.force and type(r.display_lines) ~= "function" and contains(note, line)
			or at_endpoint(r, note, line, bufnr)
		if matches(note, current) and at_line then
			append_note(lines, note)
		end
	end
	open_hover(lines, " Quickfix note ")
end

function M.hover_all(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	if hover_all[winid] then
		close_hover_all(winid, true)
		return false
	end
	if vim.bo[bufnr].buftype == "quickfix" then
		return false
	end
	local current, r = resolver.location(bufnr, winid), resolver.detect(bufnr, winid)
	if not current or not r then
		return false
	end
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		close_hover()
	end
	hover_all[winid] = { winid = winid, bufnr = bufnr, popups = {} }
	refresh_hover_all(winid)
	return true
end

function M.refresh()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		M.render(vim.api.nvim_win_get_buf(win))
	end
	for winid in pairs(hover_all) do
		refresh_hover_all(winid)
	end
end
function M.hide()
	enabled, visible = false, false
	close_hover()
	close_all_hover_all()
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
