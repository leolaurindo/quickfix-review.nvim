return {
	name = "file",
	send = function(payload, opts)
		opts = opts or {}
		local dir = opts.path or (vim.fn.stdpath("data") .. "/quickfix-notes")
		vim.fn.mkdir(dir, "p")
		local filename = opts.filename or (os.date("%Y%m%d-%H%M%S") .. ".md")
		local path = vim.fs.joinpath(dir, filename)
		local ok, err = pcall(vim.fn.writefile, vim.split(payload, "\n", { plain = true }), path)
		return ok and path or false, ok and nil or err
	end,
}
