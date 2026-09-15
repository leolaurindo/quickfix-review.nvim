local M = {}

M.defaults = {
	send = "clipboard",
	send_opts = {},
	warn_stale = true,
	actions = { mappings = { qf = false } },
	export = {},
	quickfix_title = "Quickfix Review",
	persist_review_list = true,
	scope_policy = "branch",
	inline = true,
	glyph = "▲",
	float = { enabled = true, delay = 500, permanent = false },
	quickfix = {
		prefill = true,
		inline = true,
		agent_label = { enabled = true, text = " AGENT " },
		float = { enabled = true, delay = 500, permanent = false, command = true },
	},
	agent = {
		protect_git = true,
		response = {
			watch = true,
			path = ".quickfix-review/agent-response.json",
		},
	},
	keys = {},
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
