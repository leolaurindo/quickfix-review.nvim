local ok, generic = pcall(require, "quickfix_export")
if not ok then
	error("Quickfix Review requires quickfix-export.nvim (quickfix_export): " .. tostring(generic), 0)
end

local lists = require("quickfix_review.lists")
local annotations = require("quickfix_review.annotations")
local location = require("quickfix_review.location")

local source = require("quickfix_review.source")
local config = require("quickfix_review.config")

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
		return nil, "no Quickfix Review list"
	end
	local note_origin = opts.note_origin
	if note_origin ~= nil and note_origin ~= "user" and note_origin ~= "agent" then
		return nil, "note_origin must be user or agent"
	end
	local generic_opts = vim.tbl_extend("force", opts, { list = target })
	if note_origin ~= nil then
		generic_opts.strict = false
	end
	local selector = opts.text
	generic_opts.text = function(item, default_text)
		local annotation = annotations.get(item)
		local text = annotation and annotation.text or default_text
		return type(selector) == "function" and selector(item, annotation, text) or text
	end
	local warn_stale = opts.warn_stale
	if warn_stale == nil then
		warn_stale = config.get().warn_stale
	end
	local records, err, details = generic.records(generic_opts)
	if not records then
		return nil, err, details
	end
	if note_origin ~= nil then
		local filtered = {}
		for _, record in ipairs(records) do
			local item = details.snapshot.items[record.index]
			local annotation = item and annotations.get(item)
			if annotation and annotations.origin(annotation) == note_origin then
				filtered[#filtered + 1] = record
			end
		end
		records = filtered
	end
	local fingerprints = {}
	for _, record in ipairs(records) do
		local item = details.snapshot.items[record.index]
		local annotation = item and annotations.get(item)
		if annotation and annotation.metadata ~= nil then
			local encoded, metadata = pcall(vim.json.encode, annotation.metadata)
			if not encoded then
				return nil, "invalid annotation metadata for item " .. record.index .. ": " .. tostring(metadata), details
			end
			record.metadata = vim.json.decode(metadata)
		end
		local note_location = annotation and location.canonical(annotation.location)
		if note_location then
			record.path = note_location.path
			record.line = note_location.line
			record.line_end = note_location.line_end
			record.side = note_location.side
			record.revision = note_location.revision
			record.hash = note_location.hash
			local labels, stale = source.describe(note_location, fingerprints)
			record.stale = stale or nil
			if stale and warn_stale then
				labels[#labels + 1] = "location may be stale"
			end
			if annotations.origin(annotation) == "agent" then
				labels[#labels + 1] = "source: agent"
			end
			record.labels = #labels > 0 and labels or nil
			details.stale = (details.stale or 0) + (stale and 1 or 0)
		end
	end
	return records, nil, details
end

function M.format(records, name, opts)
	return generic.format(records, name, opts)
end

return M
