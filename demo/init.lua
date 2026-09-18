local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fn.fnamemodify(source, ":p:h:h")
local projects = vim.fn.fnamemodify(plugin_root, ":h")
local demo_root = "/tmp/quickfix-review-agent-demo"

vim.fn.delete(demo_root, "rf")
vim.fn.mkdir(demo_root, "p")
assert(vim.system({ "git", "init", "-q", demo_root }):wait().code == 0)
assert(vim.fn.writefile({
	"local function authenticate(token)",
	"  return token ~= nil",
	"end",
	"",
	"return authenticate",
}, demo_root .. "/auth.lua") == 0)

vim.opt.rtp:prepend(vim.env.QUICKFIX_ACTIONS_PATH or (projects .. "/quickfix-actions.nvim"))
vim.opt.rtp:prepend(vim.env.QUICKFIX_EXPORT_PATH or (projects .. "/quickfix-export.nvim"))
vim.opt.rtp:prepend(plugin_root)
vim.cmd.cd(vim.fn.fnameescape(demo_root))
vim.o.termguicolors = true
vim.g.mapleader = " "

local review = require("quickfix_review")
local sender = require("quickfix_review.sender")

review.setup({
	nerd_font = false,
	persist_review_list = false,
	scope_policy = "repository",
	send = "sidekick",
})

sender.register({
	name = "sidekick",
	send = function(payload)
		vim.fn.writefile(vim.split(payload, "\n", { plain = true }), demo_root .. "/sent-review.md")
		return true
	end,
})

vim.api.nvim_create_user_command("DemoShowSentReview", function()
	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
	vim.api.nvim_buf_set_name(buf, "Sidekick review request")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(demo_root .. "/sent-review.md"))
	vim.bo[buf].modifiable = false
end, {})

vim.api.nvim_create_user_command("DemoAgentRespond", function()
	local response_path = demo_root .. "/.quickfix-review/agent-response.json"
	vim.fn.mkdir(vim.fn.fnamemodify(response_path, ":h"), "p")
	vim.fn.writefile({ vim.json.encode({
		version = 1,
		origin = "agent",
		findings = {
			{
				path = "auth.lua",
				line = 2,
				text = "Accepting any non-nil token bypasses authentication.",
				severity = "high",
			},
			{
				path = "auth.lua",
				line = 5,
				text = "Return an error when token validation fails.",
				severity = "medium",
			},
		},
	}) }, response_path)
	vim.fn.writefile({}, response_path .. ".ready")
	vim.notify("Agent response delivered; importing findings...", vim.log.levels.INFO, { title = "Quickfix Review" })
end, {})
