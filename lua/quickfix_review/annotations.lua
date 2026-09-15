local M = {}

M.key = "quickfix_review"
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

function M.create(location, text, id, metadata)
	local stamp = now()
	local note = {
		version = M.version,
		id = id and tostring(id) or new_id(),
		text = text or "",
		created_at = stamp,
		updated_at = stamp,
		location = require("quickfix_review.source").capture(location),
	}
	if metadata ~= nil then
		note.metadata = vim.deepcopy(metadata)
	end
	return note
end

function M.set(item, location, text, existing, metadata)
	if type(item.user_data) == "nil" then
		item.user_data = {}
	elseif type(item.user_data) ~= "table" then
		return nil, "cannot annotate an item with non-table user_data"
	end
	local old = M.get(item)
	local previous = existing or old
	local note = M.create(
		location,
		text,
		existing and existing.id or old and old.id,
		metadata == nil and old and old.metadata or metadata
	)
	note.created_at = previous and previous.created_at or note.created_at
	note.origin = previous and vim.deepcopy(previous.origin) or nil
	-- Editing text must not acknowledge a changed source as a new anchor.
	if old and require("quickfix_review.location").equal(old.location, location) then
		note.location.fingerprint = old.location.fingerprint
	end
	item.user_data[M.key] = note
	return note
end

function M.update(item, text, location, metadata)
	local old = M.get(item)
	if not old then
		return nil, "item is not annotated"
	end
	return M.set(item, location or old.location, text, old, metadata)
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

function M.origin(note)
	local metadata = type(note) == "table" and note.metadata
	if type(metadata) ~= "table" then
		return "user"
	end
	if metadata.origin == "agent" then
		return "agent"
	end
	return "user"
end

function M.valid(note)
	return type(note) == "table" and type(note.id) == "string" and type(note.location) == "table"
end

return M
