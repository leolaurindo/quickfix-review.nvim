local M = {}

local store = require("reviewnotes.store")

---Order notes: keep insertion order (already chronological in the store).
---@param notes table[]
---@return string markdown
function M.render(notes, scope)
	scope = scope or store.scope()
	local lines = {
		"# Review Notes: " .. (scope and scope.branch or "unknown"),
		"",
	}

	-- Group by file, preserving first-seen order.
	local files = {}
	for _, n in ipairs(notes) do
		files[n.file] = files[n.file] or {}
		files[n.file][#files[n.file] + 1] = n
	end

	for file, file_notes in pairs(files) do
		lines[#lines + 1] = "## " .. file
		lines[#lines + 1] = ""
		for _, n in ipairs(file_notes) do
			lines[#lines + 1] = M.note_line(n)
		end
		lines[#lines + 1] = ""
	end

	return table.concat(lines, "\n"):gsub("\n+$", "\n")
end

---Render valid quickfix items as markdown.
---@param items table[]
---@param title? string
---@return string markdown
function M.render_quickfix(items, title)
	local lines = { "# Quickfix: " .. (title or "quickfix"), "" }
	local files = {}
	for _, item in ipairs(items) do
		files[item.file] = files[item.file] or {}
		files[item.file][#files[item.file] + 1] = item
	end

	for file, file_items in pairs(files) do
		lines[#lines + 1] = "## " .. file
		lines[#lines + 1] = ""
		for _, item in ipairs(file_items) do
			lines[#lines + 1] = M.note_line(item)
		end
		lines[#lines + 1] = ""
	end

	return table.concat(lines, "\n"):gsub("\n+$", "\n")
end

---@param n table
---@return string one line: `path:10-20 - text`
function M.note_line(n)
	local loc = n.file
	if n.line then
		local prefix = n.side == "old" and "~" or ""
		loc = string.format("%s:%s%d", n.file, prefix, n.line)
		if n.line_end and n.line_end ~= n.line then
			loc = loc .. "-" .. prefix .. n.line_end
		end
	end
	local text = (n.text or ""):gsub("\n", " ")
	return string.format("- `%s` - %s", loc, text)
end

return M
