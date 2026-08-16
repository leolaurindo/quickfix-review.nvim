local M = {}

M.name = "file"

---Write markdown to a file. opts.path or opts.filename; defaults to a
---timestamped file in the data dir.
function M.send(markdown, opts)
	opts = opts or {}
	local store = require("reviewnotes.store")
	local scope = store.scope()
	local dir = opts.path or (vim.fn.stdpath("data") .. "/reviewnotes")
	vim.fn.mkdir(dir, "p")

	local filename = opts.filename or (scope and scope.branch) or "review-notes"
	filename = filename:gsub("[/\\]", "_") .. "-" .. os.date("%Y%m%d-%H%M%S") .. ".md"

	local path = dir .. "/" .. filename
	vim.fn.writefile(vim.split(markdown, "\n", { plain = true }), path)
	return true, path
end

return M
