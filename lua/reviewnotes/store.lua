local M = {}
local notes = require("quickfix_notes")
local lists = require("quickfix_notes.lists")
local annotation = require("quickfix_notes.annotations")
local location = require("quickfix_notes.location")

function M.scope()
	return notes.scope()
end
function M.repo_root(path)
	return location.repo_root(path)
end
function M.switch_scope()
	return false
end

local function records()
	local out = {}
	local owned = lists.find_owned()
	if owned then
		for _, item in ipairs(owned.items or {}) do
			local note = annotation.get(item)
			if note then
				local loc = location.canonical(note.location)
				out[#out + 1] =
					vim.tbl_extend("force", vim.deepcopy(loc), { file = loc.path, text = note.text, id = note.id })
			end
		end
	end
	return out
end

function M.all()
	return records()
end
function M.count()
	return #records()
end
function M.get(id)
	for _, note in ipairs(records()) do
		if note.id == id then
			return note
		end
	end
end
function M.at(value)
	for _, note in ipairs(records()) do
		if location.equal(note, value) then
			return note
		end
	end
end

function M.add(value, text)
	local entry = lists.current()
	if not entry or not entry.item then
		return nil
	end
	local item = vim.deepcopy(entry.item)
	local note, err = annotation.set(item, value, text)
	if not note then
		return nil, err
	end
	local items = vim.deepcopy(entry.items)
	items[entry.index] = item
	local ok, replace_err = lists.replace(
		{ kind = entry.kind, id = entry.id, winid = entry.winid },
		items,
		entry.list.idx,
		entry.changedtick
	)
	return ok and vim.tbl_extend("force", vim.deepcopy(value), { id = note.id, text = text }) or nil, replace_err
end

function M.update(id, fields)
	local entry = lists.current()
	if not entry then
		return
	end
	local ok = lists.update_item({ kind = entry.kind, id = entry.id, winid = entry.winid }, entry.index, function(item)
		local note = annotation.get(item)
		if not note or note.id ~= id then
			return nil
		end
		annotation.update(item, fields.text, note.location)
		return true
	end, id)
	return ok and M.get(id)
end

function M.delete(id)
	local entry = lists.current()
	if not entry then
		return false
	end
	return lists.update_item({ kind = entry.kind, id = entry.id, winid = entry.winid }, entry.index, function(item)
		return annotation.remove(item)
	end, id)
end

function M.clear()
	local owned = lists.find_owned()
	if not owned then
		return 0
	end
	local count = #(owned.items or {})
	lists.clear({ kind = "quickfix", id = owned.id })
	return count
end

function M.for_file(file)
	return vim.tbl_filter(function(note)
		return note.file == file
	end, records())
end

return M
