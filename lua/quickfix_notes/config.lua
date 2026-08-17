local M = {}

M.defaults = {
	send = "clipboard",
	send_opts = {},
	quickfix_title = "Quickfix Notes",
	persist_review_list = true,
	scope_policy = "branch",
	inline = true,
	glyph = "▲",
	float = { enabled = true, delay = 500, permanent = false },
	quickfix = {
		inline = true,
		float = { enabled = true, delay = 500, permanent = false, command = true },
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

local options = vim.deepcopy(M.defaults)

function M.setup(opts)
	options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	if
		options.scope_policy ~= "branch"
		and options.scope_policy ~= "repository"
		and options.scope_policy ~= "custom"
	then
		options.scope_policy = "branch"
	end
	return options
end

function M.get()
	return options
end

return M
