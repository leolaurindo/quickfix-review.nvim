local M = {}
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local location = require("quickfix_review.location")
local resolver = require("quickfix_review.resolver")
local namespace = vim.api.nvim_create_namespace("quickfix_review")
local visible, configured, enabled = true, true, true
-- Hover redraw discipline - the rules that keep the note popup from flickering.
-- They came from a real bug: the hover was rebuilt on every movement, so each stop
-- painted a fresh frame (and hid the cursor while doing it) and the next movement
-- erased it. When touching this code:
--   * never draw from CursorMoved unless the *payload* under the cursor changed
--     (see hover_payload/hover_follow): "the cursor moved" is not a reason to draw;
--   * never close and reopen the float to change its text - rewrite it through
--     `_update_win` (what vim.diagnostic/vim.lsp floats do) and only recreate the
--     window when the content height changes;
--   * never list "CursorMoved" in the float's close_events;
--   * rails follow the window, not the cursor: refresh them from BufEnter/WinScrolled/
--     WinResized and never run M.render() from a scroll handler;
--   * anything scheduled with vim.defer_fn() from CursorMoved runs on an idle screen,
--     so it must be a no-op unless something actually changed;
--   * and it must not do blocking work either. The hover path used to resolve the repo
--     root with a synchronous `git rev-parse` (location.repo_root), i.e. a git process on
--     every cursor move and every hover; that was the last thing making this plugin's
--     users see a flickering cursor. Anything on this path has to be cheap and cached.
local hover_win
local hover_buf
local hover_key -- payload currently displayed (nil when nothing is shown)
local hover_auto = true -- automatic hover; runtime switch: M.hover_toggle()
local hover_lines_count
local hover_geometry -- last placed row/col/width/height, so an unchanged hover never moves
local hover_group = vim.api.nvim_create_augroup("QuickfixReviewHover", { clear = true })
local hover_all = {}
local rails = {}
local hover_all_refreshing = false
local rail_rendering = false
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
	pcall(vim.api.nvim_clear_autocmds, { group = hover_group })
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		local buf = hover_buf
		vim.api.nvim_win_close(hover_win, true)
		if buf and vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	hover_win, hover_buf, hover_key, hover_lines_count, hover_geometry = nil, nil, nil, nil, nil
end

-- Where the hover belongs: next to the end of the text on the line it refers to (the
-- cursor's line, not the end of a range), so it never covers the cursor or the text.
-- Returns 0-based screen row/col plus the content size.
local function hover_geometry_for(lines)
	local text_width = 0
	for _, line in ipairs(lines) do
		text_width = math.max(text_width, vim.fn.strdisplaywidth(line))
	end
	local width = math.min(text_width + 2, math.min(80, vim.o.columns - 8))
	local height = #lines

	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()
	local pos = vim.fn.screenpos(0, lnum, math.max(1, #line))
	local row, col
	if type(pos) == "table" and pos.row > 0 then
		row, col = pos.row - 1, pos.col + 1
	else
		row, col = vim.fn.winline() - 1, vim.fn.wincol()
	end
	return math.max(0, math.min(row, vim.o.lines - height - 3)),
		math.max(0, math.min(col, vim.o.columns - width - 2)),
		width,
		height
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

local function matches(note, current, r, bufnr)
	local value = location.canonical(note.location)
	if not value or not current or value.root ~= current.root or value.path ~= current.path then
		return false
	end
	if r and type(r.matches) == "function" then
		local ok, matched = pcall(r.matches, value, bufnr)
		if ok and matched ~= nil then
			return matched
		end
	end
	return (not value.side or value.side == current.side)
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

local function close_rail_panel(state)
	if state.panel and vim.api.nvim_win_is_valid(state.panel) then
		vim.api.nvim_win_close(state.panel, true)
	end
	state.panel = nil
end

local function close_rail(winid)
	local state = rails[winid]
	if not state then
		return
	end
	close_rail_panel(state)
	if state.badge and vim.api.nvim_win_is_valid(state.badge) then
		vim.api.nvim_win_close(state.badge, true)
	end
	rails[winid] = nil
end

local function matching_notes(bufnr, winid)
	local current, r = resolver.location(bufnr, winid), resolver.detect(bufnr, winid)
	if not current or not r then
		return {}, r
	end
	local notes = {}
	for _, note in ipairs(collect()) do
		local value = location.canonical(note.location)
		if (r.renderable and matches(note, current, r, bufnr))
			or (not r.renderable and value and value.root == current.root and value.path == current.path) then
			notes[#notes + 1] = note
		end
	end
	table.sort(notes, function(a, b)
		local a_line, b_line = a.location.line or math.huge, b.location.line or math.huge
		return a_line == b_line and a.id < b.id or a_line < b_line
	end)
	return notes, r
end

local function same_notes(a, b)
	if #a ~= #b then
		return false
	end
	for index, note in ipairs(a) do
		if note.id ~= b[index].id then
			return false
		end
	end
	return true
end

local function render_rail(bufnr)
	if rail_rendering then
		return
	end
	rail_rendering = true
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
			local notes, r = matching_notes(bufnr, winid)
			if not r or r.renderable or #notes == 0 then
				close_rail(winid)
			else
				local state = rails[winid]
				if state and state.bufnr == bufnr and vim.api.nvim_win_is_valid(state.badge) and same_notes(state.notes, notes) then
					state.notes = notes
				else
					close_rail(winid)
					local text = indicator(notes[1]) .. " " .. #notes
					local width = vim.fn.strdisplaywidth(text)
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
					vim.bo[buf].bufhidden = "wipe"
					vim.bo[buf].modifiable = false
					local badge = vim.api.nvim_open_win(buf, false, {
						relative = "win",
						win = winid,
						row = 0,
						col = math.max(0, vim.api.nvim_win_get_width(winid) - width),
						width = width,
						height = 1,
						style = "minimal",
						focusable = false,
						zindex = 60,
					})
					vim.api.nvim_buf_add_highlight(buf, -1, "QuickfixReviewMark", 0, 0, -1)
					rails[winid] = { winid = winid, bufnr = bufnr, badge = badge, notes = notes }
				end
			end
		end
	end
	rail_rendering = false
end

local function rail_note_title(note)
	local value = note.location
	local title = value.path or value.file or "file"
	if value.line then
		title = title .. ":" .. value.line .. (value.line_end and "-" .. value.line_end or "")
	end
	return value.side and title .. " (" .. value.side .. ")" or title
end

local function open_rail_panel(state)
	local lines = {}
	for _, note in ipairs(state.notes) do
		if #lines > 0 then
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = rail_note_title(note)
		vim.list_extend(lines, vim.split(note.text or "", "\n", { plain = true }))
	end
	local width = 1
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	local win_width = vim.api.nvim_win_get_width(state.winid)
	local panel_title = " Quickfix Review "
	-- Never narrower than its own title, or nvim clips it and shows a "<" marker.
	width = math.min(math.max(width + 2, #panel_title), math.max(1, win_width - 2))
	local padded = {}
	for _, line in ipairs(lines) do
		padded[#padded + 1] = " " .. line
	end
	local height = math.min(#lines, math.max(1, vim.api.nvim_win_get_height(state.winid) - 2))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	state.panel = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = state.winid,
		row = 1,
		col = math.max(0, win_width - width),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 61,
		title = panel_title,
		title_pos = "center",
	})
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

local function close_all_rails()
	for winid in pairs(rails) do
		close_rail(winid)
	end
end

local function close_rails_for_buffer(bufnr)
	for winid, state in pairs(rails) do
		if state.bufnr == bufnr then
			close_rail(winid)
		end
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
	width = math.min(width + 2, math.max(1, source_width - 4))
	local height = math.max(1, math.min(#lines, 10))
	local padded = {}
	for _, line in ipairs(lines) do
		padded[#padded + 1] = " " .. line
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
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
			if matches(note, current, r, state.bufnr) then
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
	close_all_rails()
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
			-- Rails/badges only need to follow the window, and render_rail() already
			-- skips windows whose notes did not change. Re-running M.render() here
			-- cleared and rewrote every mark in the buffer on each scroll (a full
			-- repaint on an otherwise idle screen). Rail rendering only.
			for winid, state in pairs(rails) do
				if vim.api.nvim_win_is_valid(winid) then
					render_rail(state.bufnr)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = hover_group,
		callback = function()
			local winid = vim.api.nvim_get_current_win()
			close_hover_all(winid, true)
			if rails[winid] then
				close_rail_panel(rails[winid])
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = hover_group,
		callback = function(event)
			close_rail(tonumber(event.match))
		end,
	})
	visible = configured and enabled
end

function M.render(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	if not visible then
		close_rails_for_buffer(bufnr)
		return
	end
	if vim.bo[bufnr].buftype == "quickfix" then
		close_rails_for_buffer(bufnr)
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
		render_rail(bufnr)
		return
	end
	render_rail(bufnr)
	local count = vim.api.nvim_buf_line_count(bufnr)
	for _, note in ipairs(collect()) do
		if matches(note, current, r, bufnr) then
			local text = indicator(note)
			for _, line in ipairs(display_lines(r, note, bufnr)) do
				if line and line >= 1 and line <= count and text and text ~= "" then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line - 1, 0, {
						virt_text = { { "  " .. text, "QuickfixReviewMark" } },
						virt_text_pos = "eol",
						hl_mode = "combine",
						priority = 200,
					})
				end
			end
		end
	end
end

function M.refresh_rail(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if visible and vim.bo[bufnr].buftype ~= "quickfix" then
		local r = resolver.detect(bufnr)
		if r and not r.renderable then
			render_rail(bufnr)
		end
	end
end

function M.float_delay()
	if not hover_auto then
		return nil -- automatic hover off: nothing is scheduled, nothing is drawn
	end
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

-- A plain box: no title. The window is sized to the note text plus one column of padding
-- per side, and the content is padded to match, so the text is not glued to the left
-- border. (A title would also be clipped, with a "<" marker, whenever the box is narrower
-- than the title.)
local function open_hover(lines, key)
	if #lines == 0 then
		return
	end
	local row, col, width, height = hover_geometry_for(lines)
	local moved = not hover_geometry
		or hover_geometry[1] ~= row
		or hover_geometry[2] ~= col
		or hover_geometry[3] ~= width
		or hover_geometry[4] ~= height

	local padded = {}
	for _, line in ipairs(lines) do
		padded[#padded + 1] = " " .. line
	end

	if hover_win and vim.api.nvim_win_is_valid(hover_win) and hover_buf and vim.api.nvim_buf_is_valid(hover_buf) then
		if key == hover_key then
			-- Same notes in the same place: nothing to draw at all.
			if not moved then
				return
			end
			-- Same notes, but the cursor's line moved on screen: reposition only.
			vim.api.nvim_win_set_config(hover_win, { relative = "editor", row = row, col = col })
			hover_geometry = { row, col, width, height }
			return
		end
		vim.bo[hover_buf].modifiable = true
		vim.api.nvim_buf_set_lines(hover_buf, 0, -1, false, padded)
		vim.bo[hover_buf].modifiable = false
		vim.api.nvim_win_set_config(hover_win, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
		})
		hover_key, hover_lines_count, hover_geometry = key, #lines, { row, col, width, height }
		return
	end

	close_hover()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 50,
	})
	vim.bo[buf].modifiable = false
	-- Not "CursorMoved": the hover is closed when the notes under the cursor change.
	for _, event in ipairs({ "InsertCharPre", "BufLeave", "WinLeave" }) do
		vim.api.nvim_create_autocmd(event, { group = hover_group, callback = close_hover })
	end
	hover_win, hover_buf, hover_key, hover_lines_count, hover_geometry = win, buf, key, #lines, { row, col, width, height }
end

-- The notes that belong under the cursor right now, as both text and identity.
-- Both hover() and hover_follow() work off this, so "same notes" is what decides
-- whether anything is drawn - never "did the cursor move". It runs on every CursorMoved
-- and from the deferred hover, so keep it cheap: no shell commands, no blocking calls,
-- no work that is not cached (a synchronous `git` call here once made every cursor move
-- fork a process and flicker the cursor).
local function hover_payload(bufnr, opts)
	opts = opts or {}
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local current, r = resolver.location(bufnr), resolver.detect(bufnr)
	if not current or not r or not r.renderable then
		return nil, nil
	end
	local line, lines = vim.api.nvim_win_get_cursor(0)[1], {}
	for _, note in ipairs(collect()) do
		local at_line = opts.force and type(r.display_lines) ~= "function" and contains(note, line)
			or at_endpoint(r, note, line, bufnr)
		if matches(note, current, r, bufnr) and at_line then
			append_note(lines, note)
		end
	end
	return lines, table.concat(lines, "\n")
end

-- CursorMoved follow-up: keep the hover while it still describes the cursor, close
-- it only when those notes are gone. Redrawing on every movement is what flickers,
-- so this function must never draw - hover() is the only path that may.
function M.hover_follow()
	if not (hover_win and vim.api.nvim_win_is_valid(hover_win)) then
		return
	end
	local _, key = hover_payload(vim.api.nvim_get_current_buf(), {})
	if key ~= hover_key then
		close_hover()
	end
end

-- Runtime switch for the *automatic* hover only: unlike M.hide/M.show this leaves
-- marks and rails alone, and :QuickfixReviewHover still shows a note on demand.
function M.hover_toggle()
	hover_auto = not hover_auto
	if not hover_auto then
		close_hover()
	end
	return hover_auto
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
	local lines = vim.split(note.text or "", "\n", { plain = true })
	open_hover(lines, table.concat(lines, "\n"))
end

function M.hover(bufnr, opts)
	opts = opts or {}
	if bufnr and vim.bo[bufnr].buftype == "quickfix" then
		return M.hover_qf(bufnr, opts)
	end
	if not opts.force and not M.float_delay() then
		return
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local lines, key = hover_payload(bufnr, opts)
	if not lines or #lines == 0 then
		close_hover() -- no notes here: this is the only thing that should close it
		return
	end
	open_hover(lines, key)
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
	if not r.renderable then
		local state = rails[winid]
		if not state or state.bufnr ~= bufnr then
			render_rail(bufnr)
			state = rails[winid]
		end
		if not state then
			return false
		end
		if state.panel then
			close_rail_panel(state)
			return false
		end
		open_rail_panel(state)
		return true
	end
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		close_hover()
	end
	hover_all[winid] = { winid = winid, bufnr = bufnr, popups = {} }
	refresh_hover_all(winid)
	return true
end

function M.refresh()
	local bufs = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			bufs[vim.api.nvim_win_get_buf(win)] = true
		end
	end
	for bufnr in pairs(bufs) do
		M.render(bufnr)
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
