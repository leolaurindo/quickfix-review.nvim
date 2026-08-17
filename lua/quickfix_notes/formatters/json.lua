local M = {}

function M.format(records)
	return vim.json.encode(records) .. "\n"
end

return M
