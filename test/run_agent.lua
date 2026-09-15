vim.env.XDG_DATA_HOME = "/tmp/quickfix_review-agent-test-data"
vim.env.XDG_STATE_HOME = "/tmp/quickfix_review-agent-test-state"
local plugin_root = vim.fn.getcwd()

local function add_dependency(env, sibling)
	local path = vim.env[env]
	if not path or path == "" then
		path = vim.fs.joinpath(vim.fn.fnamemodify(plugin_root, ":h"), sibling)
	end
	vim.opt.rtp:prepend(path)
end

add_dependency("QUICKFIX_ACTIONS_PATH", "quickfix-actions.nvim")
add_dependency("QUICKFIX_EXPORT_PATH", "quickfix-export.nvim")
vim.opt.rtp:prepend(plugin_root)

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
assert(vim.fn.writefile({ "one", "two", "three", "four", "five" }, vim.fs.joinpath(root, "README.md")) == 0)
vim.cmd.cd(vim.fn.fnameescape(root))

local notes = require("quickfix_review")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local marks = require("quickfix_review.marks")
local sender = require("quickfix_review.sender")

assert(require("quickfix_review.config").defaults.agent.response.watch == true)
notes.setup({ persist_review_list = false, scope_policy = "repository" })
assert(vim.fn.exists(":QuickfixReviewSendAgent") == 2)
assert(vim.fn.exists(":QuickfixReviewSendAgentAndClear") == 2)
assert(vim.fn.exists(":QuickfixReviewClearAgent") == 2)
assert(vim.fn.exists(":QuickfixReviewReloadAgentResponse") == 2)

local nongit = vim.fn.tempname()
vim.fn.mkdir(nongit, "p")
local unprotected, protect_warning = require("quickfix_review.agent.file").protect(
	nongit,
	".quickfix-review/agent-response.json",
	true
)
assert(unprotected and protect_warning and protect_warning:find("visible to Git", 1, true))
vim.fn.delete(nongit, "rf")

local filename = vim.fs.joinpath(root, "README.md")
local item = { filename = filename, lnum = 1, text = "producer", user_data = {} }
assert(annotations.set(item, {
	root = root,
	path = "README.md",
	line = 1,
	resolver = "normal",
}, "Inspect this cleanup", nil, { origin = "user" }))
vim.fn.setqflist({}, "r", {
	title = "agent attention",
	items = { item, { filename = filename, lnum = 1, text = "unreviewed producer row" } },
})
local current = assert(lists.current())
local target = { kind = "quickfix", id = current.id }

local submitted, sent
sender.register({
	name = "sidekick",
	send = function(payload, opts)
		sent, submitted = payload, opts.submit
		return true
	end,
})
assert(notes.send_agent({ list = target, submit = false }))
assert(submitted == false)
assert(sent:find("Quickfix Review notes for this review:", 1, true))
assert(sent:find("Inspect this cleanup", 1, true))
assert(not sent:find("unreviewed producer row", 1, true))
assert(sent:find("End of Quickfix Review notes.", 1, true))
assert(sent:find("Review these notes", 1, true))
assert(sent:find(".quickfix-review/agent-response.json", 1, true))
assert(sent:find("If that file already exists", 1, true))
assert(sent:find("<payload%-path>%.ready"))
assert(sent:find("deletes both files after a successful import", 1, true))
assert(sent:find("disappearance confirms successful consumption", 1, true))
assert(sent:find("do not recreate them for this review request", 1, true))
vim.cmd("copen")
vim.cmd("QuickfixReviewSendAgent!")
assert(submitted == true)
vim.cmd("cclose")

notes.setup({
	persist_review_list = false,
	scope_policy = "repository",
	agent = { response = { watch = true } },
})
local response = {
	version = 1,
	origin = "agent",
	findings = {
		{
			path = "README.md",
			line = 1,
			line_end = 3,
			text = "Agent response",
			metadata = { origin = "user" },
		},
	},
}
local response_path = vim.fs.joinpath(root, ".quickfix-review/agent-response.json")
local ready_path = response_path .. ".ready"
assert(vim.fn.writefile({ "{" }, response_path) == 0)
vim.wait(100)
assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())) == nil)
assert(vim.fn.writefile({ vim.json.encode(response) }, response_path) == 0)
assert(vim.fn.writefile({}, ready_path) == 0)
assert(vim.wait(2000, function()
	local owned = lists.find_owned(require("quickfix_review.scope").id(notes.scope()))
	for _, owned_item in ipairs(owned and owned.items or {}) do
		local note = annotations.get(owned_item)
		if note and note.text == "Agent response" then
			assert(note.metadata.origin == "agent")
			return true
		end
	end
	return false
end, 20))
assert(vim.fn.filereadable(response_path) == 0)
assert(vim.fn.filereadable(ready_path) == 0)
local user_payload = {
	version = 1,
	origin = "user",
	findings = { { id = "user-one", path = "README.md", line = 1, text = "User response" } },
}
local user_result = assert(notes.import_findings(user_payload))
assert(user_result.added == 1)
local owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local default_records = assert(require("quickfix_review.export").records({
	list = { kind = "quickfix", id = owned.id },
}))
local all_records = assert(require("quickfix_review.export").records({
	list = { kind = "quickfix", id = owned.id },
	include_agent_notes = true,
}))
assert(#default_records == 1 and default_records[1].text == "User response")
assert(#all_records == 2)

local ignored = vim.system({
	"git", "-C", root, "check-ignore", "-q", "--no-index", ".quickfix-review/agent-response.json",
}):wait()
assert(ignored.code == 0)
local status = vim.system({ "git", "-C", root, "status", "--short" }, { text = true }):wait()
assert(status.code == 0 and not status.stdout:find(".quickfix-review", 1, true))

assert(vim.fn.writefile({ "{" }, response_path) == 0)
assert(vim.fn.writefile({}, ready_path) == 0)
assert(vim.wait(2000, function()
	return vim.fn.filereadable(ready_path) == 0
end, 20))
assert(vim.fn.filereadable(response_path) == 1)
local invalid, invalid_err = notes.reload_agent_response()
assert(not invalid and invalid_err:find("invalid findings JSON", 1, true))
assert(vim.fn.filereadable(response_path) == 1)
assert(vim.fn.delete(response_path) == 0)
local agent_file = require("quickfix_review.agent.file")
agent_file.stop()
notes.setup({
	persist_review_list = false,
	scope_policy = "repository",
	agent = { response = { watch = false } },
})
assert(vim.fn.writefile({ vim.json.encode({
	version = 1,
	origin = "agent",
	findings = { { id = "manual-default", path = "README.md", text = "Imported from the default path" } },
}) }, response_path) == 0)
vim.cmd("QuickfixReviewImport")
assert(vim.fn.filereadable(response_path) == 1)
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local found_manual_default = false
for _, owned_item in ipairs(owned.items) do
	local note = annotations.get(owned_item)
	found_manual_default = found_manual_default or (note and note.id == "manual-default")
end
assert(found_manual_default)
assert(vim.fn.delete(response_path) == 0)

local response_dir = vim.fs.joinpath(root, ".quickfix-review")
local first_path = vim.fs.joinpath(response_dir, "first-race-response.json")
local second_path = vim.fs.joinpath(response_dir, "second-race-response.json")
local imported_ids = {}
assert(agent_file.setup({
	root = root,
	path = ".quickfix-review/race-response.json",
	protect_git = false,
	import = function(payload)
		imported_ids[#imported_ids + 1] = payload.id
		return {}
	end,
}))
assert(vim.fn.writefile({ vim.json.encode({ id = "first" }) }, first_path) == 0)
assert(vim.fn.writefile({ vim.json.encode({ id = "second" }) }, second_path) == 0)
assert(vim.fn.writefile({}, first_path .. ".ready") == 0)
assert(vim.fn.writefile({}, second_path .. ".ready") == 0)
assert(vim.wait(2000, function()
	return #imported_ids == 2
end, 20))
table.sort(imported_ids)
assert(imported_ids[1] == "first" and imported_ids[2] == "second")
assert(vim.fn.filereadable(first_path) == 0 and vim.fn.filereadable(first_path .. ".ready") == 0)
assert(vim.fn.filereadable(second_path) == 0 and vim.fn.filereadable(second_path .. ".ready") == 0)
agent_file.stop()

local outside = vim.fn.tempname()
vim.fn.mkdir(outside, "p")
assert(vim.fn.writefile({ "outside" }, vim.fs.joinpath(outside, "outside.lua")) == 0)
local link = vim.fs.joinpath(root, "outside-link")
assert(vim.uv.fs_symlink(outside, link))
local escaped = assert(notes.import_findings({
	version = 1,
	findings = { { id = "escaped", path = "outside-link/outside.lua", text = "must be rejected" } },
}))
assert(escaped.skipped == 1 and escaped.errors[1]:find("outside", 1, true))
vim.fn.delete(link)
vim.fn.delete(outside, "rf")

notes.open_list()
local qfbuf = vim.api.nvim_get_current_buf()
marks.render(qfbuf)
local namespace = vim.api.nvim_get_namespaces().quickfix_review
local function has_marker(bufnr, text, combined)
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
	for _, extmark in ipairs(extmarks) do
		local virt_text = extmark[4].virt_text
		if virt_text and virt_text[1] and virt_text[1][1]:find(text, 1, true) then
			assert(virt_text[1][2] == "QuickfixReviewMark")
			assert(not combined or extmark[4].hl_mode == "combine")
			return true
		end
	end
	return false
end
assert(has_marker(qfbuf, "󰚩", true))
assert(has_marker(qfbuf, "󰏫", true))
marks.setup({ nerd_font = false })
marks.render(qfbuf)
assert(has_marker(qfbuf, "AGENT", true))
assert(has_marker(qfbuf, "✎", true))
marks.setup(require("quickfix_review.config").get())

vim.cmd("cclose")
vim.cmd.edit(filename)
marks.render(0)
assert(has_marker(0, "󰚩"))
assert(has_marker(0, "󰏫"))
local preview = vim.lsp.util.open_floating_preview
local previews = 0
vim.lsp.util.open_floating_preview = function()
	previews = previews + 1
end
vim.api.nvim_win_set_cursor(0, { 2, 0 })
marks.hover(0)
assert(previews == 0)
marks.hover(0, { force = true })
assert(previews == 1)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
marks.hover(0)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
marks.hover(0)
assert(previews == 3)
vim.lsp.util.open_floating_preview = preview

assert(notes.clear_agent_reviews())
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
assert(#owned.items == 1 and annotations.origin(assert(annotations.get(owned.items[1]))) == "user")
assert(notes.import_findings(response, { origin = "agent" }))
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
sender.register({
	name = "sidekick",
	send = function(payload)
		sent = payload
		return true
	end,
})
local review_target = { kind = "quickfix", id = owned.id }
assert(notes.export_and_clear({ list = review_target, destination = "sidekick" }))
assert(sent:find("User response", 1, true) and not sent:find("Agent response", 1, true))
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
assert(#owned.items == 1 and annotations.origin(assert(annotations.get(owned.items[1]))) == "agent")
assert(notes.import_findings(user_payload))
assert(notes.send_agent_and_clear({ list = review_target, submit = false }))
assert(sent:find("User response", 1, true) and not sent:find("Agent response", 1, true))
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
assert(#owned.items == 0)

require("quickfix_review.agent.file").stop()
vim.cmd.cd(vim.fn.fnameescape(plugin_root))
vim.fn.delete(root, "rf")
print("quickfix_review agent response tests passed")
