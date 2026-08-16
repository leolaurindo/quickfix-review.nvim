local M = {}

M.defaults = {
	send = "clipboard",
	send_opts = {},
	list = "quickfix", -- "quickfix" | "snacks" | "telescope" | "mini"
	quickfix_title = "review",
	inline = true, -- Set false to disable inline note markers.
	glyph = "▲", -- Set false to hide the inline marker.
	float = {
		enabled = true,
		delay = 500,
		permanent = false,
	},
	keys = {
		note = "<leader>rn",
		send = "<leader>rs",
		export = "<leader>re",
		export_and_clear = "<leader>rx",
		clear = "<leader>rc",
		list = "<leader>rl",
		next = "]r",
		prev = "[r",
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.get()
	return M.options
end

return M
