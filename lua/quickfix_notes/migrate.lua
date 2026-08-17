local M = {}
local annotations = require("quickfix_notes.annotations")
local lists = require("quickfix_notes.lists")
local location = require("quickfix_notes.location")

local function legacy_paths(scope)
	local safe_root = scope.root:gsub("^/", ""):gsub("[/\\:]", "_")
	local branch = (scope.branch or "detached"):gsub("[/\\:]", "_")
	return {
		vim.fn.stdpath("data") .. "/quickfix-notes/" .. safe_root .. "-" .. branch .. ".json",
		vim.fn.stdpath("data") .. "/reviewnotes/" .. safe_root .. "-" .. branch .. ".json",
	}
end

function M.read(scope)
	for _, path in ipairs(legacy_paths(scope)) do
		if vim.fn.filereadable(path) == 1 then
			local ok, value = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
			if not ok or type(value) ~= "table" then
				return nil, "could not decode legacy notes: " .. path
			end
			return value, path
		end
	end
	return nil, "legacy notes not found"
end

function M.apply(scope_id, scope_value, opts)
	local records, err = M.read(scope_value)
	if not records then
		return nil, err
	end
	local owned, target = lists.ensure_owned(opts, scope_id)
	local items = vim.deepcopy(owned.items or {})
	for _, record in ipairs(records) do
		local value = location.canonical({
			root = record.root or scope_value.root,
			file = record.path or record.file,
			line = record.line,
			line_end = record.line_end,
			side = record.side,
			revision = record.revision,
			hash = record.hash,
		})
		if value and value.path and value.line then
			local item = {
				filename = location.absolute(value),
				lnum = value.line,
				end_lnum = value.line_end,
				valid = 1,
				type = "N",
				text = (record.text or ""):gsub("\n", " "),
				user_data = {},
			}
			annotations.set(item, value, record.text or "", record)
			items[#items + 1] = item
		end
	end
	local ok, replace_err = lists.replace(target, items, owned.idx, owned.changedtick)
	return ok and #items or nil, replace_err
end

return M
