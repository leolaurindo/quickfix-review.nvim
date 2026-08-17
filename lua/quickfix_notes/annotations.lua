local M = {}

M.key = "quickfix_notes"
M.version = 1

local function now()
	return os.time()
end

local function new_id()
	return table.concat({ now(), vim.fn.reltimefloat(vim.fn.reltime()), math.random(1000000) }, "-")
end

function M.get(item)
	if type(item) ~= "table" or type(item.user_data) ~= "table" then
		return nil
	end
	local note = item.user_data[M.key]
	return type(note) == "table" and note or nil
end

function M.location(note)
	return type(note) == "table" and type(note.location) == "table" and note.location or note
end

function M.create(location, text, id)
	local stamp = now()
	return {
		version = M.version,
		id = id and tostring(id) or new_id(),
		text = text or "",
		created_at = stamp,
		updated_at = stamp,
		location = vim.deepcopy(location),
	}
end

function M.set(item, location, text, existing)
	if type(item.user_data) == "nil" then
		item.user_data = {}
	elseif type(item.user_data) ~= "table" then
		return nil, "cannot annotate an item with non-table user_data"
	end
	local old = M.get(item)
	local note = M.create(location, text, existing and existing.id or old and old.id)
	note.created_at = existing and existing.created_at or old and old.created_at or note.created_at
	local source_text = old and old.source_text or item.text
	if source_text and source_text ~= "" and source_text ~= note.text then
		note.source_text = source_text
	end
	item.user_data[M.key] = note
	return note
end

function M.composed_text(note)
	if type(note) ~= "table" then
		return ""
	end
	if note.source_text and note.source_text ~= "" and note.source_text ~= note.text then
		return note.source_text .. " | Note: " .. (note.text or "")
	end
	return "Note: " .. (note.text or "")
end

function M.update(item, text, location)
	local old = M.get(item)
	if not old then
		return nil, "item is not annotated"
	end
	return M.set(item, location or old.location, text, old)
end

function M.remove(item)
	if type(item.user_data) ~= "table" then
		return false
	end
	if not item.user_data[M.key] then
		return false
	end
	item.user_data[M.key] = nil
	return true
end

function M.clone(item)
	local copy = vim.deepcopy(item)
	return copy, M.get(copy)
end

function M.valid(note)
	return type(note) == "table" and type(note.id) == "string" and type(note.location) == "table"
end

return M
