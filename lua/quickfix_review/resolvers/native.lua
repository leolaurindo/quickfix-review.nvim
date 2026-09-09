local M = { name = "native", priority = 10, renderable = true }

function M.detect(bufnr, winid)
	return vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.wo[winid].diff == true
end

function M.location(bufnr, winid)
	return require("quickfix_review.resolvers.normal").location(bufnr, winid)
end

function M.range_location(bufnr, start_line, stop_line)
	return require("quickfix_review.resolvers.normal").range_location(bufnr, start_line, stop_line)
end

function M.anchor(note)
	return note.line_end or note.line
end

return M
