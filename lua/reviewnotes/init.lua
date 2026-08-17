local M = {}

local config = require("reviewnotes.config")
local resolver = require("reviewnotes.resolver")
local store = require("reviewnotes.store")
local marks = require("reviewnotes.marks")
local ui = require("reviewnotes.ui")
local render = require("reviewnotes.render")
local sender = require("reviewnotes.sender")
local picker = require("reviewnotes.picker")
local list = require("reviewnotes.list")
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

local function persist_review_list()
	if not config.get().persist_review_list then
		return
	end
	local ok, persist = pcall(require, "quickfix_persist")
	local scope = store.scope()
	local id = picker.sync_quickfix(store.all())
	if ok and scope and id then
		persist.save({ name = config.get().quickfix_title, scope = scope, target = { kind = "quickfix", id = id } })
	end
end

local function clear_review_list()
	picker.clear_quickfix()
	local ok, persist = pcall(require, "quickfix_persist")
	local scope = store.scope()
	if ok and scope then
		persist.delete({ name = config.get().quickfix_title, scope = scope })
	end
end

local function restore_review_list()
	if not config.get().persist_review_list then
		return
	end
	local ok, persist = pcall(require, "quickfix_persist")
	local scope = store.scope()
	if not ok or not scope then
		return
	end
	local snapshot = persist.load({ name = config.get().quickfix_title, scope = scope })
	if snapshot then
		persist.restore(snapshot, { kind = "quickfix" })
	end
	if #store.all() > 0 then
		persist_review_list()
	end
end

local function add_note_at(loc, bufnr, on_saved)
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
		persist_review_list()
		if on_saved then
			on_saved()
		end
	end)
end

local function qf_note()
	local entry = list.current()
	local review_note = type(entry.item.user_data) == "table" and entry.item.user_data.quickfix_notes
	if review_note then
		local existing = store.get(review_note.id)
		if not existing then
			return
		end
		ui.note_input({ location = existing, existing = existing }, function(result)
			if result then
				store.update(existing.id, { text = result.text })
				marks.refresh()
				persist_review_list()
			end
		end)
		return
	end
	local loc = list.location(entry, store.scope() and store.scope().root)
	if not loc then
		notify("reviewnotes: current list entry has no file", vim.log.levels.WARN)
		return
	end
	add_note_at(loc, entry.item.bufnr and entry.item.bufnr > 0 and entry.item.bufnr or nil)
end

local function qf_edit()
	local entry = list.current()
	local loc = list.location(entry, store.scope() and store.scope().root)
	if not loc then
		notify("reviewnotes: current list entry has no file", vim.log.levels.WARN)
		return
	end
	if not store.at(loc) then
		notify("reviewnotes: no note at this list entry", vim.log.levels.INFO)
		return
	end
	add_note_at(loc, entry.item.bufnr and entry.item.bufnr > 0 and entry.item.bufnr or nil)
end

local function sync_review_edits(id)
	local review = vim.fn.getqflist({ id = id, all = 1 })
	if review.title ~= config.get().quickfix_title then
		return
	end
	local remaining = {}
	for _, item in ipairs(review.items or {}) do
		local note = type(item.user_data) == "table" and item.user_data.quickfix_notes
		if note then
			remaining[note.id] = true
			if store.get(note.id) then
				store.update(note.id, { text = item.text })
			end
		end
	end
	for _, note in ipairs(store.all()) do
		if not remaining[note.id] then
			store.delete(note.id)
		end
	end
	marks.refresh()
	persist_review_list()
end

local function qf_record(item, kind, list_key, index)
	local user_data = item.user_data
	local review_note = type(user_data) == "table" and user_data.quickfix_notes
	local is_review_note = review_note
		or type(user_data) == "table" and user_data.id and user_data.file and user_data.text
	user_data = review_note or user_data
	local line = is_review_note and user_data.line or item.lnum
	local loc = list.location_for(kind, item, store.scope() and store.scope().root, list_key, index)
	local note = loc and store.at(loc)
	local text = is_review_note and user_data.text
		or type(user_data) == "table" and user_data.error_text
		or item.text
		or ""
	if note and note.text ~= "" and note.text ~= text then
		text = text ~= "" and text .. "\nNote: " .. note.text or note.text
	end
	return {
		file = is_review_note and user_data.file
			or list.file(item, store.scope() and store.scope().root)
			or "[quickfix]",
		line = line and line > 0 and line or nil,
		line_end = is_review_note and user_data.line_end or item.end_lnum,
		side = is_review_note and user_data.side or nil,
		text = text,
	}
end

function M.note()
	if vim.bo.buftype == "quickfix" then
		qf_note()
		return
	end
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
		return false
	end
	local md = render.render(notes)
	local ok, result = sender.send(md, config.get().send_opts)
	if not ok then
		notify("export failed: " .. result, vim.log.levels.ERROR)
		return false
	end
	notify(
		("reviewnotes: exported %d notes via %s (%s)"):format(#notes, sender.active(), result or "ok"),
		vim.log.levels.INFO
	)
	return true
end

function M.export_qf()
	local current, kind, list_key = list.items()
	local records = {}
	for index, item in ipairs(current.items or {}) do
		if item.valid == 1 or type(item.user_data) == "table" and item.user_data.quickfix_notes then
			records[#records + 1] = qf_record(item, kind, list_key, index)
		end
	end
	if #records == 0 then
		notify("reviewnotes: no " .. kind .. "-list entries to export", vim.log.levels.INFO)
		return
	end
	local md = render.render_quickfix(records, current.title or kind)
	local ok, result = sender.send(md, config.get().send_opts)
	if not ok then
		notify("quickfix export failed: " .. result, vim.log.levels.ERROR)
		return
	end
	notify(
		("reviewnotes: exported %d %s-list entries via %s (%s)"):format(#records, kind, sender.active(), result or "ok"),
		vim.log.levels.INFO
	)
end

function M.save_list(name)
	local ok, persist = pcall(require, "quickfix_persist")
	if not ok then
		notify("quickfix_persist is required to save lists", vim.log.levels.WARN)
		return
	end
	local scope = store.scope()
	if not scope then
		notify("reviewnotes: no repository scope", vim.log.levels.WARN)
		return
	end
	local entry = list.current()
	local saved, err = persist.save({
		name = name,
		scope = scope,
		target = { kind = entry.kind, winid = entry.winid },
	})
	if not saved then
		notify("could not save list: " .. err, vim.log.levels.ERROR)
		return
	end
	notify("saved " .. entry.kind .. " list: " .. name, vim.log.levels.INFO)
end

function M.load_list(name)
	local ok, persist = pcall(require, "quickfix_persist")
	if not ok then
		notify("quickfix_persist is required to load lists", vim.log.levels.WARN)
		return
	end
	local scope = store.scope()
	if not scope then
		notify("reviewnotes: no repository scope", vim.log.levels.WARN)
		return
	end
	local snapshot, err = persist.load({ name = name, scope = scope })
	if not snapshot then
		notify("could not load list: " .. err, vim.log.levels.ERROR)
		return
	end
	local target = { kind = snapshot.kind }
	if target.kind == "location" then
		target.winid = vim.api.nvim_get_current_win()
	end
	local restored
	restored, err = persist.restore(snapshot, target)
	if not restored then
		notify("could not restore list: " .. err, vim.log.levels.ERROR)
		return
	end
	persist.watch({ name = name, scope = scope, target = target })
	notify("loaded " .. snapshot.kind .. " list: " .. name, vim.log.levels.INFO)
end

function M.export_and_clear()
	if M.export() then
		M.clear()
	end
end

function M.clear()
	local count = store.clear()
	clear_review_list()
	marks.refresh()
	notify(("reviewnotes: cleared %d notes"):format(count), vim.log.levels.INFO)
end

function M.list()
	picker.open(store.all(), "quickfix")
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
		restore_review_list()
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
	local function commands(prefix)
		cmd(prefix .. "Add", function(cmd_opts)
			if cmd_opts.range and cmd_opts.range > 0 then
				M.note_range(cmd_opts.line1, cmd_opts.line2)
			else
				M.note()
			end
		end, { desc = "add a note at the current location", range = true })
		cmd(prefix .. "Send", M.send, { desc = "send the note at the cursor" })
		cmd(prefix .. "Export", M.export, { desc = "export all notes" })
		cmd(prefix .. "ExportList", M.export_qf, { desc = "export the current quickfix or location list" })
		cmd(prefix .. "SaveList", function(cmd_opts)
			M.save_list(cmd_opts.args)
		end, { nargs = 1, desc = "save and autosave the current list" })
		cmd(prefix .. "LoadList", function(cmd_opts)
			M.load_list(cmd_opts.args)
		end, { nargs = 1, desc = "load and autosave a list" })
		cmd(prefix .. "ExportAndClear", M.export_and_clear, { desc = "export then clear all notes" })
		cmd(prefix .. "Clear", M.clear, { desc = "clear all notes" })
		cmd(prefix .. "List", M.list, { desc = "list notes" })
		cmd(prefix .. "Next", M.next, { desc = "jump to the next note" })
		cmd(prefix .. "Prev", M.prev, { desc = "jump to the previous note" })
	end
	local function setup_qf_buffer(buf)
		vim.bo[buf].modifiable = true
		vim.keymap.set("n", "<CR>", function()
			local current = list.current()
			local note = type(current.item.user_data) == "table" and current.item.user_data.quickfix_notes
			if note then
				picker.jump(note)
			else
				vim.cmd(current.kind == "location" and "ll" or "cc")
			end
		end, { buffer = buf, desc = "Jump to quickfix location" })
		vim.keymap.set("n", keys.note, qf_note, { buffer = buf, desc = "ReviewNoteAtQuickfix" })
		vim.keymap.set("n", "a", qf_note, { buffer = buf, desc = "ReviewNoteAtQuickfix" })
		vim.keymap.set("n", "e", qf_edit, { buffer = buf, desc = "ReviewEditQuickfixNote" })
		vim.keymap.set("n", keys.export, M.export_qf, { buffer = buf, desc = "ReviewExportList" })
		if not vim.b[buf].quickfix_notes_sync then
			vim.b[buf].quickfix_notes_sync = true
			vim.api.nvim_create_autocmd("BufWriteCmd", {
				buffer = buf,
				callback = function()
					local current = list.current()
					if current.kind == "quickfix" and current.title == config.get().quickfix_title then
						vim.schedule(function()
							sync_review_edits(current.id)
						end)
					end
				end,
			})
		end
	end
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "qf",
		callback = function(ev)
			setup_qf_buffer(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(ev)
			if vim.bo[ev.buf].filetype == "qf" then
				setup_qf_buffer(ev.buf)
			end
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].filetype == "qf" then
			setup_qf_buffer(buf)
		end
	end
	cmd("ReviewQfNote", qf_note, { desc = "reviewnotes: add or edit note at quickfix entry" })
	cmd("ReviewQfEdit", qf_edit, { desc = "reviewnotes: edit note at quickfix entry" })
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
	cmd("ReviewExportQf", function()
		M.export_qf()
	end, { desc = "reviewnotes: export actual quickfix entries" })
	cmd("ReviewExportList", function()
		M.export_qf()
	end, { desc = "reviewnotes: export current quickfix or location list" })
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
	commands("QuickfixNotes")

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
