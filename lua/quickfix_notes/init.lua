local M = {}

local config = require("quickfix_notes.config")
local scope = require("quickfix_notes.scope")
local location = require("quickfix_notes.location")
local annotations = require("quickfix_notes.annotations")
local lists = require("quickfix_notes.lists")
local resolver = require("quickfix_notes.resolver")
local ui = require("quickfix_notes.ui")
local marks = require("quickfix_notes.marks")
local picker = require("quickfix_notes.picker")
local exporter = require("quickfix_notes.export")
local sender = require("quickfix_notes.sender")

local current_scope
local review_watch
local setup_done = false
local hover_tick = 0

local function notify(message, level)
	vim.notify(message, level, { title = "QuickfixNotes" })
end

local function persist_module()
	local ok, persist = pcall(require, "quickfix_persist")
	return ok and persist or nil
end

local function scope_id()
	return current_scope and scope.id(current_scope)
end

local function persist_review()
	if not config.get().persist_review_list or not current_scope then
		return false
	end
	local persist = persist_module()
	local owned = lists.find_owned(scope_id())
	if not persist or not owned then
		return false
	end
	if review_watch then
		pcall(persist.unwatch, review_watch)
		review_watch = nil
	end
	local handle, err = persist.save({
		namespace = "quickfix-notes",
		name = "review",
		scope = current_scope,
		target = { kind = "quickfix", id = owned.id },
		watch = true,
	})
	if not handle then
		notify("could not persist review list: " .. tostring(err), vim.log.levels.WARN)
		return false
	end
	review_watch = handle
	return true
end

local function restore_review()
	if not config.get().persist_review_list or not current_scope then
		return
	end
	if lists.find_owned(scope_id()) then
		return
	end
	local persist = persist_module()
	if not persist then
		return
	end
	local snapshot, err = persist.load({ namespace = "quickfix-notes", name = "review", scope = current_scope })
	if not snapshot then
		if err == "not-found: snapshot not found" or err == "snapshot not found" then
			local migrated, migration_err = require("quickfix_notes.migrate").apply(scope_id(), current_scope, {
				title = config.get().quickfix_title,
			})
			if migrated then
				persist_review()
			elseif migration_err and migration_err ~= "legacy notes not found" then
				notify("could not migrate legacy notes: " .. migration_err, vim.log.levels.WARN)
			end
		elseif err then
			notify("could not restore review list: " .. err, vim.log.levels.WARN)
		end
		return
	end
	local active = vim.fn.getqflist({ id = 0, nr = 0 })
	local restored, restore_err = persist.restore(snapshot, { kind = "quickfix", mode = "new" })
	if not restored then
		notify("could not restore review list: " .. tostring(restore_err), vim.log.levels.WARN)
		return
	end
	if active.id and active.id ~= restored.id and active.nr then
		pcall(vim.cmd, "silent " .. active.nr .. "chistory")
	end
	persist_review()
end

local function clear_old_scope(old)
	local owned = old and lists.find_owned(scope.id(old))
	if owned then
		pcall(lists.clear, { kind = "quickfix", id = owned.id })
	end
end

local function refresh_scope(force)
	local next_scope = scope.resolve(config.get().scope_policy, config.get().scope)
	if current_scope and scope.id(current_scope) == scope.id(next_scope) then
		return false
	end
	local old = current_scope
	local persist = persist_module()
	if review_watch and persist then
		pcall(persist.flush, review_watch)
		pcall(persist.unwatch, review_watch)
	end
	review_watch = nil
	if old then
		clear_old_scope(old)
	end
	current_scope = next_scope
	restore_review()
	marks.refresh()
	return true
end

function M.scope()
	return current_scope and vim.deepcopy(current_scope) or nil
end

local function source_location(range_start, range_end)
	local value
	if range_start then
		value = resolver.range_location(vim.api.nvim_get_current_buf(), range_start, range_end)
	else
		value = resolver.location()
	end
	if not value or not value.path then
		return nil, "could not resolve a source location"
	end
	value = location.canonical(value)
	if not value.root then
		return nil, "resolver returned no repository root"
	end
	if current_scope and current_scope.root ~= value.root then
		return nil, "source buffer belongs to a different repository scope"
	end
	return value
end

local function item_location(item)
	local note = annotations.get(item)
	if note then
		return location.canonical(note.location)
	end
	local path = item.filename
	if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
		path = vim.api.nvim_buf_get_name(item.bufnr)
	end
	if not path or path == "" then
		return nil
	end
	return location.canonical({
		root = current_scope and current_scope.root,
		file = path,
		line = item.lnum,
		line_end = item.end_lnum,
	})
end

local function flatten(text)
	return (text or ""):gsub("\n", " ")
end

local function add_source(value, bufnr)
	local owned, target = lists.ensure_owned({ title = config.get().quickfix_title }, scope_id())
	local existing, index
	for i, item in ipairs(owned.items or {}) do
		local note = annotations.get(item)
		if note and location.equal(note.location, value) then
			existing, index = note, i
			break
		end
	end
	ui.note_input({ location = value, existing = existing }, function(result)
		if not result then
			return
		end
		local latest, _, latest_target = lists.read(target)
		if not latest then
			notify("QuickfixNotes list disappeared", vim.log.levels.WARN)
			return
		end
		if existing then
			local ok, err = lists.update_item(latest_target, index, function(item)
				local note, update_err = annotations.update(item, result.text, value)
				if not note then
					return nil, update_err
				end
				item.type = ""
				item.text = flatten(annotations.composed_text(note))
				return true
			end, existing.id)
			if not ok then
				notify(err, vim.log.levels.WARN)
				return
			end
		else
			local item = {
				filename = location.absolute(value),
				lnum = value.line,
				end_lnum = value.line_end,
				col = 0,
				end_col = 0,
				valid = 1,
				type = "",
				text = flatten(result.text),
				user_data = {},
			}
			local note, err = annotations.set(item, value, result.text)
			if not note then
				notify(err, vim.log.levels.WARN)
				return
			end
			latest.items[#latest.items + 1] = item
			local ok, replace_err = lists.replace(latest_target, latest.items, latest.idx, latest.changedtick)
			if not ok then
				notify(replace_err, vim.log.levels.WARN)
				return
			end
		end
		marks.render(bufnr)
		persist_review()
		notify(existing and "note updated" or "note added", vim.log.levels.INFO)
	end)
end

local function owned_copy(entry, note)
	local item = vim.deepcopy(entry.item)
	item.filename = item.filename or location.absolute(note.location)
	item.valid = 1
	item.type = ""
	item.module = ""
	item.text = flatten(annotations.composed_text(note))
	if item.end_lnum == 0 then
		item.end_lnum = nil
	end
	if item.end_col == 0 then
		item.end_col = nil
	end
	item.user_data = type(item.user_data) == "table" and item.user_data or {}
	item.user_data.quickfix_notes = vim.deepcopy(note)
	return item
end

local function sync_owned_copy(entry, note)
	local _, target = lists.ensure_owned({ title = config.get().quickfix_title }, scope_id())
	local latest, _, latest_target = lists.read(target)
	if not latest then
		return nil, "Quickfix Notes list disappeared"
	end
	local copy = owned_copy(entry, note)
	local found
	for index, item in ipairs(latest.items or {}) do
		local existing = annotations.get(item)
		if existing and existing.id == note.id then
			latest.items[index] = copy
			found = true
			break
		end
	end
	if not found then
		latest.items[#latest.items + 1] = copy
	end
	return lists.replace(latest_target, latest.items, latest.idx, latest.changedtick)
end

local function remove_owned_copy(id)
	if not id then
		return
	end
	local owned, target = lists.find_owned(scope_id())
	if not owned then
		return
	end
	local latest, _, latest_target = lists.read(target)
	if not latest then
		return
	end
	for index, item in ipairs(latest.items or {}) do
		if (annotations.get(item) or {}).id == id then
			table.remove(latest.items, index)
			lists.replace(latest_target, latest.items, math.min(latest.idx or 1, #latest.items), latest.changedtick)
			return
		end
	end
end

local function annotate_list_entry(edit_only)
	local entry, err = lists.current()
	if not entry or not entry.item then
		notify(err or "empty quickfix row", vim.log.levels.WARN)
		return
	end
	local note = annotations.get(entry.item)
	if edit_only and not note then
		notify("no QuickfixNotes annotation on this entry", vim.log.levels.INFO)
		return
	end
	if not note and entry.item.valid ~= 1 and not entry.item.filename and not entry.item.bufnr then
		notify("cannot annotate an invalid quickfix context row", vim.log.levels.WARN)
		return
	end
	local value = item_location(entry.item)
	if not value or not value.path or not value.line or value.line < 1 then
		notify("current list entry has no usable file and line", vim.log.levels.WARN)
		return
	end
	ui.note_input({ location = value, existing = note }, function(result)
		if not result then
			return
		end
		local target = { kind = entry.kind, id = entry.id, winid = entry.winid }
		local new_note
		local ok, update_err = lists.update_item(target, entry.index, function(item)
			local set_err
			if note then
				new_note, set_err = annotations.update(item, result.text, value)
			else
				new_note, set_err = annotations.set(item, value, result.text)
			end
			if not new_note then
				return nil, set_err
			end
			return true
		end, note and note.id)
		if not ok then
			notify(update_err, vim.log.levels.WARN)
			return
		end
		local copied, copy_err = sync_owned_copy(entry, new_note)
		if not copied then
			notify(copy_err, vim.log.levels.WARN)
			return
		end
		marks.refresh()
		persist_review()
		notify(note and "note updated" or "note added", vim.log.levels.INFO)
	end)
end

local function qf_jump()
	local entry = lists.current()
	if not entry or not entry.item then
		notify("empty quickfix row", vim.log.levels.WARN)
		return
	end
	local command = entry.kind == "location" and "ll" or "cc"
	vim.cmd(("%s %d"):format(command, entry.index))
end

local function qf_entry_is_owned(entry)
	return entry.kind == "quickfix"
		and type(entry.list.context) == "table"
		and type(entry.list.context.quickfix_notes) == "table"
		and entry.list.context.quickfix_notes.role == "notes"
end

local function delete_qf_entry()
	local entry = lists.current()
	if not entry or not entry.item then
		notify("empty quickfix row", vim.log.levels.WARN)
		return
	end
	local items = vim.deepcopy(entry.items)
	local note = annotations.get(entry.item)
	table.remove(items, entry.index)
	local index = math.min(entry.list.idx or 1, #items)
	local ok, err =
		lists.replace({ kind = entry.kind, id = entry.id, winid = entry.winid }, items, index, entry.changedtick)
	if not ok then
		notify(err, vim.log.levels.WARN)
		return
	end
	remove_owned_copy(note and note.id)
	marks.refresh()
	persist_review()
end

function M.add()
	refresh_scope()
	if vim.bo.buftype == "quickfix" then
		annotate_list_entry(false)
		return
	end
	if vim.fn.mode():match("[vV\022]") then
		local start, stop = vim.fn.line("'<"), vim.fn.line("'>")
		if start > stop then
			start, stop = stop, start
		end
		local value, err = source_location(start, stop)
		if not value then
			notify(err, vim.log.levels.WARN)
			return
		end
		add_source(value, vim.api.nvim_get_current_buf())
		return
	end
	local value, err = source_location()
	if not value then
		notify(err, vim.log.levels.WARN)
		return
	end
	add_source(value, vim.api.nvim_get_current_buf())
end

function M.note_range(line1, line2)
	refresh_scope()
	local value, err = source_location(line1, line2)
	if not value then
		notify(err, vim.log.levels.WARN)
		return
	end
	add_source(value, vim.api.nvim_get_current_buf())
end

function M.edit()
	if vim.bo.buftype == "quickfix" then
		annotate_list_entry(true)
		return
	end
	M.add()
end

function M.delete()
	refresh_scope()
	if vim.bo.buftype == "quickfix" then
		local entry = lists.current()
		if not entry or not entry.item then
			notify("empty quickfix row", vim.log.levels.WARN)
			return
		end
		local note = annotations.get(entry.item)
		if not note then
			notify("no QuickfixNotes annotation here", vim.log.levels.INFO)
			return
		end
		local ok, err
		if qf_entry_is_owned(entry) then
			local items = vim.deepcopy(entry.items)
			table.remove(items, entry.index)
			ok, err = lists.replace(
				{ kind = entry.kind, id = entry.id, winid = entry.winid },
				items,
				math.min(entry.list.idx or 1, #items),
				entry.changedtick
			)
		else
			ok, err = lists.update_item(
				{ kind = entry.kind, id = entry.id, winid = entry.winid },
				entry.index,
				function(item)
					return annotations.remove(item)
				end,
				note.id
			)
		end
		if not ok then
			notify(err, vim.log.levels.WARN)
			return
		end
		if not qf_entry_is_owned(entry) then
			remove_owned_copy(note.id)
		end
		marks.refresh()
		persist_review()
		return
	end
	local value = source_location()
	if not value then
		return
	end
	local owned, target = lists.find_owned(scope_id())
	if not owned then
		return
	end
	for index, item in ipairs(owned.items or {}) do
		local note = annotations.get(item)
		if note and location.equal(note.location, value) then
			table.remove(owned.items, index)
			lists.replace(target, owned.items, math.min(owned.idx or 1, #owned.items), owned.changedtick)
			marks.refresh()
			persist_review()
			return
		end
	end
end

function M.open_list()
	refresh_scope()
	local owned, target = lists.find_owned(scope_id())
	if owned then
		local items = vim.deepcopy(owned.items or {})
		local changed
		for index = #items, 1, -1 do
			local item = items[index]
			local note = annotations.get(item)
			if not note then
				table.remove(items, index)
				changed = true
			else
				local text = flatten(annotations.composed_text(note))
				if item.type == "N" or item.text ~= text then
					item.type = ""
					item.text = text
					changed = true
				end
			end
		end
		if changed then
			lists.replace(target, items, owned.idx, owned.changedtick)
		end
	end
	local ok, err = lists.open_owned(scope_id())
	if not ok then
		notify(err, vim.log.levels.INFO)
	end
end

function M.pick(opts)
	refresh_scope()
	local ok, err = picker.pick(opts or { source = "owned", scope_id = scope_id() })
	if not ok and err then
		notify(err, vim.log.levels.INFO)
	end
	return ok
end

local function selected_target(opts)
	opts = opts or {}
	if opts.list then
		return opts.list
	end
	if vim.bo.buftype == "quickfix" then
		local current = lists.current()
		return current and { kind = current.kind, id = current.id, winid = current.winid }
	end
	local owned = lists.find_owned(scope_id())
	return owned and { kind = "quickfix", id = owned.id }
end

function M.export(opts)
	refresh_scope()
	opts = opts or {}
	opts.scope_id, opts.root = scope_id(), current_scope and current_scope.root
	local records, err, details = exporter.records(vim.tbl_extend("force", opts, { list = selected_target(opts) }))
	if not records then
		notify("export failed: " .. tostring(err), vim.log.levels.ERROR)
		return false, err
	end
	local payload, format_err = exporter.format(records, opts.format or "markdown")
	if not payload then
		notify(format_err, vim.log.levels.ERROR)
		return false, format_err
	end
	local ok, result = sender.send(payload, opts.destination_opts or config.get().send_opts, opts.destination)
	if not ok then
		notify("export failed: " .. tostring(result), vim.log.levels.ERROR)
		return false, result
	end
	notify(("exported %d entries via %s"):format(#records, sender.active()), vim.log.levels.INFO)
	return true, result, details
end

function M.clear_annotations(opts)
	local target = selected_target(opts)
	if not target then
		return false, "no list selected"
	end
	local value, err, resolved = lists.read(target)
	if not value then
		return false, err
	end
	local owned = type(value.context) == "table"
		and type(value.context.quickfix_notes) == "table"
		and value.context.quickfix_notes.role == "notes"
	if owned and not (opts and opts.annotations_only) then
		local ok, clear_err = lists.clear(resolved)
		persist_review()
		return ok, clear_err
	end
	local items = vim.deepcopy(value.items or {})
	local ids = {}
	for _, item in ipairs(items) do
		local note = annotations.get(item)
		if note then
			ids[#ids + 1] = note.id
		end
		annotations.remove(item)
	end
	local ok, clear_err = lists.replace(resolved, items, value.idx, value.changedtick)
	if ok then
		for _, id in ipairs(ids) do
			remove_owned_copy(id)
		end
	end
	persist_review()
	return ok, clear_err
end

function M.export_and_clear(opts)
	local ok, err = M.export(opts)
	if not ok then
		return false, err
	end
	local cleared, clear_err = M.clear_annotations(opts)
	if not cleared then
		notify("export succeeded but clear failed: " .. tostring(clear_err), vim.log.levels.WARN)
		return false, clear_err
	end
	marks.refresh()
	persist_review()
	return true
end

function M.save_list(name, opts)
	local persist = persist_module()
	if not persist then
		return nil, "quickfix_persist is required"
	end
	refresh_scope()
	local target = selected_target(opts)
	if not target then
		return nil, "no list selected"
	end
	local handle, err = persist.save({
		namespace = "quickfix-notes",
		name = name,
		scope = current_scope,
		target = target,
		watch = opts == nil or opts.watch ~= false,
	})
	if not handle then
		notify(err, vim.log.levels.ERROR)
	end
	return handle, err
end

function M.load_list(name, opts)
	local persist = persist_module()
	if not persist then
		return nil, "quickfix_persist is required"
	end
	refresh_scope()
	local snapshot, err = persist.load({ namespace = "quickfix-notes", name = name, scope = current_scope })
	if not snapshot then
		notify(err, vim.log.levels.ERROR)
		return nil, err
	end
	local target = opts and opts.target
		or { kind = snapshot.kind, winid = vim.api.nvim_get_current_win(), mode = opts and opts.mode or "new" }
	local restored, restore_err = persist.restore(snapshot, target)
	if not restored then
		notify(restore_err, vim.log.levels.ERROR)
		return nil, restore_err
	end
	if opts == nil or opts.watch ~= false then
		persist.watch({ namespace = "quickfix-notes", name = name, scope = current_scope, target = restored })
	end
	return restored
end

function M.next()
	return M.pick({ source = "owned", scope_id = scope_id() })
end
function M.prev()
	return M.next()
end
function M.send()
	return M.export({ list = selected_target(), destination = config.get().send })
end
function M.export_qf()
	local current = lists.current()
	if not current then
		return false, "no list selected"
	end
	return M.export({ list = { kind = current.kind, id = current.id, winid = current.winid } })
end

local function command(name, callback, opts)
	vim.api.nvim_create_user_command(name, callback, vim.tbl_extend("force", { force = true }, opts or {}))
end

local function install_commands()
	command("QuickfixNotesAdd", function(o)
		if o.range > 0 then
			M.note_range(o.line1, o.line2)
		else
			M.add()
		end
	end, { range = true, desc = "Add a QuickfixNotes annotation" })
	command("QuickfixNotesEdit", M.edit, { desc = "Edit a QuickfixNotes annotation" })
	command("QuickfixNotesDelete", M.delete, { desc = "Delete a QuickfixNotes annotation" })
	command("QuickfixNotesList", M.open_list, { desc = "Open the owned QuickfixNotes list" })
	command("QuickfixNotesPick", function()
		M.pick({ source = "owned", scope_id = scope_id() })
	end, { desc = "Pick a QuickfixNotes annotation" })
	command("QuickfixNotesPickCurrent", function()
		M.pick({ source = "current" })
	end, { desc = "Pick an annotation in the current list" })
	command("QuickfixNotesExport", M.export, { desc = "Export the selected list" })
	command("QuickfixNotesExportList", M.export_qf, { desc = "Export the current native list" })
	command("QuickfixNotesExportAndClear", M.export_and_clear, { desc = "Export then clear safely" })
	command("QuickfixNotesClear", M.clear_annotations, { desc = "Clear annotations or owned entries" })
	command("QuickfixNotesSaveList", function(o)
		M.save_list(o.args)
	end, { nargs = 1, desc = "Save the selected native list" })
	command("QuickfixNotesLoadList", function(o)
		M.load_list(o.args)
	end, { nargs = 1, desc = "Load a named native list" })
	command("QuickfixNotesHide", marks.hide, { desc = "Hide QuickfixNotes marks" })
	command("QuickfixNotesShow", marks.show, { desc = "Show QuickfixNotes marks" })
	command("QuickfixNotesHover", function()
		marks.hover_qf(vim.api.nvim_get_current_buf())
	end, { desc = "Show the note at the current quickfix row" })
	command("QuickfixNotesNext", M.next, { desc = "Pick the next QuickfixNotes annotation" })
	command("QuickfixNotesPrev", M.prev, { desc = "Pick the previous QuickfixNotes annotation" })
	command("QuickfixNotesSend", M.send, { desc = "Export through the configured destination" })
end

function M.setup(opts)
	config.setup(opts)
	resolver.register(require("quickfix_notes.resolvers.codediff"))
	resolver.register(require("quickfix_notes.resolvers.differ"))
	resolver.register(require("quickfix_notes.resolvers.neogit"))
	resolver.register(require("quickfix_notes.resolvers.diffs"))
	resolver.register(require("quickfix_notes.resolvers.native"))
	resolver.register(require("quickfix_notes.resolvers.normal"))
	sender.register(require("quickfix_notes.destinations.clipboard"))
	sender.register(require("quickfix_notes.destinations.file"))
	sender.register(require("quickfix_notes.destinations.sidekick"))
	sender.set_default(config.get().send)
	marks.setup(config.get())
	refresh_scope(true)
	marks.refresh()
	if setup_done then
		return M
	end
	setup_done = true
	local group = vim.api.nvim_create_augroup("QuickfixNotes", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		callback = function(e)
			marks.render(e.buf)
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function(e)
			hover_tick = hover_tick + 1
			local tick = hover_tick
			local delay = vim.bo[e.buf].buftype == "quickfix" and marks.quickfix_float_delay() or marks.float_delay()
			if delay then
				vim.defer_fn(function()
					if tick == hover_tick and vim.api.nvim_get_current_buf() == e.buf then
						marks.hover(e.buf)
					end
				end, delay)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "ShellCmdPost" }, {
		group = group,
		callback = function()
			refresh_scope(true)
			marks.refresh()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "NeogitBranchCheckout", "NeogitBranchCreate", "NeogitReset" },
		callback = function()
			refresh_scope(true)
			marks.refresh()
		end,
	})
	local function setup_qf_buffer(buf)
		vim.keymap.set("n", "<CR>", qf_jump, { buffer = buf, nowait = true, desc = "Jump to quickfix location" })
		vim.keymap.set("n", "dd", delete_qf_entry, { buffer = buf, nowait = true, desc = "Delete quickfix entry" })
		vim.keymap.set(
			"n",
			config.get().keys.note,
			annotate_list_entry,
			{ buffer = buf, desc = "Add or edit QuickfixNotes annotation" }
		)
		vim.keymap.set("n", "a", annotate_list_entry, { buffer = buf, desc = "Add QuickfixNotes annotation" })
		vim.keymap.set("n", "e", function()
			annotate_list_entry(true)
		end, { buffer = buf, desc = "Edit QuickfixNotes annotation" })
	end
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "qf",
		callback = function(e)
			setup_qf_buffer(e.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(e)
			if vim.bo[e.buf].filetype == "qf" then
				setup_qf_buffer(e.buf)
			end
		end,
	})
	install_commands()
	local keys = config.get().keys
	for _, mode in ipairs({ "n", "v" }) do
		vim.keymap.set(mode, keys.note, M.add, { desc = "QuickfixNotesAdd" })
		vim.keymap.set(mode, keys.export, M.export, { desc = "QuickfixNotesExport" })
		vim.keymap.set(mode, keys.export_and_clear, M.export_and_clear, { desc = "QuickfixNotesExportAndClear" })
	end
	vim.keymap.set("n", keys.clear, M.clear_annotations, { desc = "QuickfixNotesClear" })
	vim.keymap.set("n", keys.list, M.open_list, { desc = "QuickfixNotesList" })
	return M
end

return M
