local actions = require("quickfix_actions")
local M = {}

local cached_owned_id

local function hydrate_owned(value)
	for _, item in ipairs(value.items or {}) do
		if
			(not item.filename or item.filename == "")
			and item.bufnr
			and item.bufnr > 0
			and vim.api.nvim_buf_is_valid(item.bufnr)
		then
			item.filename = vim.api.nvim_buf_get_name(item.bufnr)
		end
	end
	return value
end

function M.read(target)
	return actions.read(target)
end

function M.current(target)
	return actions.current(target)
end

function M.item(target, index)
	return actions.item(target, index)
end

function M.location(entry, root)
	local item = entry and entry.item
	if not item then
		return nil
	end
	local path = item.filename
	if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
		path = vim.api.nvim_buf_get_name(item.bufnr)
	end
	if not path or path == "" then
		return nil
	end
	return require("quickfix_notes.location").canonical({
		root = root or vim.fn.getcwd(),
		file = path,
		line = item.lnum,
		line_end = item.end_lnum,
	})
end

function M.replace(target, items, idx, expected_tick)
	return actions.replace(target, items, idx, expected_tick)
end

function M.update_item(target, index, fn, expected_id)
	local value, err, resolved = actions.read(target)
	if not value then
		return nil, err
	end
	local item = value.items and value.items[index]
	if not item then
		return nil, "list entry is empty"
	end
	local annotations = require("quickfix_notes.annotations")
	if expected_id and (annotations.get(item) or {}).id ~= expected_id then
		return nil, "list entry changed while it was being edited"
	end
	local before = value.changedtick
	local copy = vim.deepcopy(value.items)
	local updated, update_err = fn(copy[index])
	if not updated then
		return nil, update_err
	end
	local latest = actions.read(vim.tbl_extend("force", resolved, { id = value.id }))
	if not latest or latest.changedtick ~= before then
		return nil, "list changed while it was being edited"
	end
	return actions.replace(resolved, copy, value.idx, before)
end

function M.delete(target, index, expected_tick)
	return actions.delete(target, index, expected_tick)
end

local function owns(value, scope_id)
	local marker = type(value.context) == "table" and value.context.quickfix_notes
	return type(marker) == "table" and marker.role == "notes" and (not scope_id or marker.scope_id == scope_id)
end

function M.find_owned(scope_id)
	if cached_owned_id then
		local value = M.read({ kind = "quickfix", id = cached_owned_id })
		if value and owns(value, scope_id) then
			return hydrate_owned(value), { kind = "quickfix", id = cached_owned_id }
		end
		cached_owned_id = nil
	end
	local max = vim.fn.getqflist({ nr = "$" }).nr or 0
	for nr = 1, max do
		local value = vim.fn.getqflist({ nr = nr, all = 1 })
		if owns(value, scope_id) then
			cached_owned_id = value.id
			return hydrate_owned(value), { kind = "quickfix", id = value.id }
		end
	end
end

function M.ensure_owned(opts, scope_id)
	local existing, target = M.find_owned(scope_id)
	if existing then
		return existing, target
	end
	local active = vim.fn.getqflist({ id = 0, nr = 0 })
	local context = {
		quickfix_notes = { version = 1, role = "notes", scope_id = scope_id },
	}
	vim.fn.setqflist({}, " ", { nr = "$", title = opts.title, context = context, items = {} })
	local created = vim.fn.getqflist({ id = 0, all = 1 })
	cached_owned_id = created.id
	if active.id and active.id ~= created.id and active.nr then
		pcall(vim.cmd, "silent " .. active.nr .. "chistory")
	end
	return created, { kind = "quickfix", id = created.id }
end

function M.set_owned(value, target, items)
	local ok, err = M.replace(target, items, value.idx, value.changedtick)
	if ok then
		cached_owned_id = target.id
	end
	return ok, err
end

function M.open_owned(scope_id)
	local value, target = M.find_owned(scope_id)
	if not value then
		return nil, "no QuickfixNotes list"
	end
	return actions.open(target)
end

function M.clear(target)
	return actions.clear(target)
end

function M.for_each_annotation(target, callback)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	local annotations = require("quickfix_notes.annotations")
	for index, item in ipairs(value.items or {}) do
		local note = annotations.get(item)
		if note then
			callback(note, item, index, resolved)
		end
	end
	return true
end

return M
