local M = {}

local function require_dependency(name, plugin)
	local ok, module = pcall(require, name)
	if not ok then
		error(("Quickfix Review requires %s (%s): %s"):format(plugin, name, tostring(module)), 0)
	end
	return module
end

local actions = require_dependency("quickfix_actions", "quickfix-actions.nvim")
local generic_export = require_dependency("quickfix_export", "quickfix-export.nvim")
local config = require("quickfix_review.config")
local scope = require("quickfix_review.scope")
local location = require("quickfix_review.location")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local resolver = require("quickfix_review.resolver")
local ui = require("quickfix_review.ui")
local marks = require("quickfix_review.marks")
local picker = require("quickfix_review.picker")
local exporter = require("quickfix_review.export")
local sender = require("quickfix_review.sender")
local importer = require("quickfix_review.import")
local source_state = require("quickfix_review.source")

local current_scope
local review_watch
local setup_done = false
local hover_tick = 0

local function notify(message, level)
	vim.notify(message, level, { title = "Quickfix Review" })
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
		namespace = "quickfix_review",
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
	local snapshot, err = persist.load({ namespace = "quickfix_review", name = "review", scope = current_scope })
	if not snapshot then
		if err and not tostring(err):match("^not%-found:") then
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
	local range_fallback = false
	if range_start then
		value = resolver.range_location(vim.api.nvim_get_current_buf(), range_start, range_end)
		if not value then
			value = resolver.location()
			range_fallback = true
			if value then
				value.line = nil
				value.line_end = nil
			end
		end
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
	return value, nil, range_fallback
end

local function item_location(item)
	local note = annotations.get(item)
	if note then
		return location.canonical(note.location)
	end
	return lists.location({ item = item }, current_scope and current_scope.root)
end

local function flatten(text)
	return (text or ""):gsub("\n", " ")
end

local function add_source(value, bufnr)
	value = source_state.capture(value)
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
			notify("Quickfix Review list disappeared", vim.log.levels.WARN)
			return
		end
		if existing then
			local ok, err = lists.update_item(latest_target, index, function(item)
				local note, update_err = annotations.update(item, result.text, value)
				if not note then
					return nil, update_err
				end
				item.type = ""
				item.text = flatten(note.text)
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
	item.text = flatten(note.text)
	item.lnum = note.location.line or 0
	item.end_lnum = note.location.line_end or 0
	if item.end_lnum == 0 then
		item.end_lnum = nil
	end
	if item.end_col == 0 then
		item.end_col = nil
	end
	item.user_data = type(item.user_data) == "table" and item.user_data or {}
	item.user_data.quickfix_review = vim.deepcopy(note)
	return item
end

local function sync_owned_copy(entry, note)
	local _, target = lists.ensure_owned({ title = config.get().quickfix_title }, scope_id())
	local latest, _, latest_target = lists.read(target)
	if not latest then
		return nil, "Quickfix Review list disappeared"
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

local function qf_entry_is_owned(entry)
	return entry.kind == "quickfix"
		and type(entry.list.context) == "table"
		and type(entry.list.context.quickfix_review) == "table"
		and entry.list.context.quickfix_review.role == "notes"
end


local function annotate_list_entry(edit_only)
	local entry, err = lists.current()
	if not entry or not entry.item then
		notify(err or "empty quickfix row", vim.log.levels.WARN)
		return
	end
	local annotation = annotations.get(entry.item)
	if edit_only and not annotation then
		notify("no Quickfix Review annotation on this entry", vim.log.levels.INFO)
		return
	end
	if not annotation and entry.item.valid ~= 1 and not entry.item.filename and not entry.item.bufnr then
		notify("cannot annotate an invalid quickfix context row", vim.log.levels.WARN)
		return
	end
	local value, location_err = item_location(entry.item)
	if not value or not value.path then
		notify(location_err or "current list entry has no usable file", vim.log.levels.WARN)
		return
	end
	if current_scope and current_scope.root ~= value.root then
		notify("list entry belongs to a different repository scope", vim.log.levels.WARN)
		return
	end
	value = source_state.capture(value)
	local text = config.get().quickfix.prefill and entry.item.text or ""
	ui.note_input({ location = value, existing = annotation, text = text }, function(result)
		if not result then
			return
		end
		local target = { kind = entry.kind, id = entry.id, winid = entry.winid }
		local new_annotation
		local ok, update_err = lists.update_item(target, entry.index, function(item)
			local set_err
			if annotation then
				new_annotation, set_err = annotations.update(item, result.text, value)
			else
				new_annotation, set_err = annotations.set(item, value, result.text)
			end
			if not new_annotation then
				return nil, set_err
			end
			if not qf_entry_is_owned(entry) then
				new_annotation.origin = vim.deepcopy(target)
			end
			return true
		end, annotation and annotation.id)
		if not ok then
			notify(update_err, vim.log.levels.WARN)
			return
		end
		local copied, copy_err = sync_owned_copy(entry, new_annotation)
		if not copied then
			notify(copy_err, vim.log.levels.WARN)
			return
		end
		marks.refresh()
		persist_review()
		notify(annotation and "note updated" or "note added", vim.log.levels.INFO)
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


local function delete_qf_entry()
	local entry = lists.current()
	if not entry or not entry.item then
		notify("empty quickfix row", vim.log.levels.WARN)
		return
	end
	local note = annotations.get(entry.item)
	local ok, err = lists.delete(
		{ kind = entry.kind, id = entry.id, winid = entry.winid },
		entry.index,
		entry.changedtick
	)
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
		local value, err, range_fallback = source_location(start, stop)
		if not value then
			notify(err, vim.log.levels.WARN)
			return
		end
		if range_fallback then
			notify("range mapping unavailable; saving a file-level note", vim.log.levels.INFO)
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

function M.add_file()
	refresh_scope()
	local value, err
	if vim.bo.buftype == "quickfix" then
		local entry = lists.current()
		if entry and entry.item then
			if qf_entry_is_owned(entry) then
				value, err = item_location(entry.item)
			else
				value, err = lists.location(entry, current_scope.root)
			end
		end
	else
		value, err = source_location()
	end
	if not value or not value.path or value.root ~= current_scope.root then
		notify(err or "no file in the current repository scope", vim.log.levels.WARN)
		return
	end
	value.line, value.line_end = nil, nil
	add_source(value, vim.api.nvim_get_current_buf())
end

function M.reanchor(opts)
	refresh_scope()
	opts = opts or {}
	if vim.bo.buftype == "quickfix" then
		notify("place the cursor in the destination source buffer first", vim.log.levels.WARN)
		return
	end
	local value, err = source_location(opts.line1, opts.line2)
	if not value then
		notify(err, vim.log.levels.WARN)
		return
	end
	if opts.file then
		value.line, value.line_end = nil, nil
	end
	value = source_state.capture(value)
	local expected_scope = scope_id()
	local entries, entries_err = picker.entries({ source = "owned", scope_id = expected_scope })
	if not entries or #entries == 0 then
		notify(entries_err or "no notes to re-anchor", vim.log.levels.INFO)
		return
	end
	local reanchor = require("quickfix_review.reanchor")
	for _, entry in ipairs(entries) do
		reanchor.capture(entry)
	end
	table.sort(entries, function(a, b)
		local a_here, b_here = a.path == value.path, b.path == value.path
		if a_here ~= b_here then
			return a_here
		end
		return a.index < b.index
	end)
	vim.ui.select(entries, { prompt = "Re-anchor note here", format_item = function(entry)
		return entry.path .. ":" .. (entry.line or "") .. " - " .. flatten(entry.text)
	end }, function(entry)
		if not entry then
			return
		end
		refresh_scope()
		if scope_id() ~= expected_scope then
			notify("repository scope changed while choosing a note", vim.log.levels.WARN)
			return
		end
		local ok, move_err = reanchor.apply(entry, value)
		if not ok then
			notify(move_err, vim.log.levels.WARN)
			return
		end
		marks.refresh()
		persist_review()
		notify("note re-anchored", vim.log.levels.INFO)
	end)
end

function M.note_range(line1, line2)
	refresh_scope()
	local value, err, range_fallback = source_location(line1, line2)
	if not value then
		notify(err, vim.log.levels.WARN)
		return
	end
	if range_fallback then
		notify("range mapping unavailable; saving a file-level note", vim.log.levels.INFO)
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
			notify("no Quickfix Review annotation here", vim.log.levels.INFO)
			return
		end
		local ok, err
		if qf_entry_is_owned(entry) then
			ok, err = lists.delete(
				{ kind = entry.kind, id = entry.id, winid = entry.winid },
				entry.index,
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
				local text = flatten(note.text)
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

function M.search(opts)
	local ok, err = picker.search(opts)
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
	local warn_stale = opts.warn_stale
	if warn_stale == nil then
		warn_stale = config.get().warn_stale
	end
	if warn_stale and (details.stale or 0) > 0 then
		notify(("%d note location(s) may be stale; use QuickfixReviewReanchor to update them"):format(details.stale),
			vim.log.levels.WARN)
	end
	local payload, format_err = exporter.format(records, opts.format or "markdown", opts)
	if not payload then
		notify(format_err, vim.log.levels.ERROR)
		return false, format_err
	end
	local ok, result = generic_export.send(payload, opts.destination_opts or config.get().send_opts, opts.destination)
	if not ok then
		notify("export failed: " .. tostring(result), vim.log.levels.ERROR)
		return false, result
	end
	notify(("exported %d entries via %s"):format(#records, generic_export.active_destination()), vim.log.levels.INFO)
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
		and type(value.context.quickfix_review) == "table"
		and value.context.quickfix_review.role == "notes"
	if owned and not (opts and opts.annotations_only) then
		local ok, clear_err = lists.clear(resolved)
		if ok then
			marks.refresh()
		end
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
		marks.refresh()
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
		namespace = "quickfix_review",
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
	local snapshot, err = persist.load({ namespace = "quickfix_review", name = name, scope = current_scope })
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
		persist.watch({ namespace = "quickfix_review", name = name, scope = current_scope, target = restored })
	end
	return restored
end

function M.import_findings(source, opts)
	refresh_scope()
	opts = vim.tbl_extend("force", {}, opts or {}, {
		root = current_scope and current_scope.root,
		scope_id = scope_id(),
		title = config.get().quickfix_title,
	})
	local result, err = importer.run(source, opts)
	if not result then
		notify("import failed: " .. tostring(err), vim.log.levels.ERROR)
		return nil, err
	end
	marks.refresh()
	persist_review()
	local imported = result.added + result.updated
	if #result.errors > 0 then
		notify(("imported %d findings; skipped %d"):format(imported, #result.errors), vim.log.levels.WARN)
	else
		notify(
			("imported %d findings (%d added, %d updated)"):format(imported, result.added, result.updated),
			vim.log.levels.INFO
		)
	end
	return result
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
	command("QuickfixReviewAdd", function(o)
		if o.range > 0 then
			M.note_range(o.line1, o.line2)
		else
			M.add()
		end
	end, { range = true, desc = "Add a Quickfix Review annotation" })
	command("QuickfixReviewAddFile", M.add_file, { desc = "Add a file-level review note" })
	command("QuickfixReviewReanchor", function(o)
		M.reanchor({ file = o.bang, line1 = o.range > 0 and o.line1 or nil, line2 = o.line2 })
	end, { range = true, bang = true, desc = "Move an existing note here (! for file-level)" })
	command("QuickfixReviewEdit", M.edit, { desc = "Edit a Quickfix Review annotation" })
	command("QuickfixReviewDelete", M.delete, { desc = "Delete a Quickfix Review annotation" })
	command("QuickfixReviewList", M.open_list, { desc = "Open the owned QuickfixReview list" })
	command("QuickfixReviewPick", function()
		M.pick({ source = "owned", scope_id = scope_id() })
	end, { desc = "Pick a QuickfixReview annotation" })
	command("QuickfixReviewPickCurrent", function()
		M.pick({ source = "current" })
	end, { desc = "Pick an annotation in the current list" })
	command("QuickfixReviewSearch", function()
		M.search()
	end, { desc = "Search the current list and review notes" })
	command("QuickfixReviewExport", M.export, { desc = "Export the selected list" })
	command("QuickfixReviewExportList", M.export_qf, { desc = "Export the current native list" })
	command("QuickfixReviewExportAndClear", M.export_and_clear, { desc = "Export then clear safely" })
	command("QuickfixReviewClear", M.clear_annotations, { desc = "Clear annotations or owned entries" })
	command("QuickfixReviewSaveList", function(o)
		M.save_list(o.args)
	end, { nargs = 1, desc = "Save the selected native list" })
	command("QuickfixReviewLoadList", function(o)
		M.load_list(o.args)
	end, { nargs = 1, desc = "Load a named native list" })
	command("QuickfixReviewImport", function(o)
		M.import_findings(o.args)
	end, { nargs = 1, complete = "file", desc = "Import agent review findings from JSON" })
	command("QuickfixReviewHide", marks.hide, { desc = "Hide Quickfix Review marks" })
	command("QuickfixReviewShow", marks.show, { desc = "Show Quickfix Review marks" })
	command("QuickfixReviewHover", function()
		marks.hover_qf(vim.api.nvim_get_current_buf())
	end, { desc = "Show the note at the current quickfix row" })
	command("QuickfixReviewNext", M.next, { desc = "Pick the next Quickfix Review annotation" })
	command("QuickfixReviewPrev", M.prev, { desc = "Pick the previous Quickfix Review annotation" })
	command("QuickfixReviewSend", M.send, { desc = "Export through the configured destination" })
end

local function actions_qf_mapping(lhs)
	local action_opts = config.get().actions
	local mappings = action_opts and action_opts ~= false and action_opts.mappings
	local qf = mappings and mappings.qf
	return type(qf) == "table" and qf[lhs] ~= false
end

function M.setup(opts)
	config.setup(opts)
	local action_opts = config.get().actions
	if action_opts == false then
		action_opts = { mappings = { qf = false } }
	end
	actions.setup(action_opts)
	generic_export.setup(config.get().export or {})
	resolver.register(require("quickfix_review.resolvers.codediff"))
	resolver.register(require("quickfix_review.resolvers.diffview"))
	resolver.register(require("quickfix_review.resolvers.differ"))
	resolver.register(require("quickfix_review.resolvers.neogit"))
	resolver.register(require("quickfix_review.resolvers.diffs"))
	resolver.register(require("quickfix_review.resolvers.native"))
	resolver.register(require("quickfix_review.resolvers.normal"))
	resolver.register(require("quickfix_review.resolvers.generic"))
	sender.set_default(config.get().send)
	marks.setup(config.get())
	refresh_scope(true)
	marks.refresh()
	if setup_done then
		return M
	end
	setup_done = true
	local group = vim.api.nvim_create_augroup("QuickfixReview", { clear = true })
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
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "DiffviewViewEnter", "DiffviewDiffBufWinEnter", "DiffviewSelectionChanged" },
		callback = function()
			marks.refresh()
		end,
	})
	local function setup_qf_buffer(buf)
		if not actions_qf_mapping("<CR>") then
			vim.keymap.set("n", "<CR>", qf_jump, { buffer = buf, nowait = true, desc = "Jump to quickfix location" })
		end
		if not actions_qf_mapping("dd") then
			vim.keymap.set("n", "dd", delete_qf_entry, { buffer = buf, nowait = true, desc = "Delete quickfix entry" })
		end
		vim.keymap.set(
			"n",
			config.get().keys.note,
			annotate_list_entry,
			{ buffer = buf, desc = "Add or edit Quickfix Review annotation" }
		)
		vim.keymap.set("n", "a", annotate_list_entry, { buffer = buf, desc = "Add QuickfixReview annotation" })
		vim.keymap.set("n", "e", function()
			annotate_list_entry(true)
		end, { buffer = buf, desc = "Edit QuickfixReview annotation" })
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
		vim.keymap.set(mode, keys.note, M.add, { desc = "QuickfixReviewAdd" })
		vim.keymap.set(mode, keys.export, M.export, { desc = "QuickfixReviewExport" })
		vim.keymap.set(mode, keys.export_and_clear, M.export_and_clear, { desc = "QuickfixReviewExportAndClear" })
	end
	vim.keymap.set("n", keys.clear, M.clear_annotations, { desc = "QuickfixReviewClear" })
	vim.keymap.set("n", keys.list, M.open_list, { desc = "QuickfixReviewList" })
	return M
end

return M
