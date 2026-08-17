local M = {}

function M.format(records)
	local lines = {}
	for _, record in ipairs(records) do
		local path = record.path
		if record.line then
			path = path .. ":" .. record.line
			if record.line_end and record.line_end ~= record.line then
				path = path .. "-" .. record.line_end
			end
		end
		lines[#lines + 1] = ("- `%s` - %s"):format(path, (record.text or ""):gsub("\n", " "))
	end
	return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

return M
