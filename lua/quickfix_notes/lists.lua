local M = {}

local cached_owned_id

local function hydrate_items(value)
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

local function kind_of_current()
	local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
	return info and info.loclist == 1 and "location" or "quickfix"
end

local function winid(target)
	local id = target and target.winid
	if id == 0 or not id then
		id = vim.api.nvim_get_current_win()
	end
	return id
end

local function check_kind(kind)
	if kind ~= "quickfix" and kind ~= "location" then
		return nil, "kind must be quickfix or location"
	end
	return kind
end

function M.read(target)
	target = target or {}
	local kind, err = check_kind(target.kind or kind_of_current())
	if not kind then
		return nil, err
	end
	local request = { all = 1 }
	if target.id then
		request.id = target.id
	end
	if kind == "location" then
		local window = winid(target)
		if not vim.api.nvim_win_is_valid(window) then
			return nil, "invalid location-list window"
		end
		local value = vim.fn.getloclist(window, request)
		if target.id and value.id ~= target.id then
			return nil, "location list no longer exists"
		end
		return hydrate_items(value), nil, { kind = kind, winid = window, id = value.id }
	end
	local value = vim.fn.getqflist(request)
	if target.id and value.id ~= target.id then
		return nil, "quickfix list no longer exists"
	end
	return hydrate_items(value), nil, { kind = kind, id = value.id }
end

function M.current()
	local value, err, target = M.read()
	if not value then
		return nil, err
	end
	local index = value.idx or 0
	if vim.bo.buftype == "quickfix" then
		local row = vim.fn.line(".")
		if row > 0 and row <= #(value.items or {}) then
			index = row
		end
	end
	return {
		kind = target.kind,
		id = value.id,
		index = index,
		title = value.title,
		context = value.context,
		changedtick = value.changedtick,
		winid = target.winid,
		items = value.items or {},
		item = value.items and value.items[index],
		list = value,
	}
end

function M.item(target, index)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	return value.items and value.items[index], nil, vim.tbl_extend("force", resolved, { list = value, index = index })
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
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	if expected_tick and value.changedtick ~= expected_tick then
		return nil, "list changed while it was being edited"
	end
	local what = {
		id = value.id,
		title = value.title,
		context = value.context,
		items = items,
		idx = idx or value.idx,
	}
	if resolved.kind == "location" then
		vim.fn.setloclist(resolved.winid, {}, "r", what)
	else
		vim.fn.setqflist({}, "r", what)
	end
	return true
end

function M.update_item(target, index, fn, expected_id)
	local value, err, resolved = M.read(target)
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
	local latest = M.read(vim.tbl_extend("force", resolved, { id = value.id }))
	if not latest or latest.changedtick ~= before then
		return nil, "list changed while it was being edited"
	end
	return M.replace(resolved, copy, value.idx, before)
end

local function owns(value, scope_id)
	local marker = type(value.context) == "table" and value.context.quickfix_notes
	return type(marker) == "table" and marker.role == "notes" and (not scope_id or marker.scope_id == scope_id)
end

function M.find_owned(scope_id)
	if cached_owned_id then
		local value = M.read({ kind = "quickfix", id = cached_owned_id })
		if value and owns(value, scope_id) then
			return value, { kind = "quickfix", id = cached_owned_id }
		end
		cached_owned_id = nil
	end
	local max = vim.fn.getqflist({ nr = "$" }).nr or 0
	for nr = 1, max do
		local value = vim.fn.getqflist({ nr = nr, all = 1 })
		if owns(value, scope_id) then
			cached_owned_id = value.id
			return value, { kind = "quickfix", id = value.id }
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
	local nr = vim.fn.getqflist({ id = target.id, nr = 0 }).nr
	if nr and nr > 0 then
		vim.cmd("silent " .. nr .. "chistory")
	end
	vim.cmd("copen")
	return true
end

function M.clear(target)
	local value, err, resolved = M.read(target)
	if not value then
		return nil, err
	end
	return M.replace(resolved, {}, 0, value.changedtick)
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
