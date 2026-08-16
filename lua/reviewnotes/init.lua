local M = {}

local config = require("reviewnotes.config")
local resolver = require("reviewnotes.resolver")
local store = require("reviewnotes.store")
local marks = require("reviewnotes.marks")
local ui = require("reviewnotes.ui")
local render = require("reviewnotes.render")
local sender = require("reviewnotes.sender")
local picker = require("reviewnotes.picker")
local hover_tick = 0

local function notify(msg, level)
	vim.notify(msg, level, { title = "reviewnotes" })
end

-- --- location helpers ------------------------------------------------------

local function current_location()
	local ok, loc = pcall(resolver.location, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win())
	if not ok or not loc then
		return nil, "could not resolve a location in this buffer"
	end
	if not loc.file then
		return nil, "resolver returned no file"
	end
	return loc
end

local function visual_range_location()
	local start_line = vim.fn.line("'<")
	local stop_line = vim.fn.line("'>")
	if start_line > stop_line then
		start_line, stop_line = stop_line, start_line
	end
	local ok, loc = pcall(resolver.range_location, vim.api.nvim_get_current_buf(), start_line, stop_line)
	if not ok or not loc then
		return nil, "could not resolve range in this buffer"
	end
	if not loc.file then
		return nil, "resolver returned no file"
	end
	return loc
end

-- --- actions ---------------------------------------------------------------

local function add_note_at(loc, bufnr)
	local existing = store.at(loc)
	ui.note_input({ location = loc, existing = existing }, function(result)
		if not result then
			return
		end
		if existing then
			store.update(existing.id, { text = result.text })
			notify("reviewnotes: note updated", vim.log.levels.INFO)
		else
			store.add(loc, result.text)
			notify(("reviewnotes: note added (%d total)"):format(store.count()), vim.log.levels.INFO)
		end
		marks.render(bufnr)
	end)
end

function M.note()
	if vim.fn.mode():match("[vV\022]") then
		local loc, err = visual_range_location()
		if not loc then
			notify(err, vim.log.levels.WARN)
			return
		end
		add_note_at(loc, vim.api.nvim_get_current_buf())
		return
	end
	local loc, err = current_location()
	if not loc then
		notify(err, vim.log.levels.WARN)
		return
	end
	add_note_at(loc, vim.api.nvim_get_current_buf())
end

-- :ReviewNote with a range (e.g. from visual mode `:'<,'>ReviewNote`).
function M.note_range(line1, line2)
	local ok, loc = pcall(resolver.range_location, vim.api.nvim_get_current_buf(), line1, line2)
	if not ok or not loc or not loc.file then
		notify("could not resolve range in this buffer", vim.log.levels.WARN)
		return
	end
	add_note_at(loc, vim.api.nvim_get_current_buf())
end

function M.send()
	local loc, err = current_location()
	if not loc then
		notify(err, vim.log.levels.WARN)
		return
	end
	local note = store.at(loc)
	if not note then
		notify("reviewnotes: no note at this location", vim.log.levels.INFO)
		return
	end
	local md = render.note_line(note) .. "\n"
	local ok, result = sender.send(md, config.get().send_opts)
	if ok then
		notify("reviewnotes: sent note via " .. sender.active())
	else
		notify("send failed: " .. result, vim.log.levels.ERROR)
	end
end

function M.export()
	local notes = store.all()
	if #notes == 0 then
		notify("reviewnotes: no notes to export", vim.log.levels.INFO)
		return
	end
	local md = render.render(notes)
	local ok, result = sender.send(md, config.get().send_opts)
	if not ok then
		notify("export failed: " .. result, vim.log.levels.ERROR)
		return
	end
	notify(
		("reviewnotes: exported %d notes via %s (%s)"):format(#notes, sender.active(), result or "ok"),
		vim.log.levels.INFO
	)
end

function M.export_and_clear()
	M.export()
	M.clear()
end

function M.clear()
	local count = store.clear()
	marks.refresh()
	notify(("reviewnotes: cleared %d notes"):format(count), vim.log.levels.INFO)
end

function M.list()
	picker.open(store.all(), config.get().list)
end

-- Always send the notes to the quickfix list, regardless of the configured
-- list backend. Falls back to the configured backend if quickfix is the default.
function M.list_quickfix()
	picker.open(store.all(), "quickfix")
end

local function navigate(step)
	local notes = store.all()
	if #notes == 0 then
		notify("reviewnotes: no notes", vim.log.levels.INFO)
		return
	end
	local loc = current_location()
	local index
	if loc then
		for i, note in ipairs(notes) do
			local last_line = note.line_end or note.line
			if
				note.file == loc.file
				and loc.line >= note.line
				and loc.line <= last_line
				and note.side == loc.side
				and note.hash == loc.hash
			then
				index = i
				break
			end
		end
	end
	index = index and (index - 1 + step) % #notes + 1 or (step > 0 and 1 or #notes)
	picker.jump(notes[index])
end

function M.next()
	navigate(1)
end

function M.prev()
	navigate(-1)
end

-- --- scope / branch tracking ----------------------------------------------

local function reload_scope()
	local root = store.repo_root() or vim.fn.getcwd()
	root = store.repo_root(root) or root
	local changed = store.switch_scope(root)
	if changed then
		marks.refresh()
	end
end

-- --- setup -----------------------------------------------------------------

function M.setup(opts)
	config.setup(opts)

	-- Resolvers: specific first, normal last.
	resolver.register(require("reviewnotes.resolvers.codediff"))
	resolver.register(require("reviewnotes.resolvers.differ"))
	resolver.register(require("reviewnotes.resolvers.neogit"))
	resolver.register(require("reviewnotes.resolvers.diffs"))
	resolver.register(require("reviewnotes.resolvers.native"))
	resolver.register(require("reviewnotes.resolvers.normal"))

	-- Senders.
	sender.register(require("reviewnotes.senders.clipboard"))
	sender.register(require("reviewnotes.senders.file"))
	sender.register(require("reviewnotes.senders.sidekick"))
	sender.set_default(config.get().send)

	marks.setup(config.get())

	reload_scope()
	marks.refresh()

	-- Re-render inline marks on buffer entry and when codediff swaps files.
	local group = vim.api.nvim_create_augroup("reviewnotes", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(ev)
			marks.render(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function(ev)
			hover_tick = hover_tick + 1
			local tick = hover_tick
			local delay = marks.float_delay()
			if delay == nil then
				return
			end
			vim.defer_fn(function()
				if tick == hover_tick and vim.api.nvim_get_current_buf() == ev.buf then
					marks.hover(ev.buf)
				end
			end, delay)
		end,
	})
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = reload_scope,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "NeogitBranchCheckout", "NeogitBranchCreate", "NeogitReset" },
		callback = reload_scope,
	})

	local codediff = require("reviewnotes.resolvers.codediff")
	if type(codediff.on_attach) == "function" then
		pcall(codediff.on_attach, function()
			marks.refresh()
		end)
	end

	-- Commands.
	local keys = config.get().keys
	local function cmd(name, fn, extra)
		vim.api.nvim_create_user_command(name, fn, extra or {})
	end
	cmd("ReviewNote", function(cmd_opts)
		if cmd_opts.range and cmd_opts.range > 0 then
			M.note_range(cmd_opts.line1, cmd_opts.line2)
		else
			M.note()
		end
	end, { desc = "reviewnotes: add note at location", range = true })
	cmd("ReviewSend", function()
		M.send()
	end, { desc = "reviewnotes: send note at cursor" })
	cmd("ReviewExport", function()
		M.export()
	end, { desc = "reviewnotes: export all notes" })
	cmd("ReviewExportAndClear", function()
		M.export_and_clear()
	end, { desc = "reviewnotes: export then clear" })
	cmd("ReviewClear", function()
		M.clear()
	end, { desc = "reviewnotes: clear all notes" })
	cmd("ReviewList", function()
		M.list()
	end, { desc = "reviewnotes: list notes" })
	cmd("ReviewQf", function()
		M.list_quickfix()
	end, { desc = "reviewnotes: send notes to quickfix" })
	cmd("ReviewNext", function()
		M.next()
	end, { desc = "reviewnotes: jump to next note" })
	cmd("ReviewPrev", function()
		M.prev()
	end, { desc = "reviewnotes: jump to previous note" })
	cmd("ReviewHide", function()
		marks.hide()
	end, { desc = "reviewnotes: hide inline marks" })
	cmd("ReviewShow", function()
		marks.show()
	end, { desc = "reviewnotes: show inline marks" })
	cmd("ReviewMode", function()
		local enabled = marks.toggle()
		notify("reviewnotes: mode " .. (enabled and "on" or "off"), vim.log.levels.INFO)
	end, { desc = "reviewnotes: toggle visual review mode" })

	local map = function(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { desc = desc })
		vim.keymap.set("v", lhs, rhs, { desc = desc })
	end
	map(keys.note, function()
		M.note()
	end, "ReviewNote")
	map(keys.send, function()
		M.send()
	end, "ReviewSend")
	map(keys.export, function()
		M.export()
	end, "ReviewExport")
	map(keys.export_and_clear, function()
		M.export_and_clear()
	end, "ReviewExportAndClear")
	map(keys.clear, function()
		M.clear()
	end, "ReviewClear")
	map(keys.list, function()
		M.list()
	end, "ReviewList")
	vim.keymap.set("n", keys.next, M.next, { desc = "ReviewNext" })
	vim.keymap.set("n", keys.prev, M.prev, { desc = "ReviewPrev" })
end

return M
