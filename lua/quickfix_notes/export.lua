local lists = require("quickfix_notes.lists")
local annotations = require("quickfix_notes.annotations")
local location = require("quickfix_notes.location")

local M = {}

local function native_path(item)
	if item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
		local name = vim.api.nvim_buf_get_name(item.bufnr)
		if name ~= "" then
			return name
		end
	end
	return item.filename or (item.module and item.module:match("^[/~%w%.][^|]*$"))
end

local function relative(root, path)
	return location.relative(root, path)
end

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
	return nil
end

function M.records(opts)
	opts = opts or {}
	local target = target_for(opts)
	if not target then
		local owned = lists.find_owned(opts.scope_id)
		if not owned then
			return nil, "no QuickfixNotes list"
		end
		target = { kind = "quickfix", id = owned.id }
	end
	local snapshot, err, resolved = lists.read(target)
	if not snapshot then
		return nil, err
	end
	local root = opts.root
	local records, errors = {}, {}
	for index, item in ipairs(snapshot.items or {}) do
		local note = annotations.get(item)
		local annotated_location = note and location.canonical(note.location)
		local path = annotated_location and annotated_location.path
		local native = native_path(item)
		if not path and native then
			path = relative(root, native)
		end
		local context_row = item.valid ~= 1 and not native and not item.module
		if not context_row or (opts.include_context == true and (path or item.module)) then
			if not path or path == "" then
				errors[#errors + 1] = "item " .. index .. " has no resolvable path"
			else
				local loc = annotated_location
					or location.canonical({
						root = root or vim.fn.getcwd(),
						file = path,
						line = item.lnum,
						line_end = item.end_lnum,
					})
				local text = note and note.text or item.text or ""
				if type(opts.text) == "function" then
					local ok, selected = pcall(opts.text, item, note, text)
					if not ok then
						return nil, "text selector failed for item " .. index .. ": " .. tostring(selected)
					end
					text = selected == nil and text or tostring(selected)
				end
				records[#records + 1] = {
					index = index,
					path = path,
					line = loc.line,
					line_end = loc.line_end,
					text = text,
					id = note and note.id,
					kind = resolved.kind,
				}
			end
		end
	end
	if #errors > 0 and opts.strict ~= false then
		return nil, table.concat(errors, "; "), { snapshot = snapshot, target = resolved, errors = errors }
	end
	return records, nil, { snapshot = snapshot, target = resolved, errors = errors }
end

function M.format(records, name, opts)
	local ok, formatter = pcall(require, "quickfix_notes.formatters." .. (name or "markdown"))
	if not ok then
		return nil, "unknown formatter: " .. tostring(name)
	end
	return formatter.format(records, opts)
end

return M
