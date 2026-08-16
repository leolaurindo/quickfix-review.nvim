local M = {}

M.name = "clipboard"

---Copy markdown to the system clipboard.
function M.send(markdown, _opts)
	vim.fn.setreg("+", markdown)
	return true
end

return M
