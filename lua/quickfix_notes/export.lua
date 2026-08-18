local ok, generic = pcall(require, "quickfix_export")
if not ok then
	error("QuickfixNotes requires quickfix-export.nvim (quickfix_export): " .. tostring(generic), 0)
end

local lists = require("quickfix_notes.lists")
local annotations = require("quickfix_notes.annotations")
local location = require("quickfix_notes.location")

local M = {}

local function target_for(opts)
	if opts and opts.list then
		return opts.list
	end
	if opts and (opts.kind or opts.id or opts.winid) then
		return opts
	end
	if vim.bo.buftype == "quickfix" then
		local current = lists.current()
		return current and { kind = current.kind, id = current.id, winid = current.winid }
	end
	local owned = lists.find_owned(opts and opts.scope_id)
	return owned and { kind = "quickfix", id = owned.id }
end

function M.records(opts)
	opts = opts or {}
	local target = target_for(opts)
	if not target then
		return nil, "no QuickfixNotes list"
	end
	local generic_opts = vim.tbl_extend("force", opts, { list = target })
	local selector = opts.text
	generic_opts.text = function(item, default_text)
		local note = annotations.get(item)
		local text = note and note.text or default_text
		return type(selector) == "function" and selector(item, note, text) or text
	end
	local records, err, details = generic.records(generic_opts)
	if not records then
		return nil, err, details
	end
	for _, record in ipairs(records) do
		local item = details.snapshot.items[record.index]
		local note = item and annotations.get(item)
		local note_location = note and location.canonical(note.location)
		if note_location then
			record.path = note_location.path
			record.line = note_location.line
			record.line_end = note_location.line_end
		end
	end
	return records, nil, details
end

function M.format(records, name, opts)
	return generic.format(records, name, opts)
end

return M
