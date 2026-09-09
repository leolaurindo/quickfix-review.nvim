local lists = require("quickfix_review.lists")
local annotations = require("quickfix_review.annotations")
local location = require("quickfix_review.location")
local source = require("quickfix_review.source")
local M = {}

function M.capture(entry)
	entry.origin_checked = true
	local origin = entry.note.origin
	local snapshot = origin and lists.read(origin)
	for _, item in ipairs(snapshot and snapshot.items or {}) do
		local annotation = annotations.get(item)
		if annotation and annotation.id == entry.id then
			entry.origin_note = vim.deepcopy(annotation)
			break
		end
	end
	return entry
end

local function prepare(target, entry, moved, owned)
	local value = moved.location
	local snapshot, err = lists.read(target)
	if not snapshot then
		return nil, owned and err or nil
	end
	local items = vim.deepcopy(snapshot.items)
	local found = false
	for _, item in ipairs(items) do
		local annotation = annotations.get(item)
		if annotation and annotation.id == entry.id then
			local expected = owned and entry.note or entry.origin_note or entry.note
			if not vim.deep_equal(annotation, expected) then
				return nil, "note changed while choosing a new location"
			end
			item.user_data[annotations.key] = vim.deepcopy(moved)
			if owned then
				item.filename = location.absolute(value)
				item.bufnr = vim.fn.bufadd(item.filename)
				item.lnum, item.end_lnum = value.line or 0, value.line_end or 0
				item.col, item.end_col = 0, 0
			end
			found = true
		end
	end
	if not found then
		return nil, owned and "note no longer exists" or nil
	end
	return { target = target, before = snapshot, items = items }
end

function M.apply(entry, value)
	if source.matches(value) == false and not value.revision then
		return nil, "destination changed while choosing a note; choose the location again"
	end
	local moved = vim.deepcopy(entry.note)
	moved.location = vim.deepcopy(value)
	moved.updated_at = os.time()
	local owned, err = prepare(entry.list, entry, moved, true)
	if not owned then
		return nil, err
	end
	local plans = { owned }
	local origin = entry.note.origin
	if origin and origin.id ~= entry.list.id and (not entry.origin_checked or entry.origin_note) then
		local producer, producer_err = prepare(entry.note.origin, entry, moved, false)
		if producer_err then
			return nil, producer_err
		end
		if producer then
			plans[#plans + 1] = producer
		end
	end
	for index, plan in ipairs(plans) do
		local before = plan.before
		local ok, replace_err = lists.replace(plan.target, plan.items, before.idx, before.changedtick)
		if not ok then
			if index > 1 then
				-- A single native replacement increments changedtick once. Never undo someone else's edit.
				local restored = lists.replace(owned.target, owned.before.items, owned.before.idx,
					owned.before.changedtick + 1)
				if not restored then
					return nil, "producer update failed and managed list changed; inspect both copies"
				end
			end
			return nil, replace_err
		end
	end
	return true
end

return M
