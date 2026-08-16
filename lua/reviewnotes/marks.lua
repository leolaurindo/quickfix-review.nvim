local M = {}

local store = require("reviewnotes.store")
local resolver = require("reviewnotes.resolver")

local NS = vim.api.nvim_create_namespace("reviewnotes")
local visible = true
local configured_visible = true
local mode_enabled = true
local hover_win
local glyph = "▲"
local float_enabled = true
local float_delay = 500
local float_permanent = false

-- Candidate highlight groups whose fg approximates the theme accent.
local ACCENT_CANDIDATES = { "@keyword", "Keyword", "Function", "Special", "DiagnosticInfo", "String" }

local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	if ok and hl and hl.fg then
		return hl.fg
	end
end

local function accent_color()
	for _, group in ipairs(ACCENT_CANDIDATES) do
		local fg = hl_fg(group)
		if fg and fg ~= "NONE" then
			return fg
		end
	end
	return "#7aa2f7" -- fallback (tokyonight blue)
end

local function close_hover()
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		vim.api.nvim_win_close(hover_win, true)
	end
	hover_win = nil
end

local function update_visibility()
	visible = configured_visible and mode_enabled
	if not visible then
		close_hover()
	end
end

function M.setup(opts)
	opts = opts or {}
	local float = opts.float or {}
	configured_visible = opts.inline ~= false
	glyph = opts.glyph == nil and "▲" or opts.glyph
	float_enabled = float.enabled ~= false
	float_delay = float.delay or 500
	float_permanent = float.permanent == true
	update_visibility()
	if not float_enabled then
		close_hover()
	end
	local accent = accent_color()
	vim.api.nvim_set_hl(0, "ReviewNotesMark", { fg = accent })
	-- Re-tint when the colorscheme changes.
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("reviewnotes_hl", { clear = true }),
		callback = function()
			vim.api.nvim_set_hl(0, "ReviewNotesMark", { fg = accent_color() })
		end,
	})
end

---Compute the buffer line for a note in `bufnr` via the resolver's anchor.
---For ranges, anchor at the bottom of the selection.
---@return integer|nil
local function anchor_line(resolver_r, note, bufnr)
	if resolver_r and type(resolver_r.anchor) == "function" then
		local ok, lnum = pcall(resolver_r.anchor, note, bufnr)
		if ok and lnum then
			return lnum
		end
	end
	-- Fallback: same-file notes attach at note.line (works for normal buffers).
	if note.line_end and note.line_end ~= note.line then
		return note.line_end
	end
	return note.line
end

---Render notes for the current buffer if its resolver allows inline marks.
function M.render(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
	if not visible then
		return
	end

	local r = resolver.detect(bufnr)
	if not r or not r.renderable then
		return
	end

	local loc = resolver.location(bufnr)
	if not loc or not loc.file then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for _, note in ipairs(store.for_file(loc.file)) do
		local lnum = anchor_line(r, note, bufnr)
		if lnum and lnum >= 1 and lnum <= line_count then
			if glyph and glyph ~= "" then
				pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, 0, {
					virt_text = { { "  " .. glyph, "ReviewNotesMark" } },
					virt_text_pos = "eol",
					priority = 200,
				})
			end
		end
	end
end

function M.float_delay()
	if visible and float_enabled then
		return float_permanent and 0 or float_delay
	end
end

---Open the note under the cursor in a diagnostic-style hover float.
function M.hover(bufnr)
	if M.float_delay() == nil then
		return
	end
	if hover_win and vim.api.nvim_win_is_valid(hover_win) then
		return
	end
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local r = resolver.detect(bufnr)
	local loc = resolver.location(bufnr)
	if not r or not loc or not loc.file then
		return
	end
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = {}
	for _, note in ipairs(store.for_file(loc.file)) do
		if anchor_line(r, note, bufnr) == line then
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
		title = " Review note ",
		title_pos = "center",
		close_events = { "CursorMoved", "InsertCharPre", "BufLeave", "WinLeave" },
	})
	hover_win = win
	vim.api.nvim_create_autocmd("WinClosed", {
		once = true,
		pattern = tostring(win),
		callback = function()
			hover_win = nil
		end,
	})
end

function M.refresh()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		M.render(vim.api.nvim_win_get_buf(win))
	end
end

function M.hide()
	mode_enabled = false
	update_visibility()
	M.refresh()
end

function M.show()
	mode_enabled = true
	update_visibility()
	M.refresh()
end

function M.toggle()
	if mode_enabled then
		M.hide()
	else
		M.show()
	end
	return mode_enabled
end

return M
