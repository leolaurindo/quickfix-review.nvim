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
local response_dir = vim.fs.joinpath(root, ".quickfix-review")
vim.fn.mkdir(root, "p")
assert(vim.system({ "git", "init", "-q", root }):wait().code == 0)
local source_lines = {}
for i = 1, 20 do
	source_lines[i] = ({ "one", "two", "three", "four", "five" })[i] or ("line " .. i)
end
assert(vim.fn.writefile(source_lines, vim.fs.joinpath(root, "README.md")) == 0)
vim.cmd.cd(vim.fn.fnameescape(root))

local notes = require("quickfix_review")
local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local marks = require("quickfix_review.marks")
local sender = require("quickfix_review.sender")

assert(require("quickfix_review.config").defaults.agent.response.watch == true)
notes.setup({ persist_review_list = false, scope_policy = "repository" })
assert(vim.fn.isdirectory(response_dir) == 0)
local initially_ignored = vim.system({
	"git", "-C", root, "check-ignore", "-q", "--no-index", ".quickfix-review/agent-response.json",
}):wait()
assert(initially_ignored.code ~= 0)
assert(vim.fn.exists(":QuickfixReviewSendAgent") == 2)
assert(vim.fn.exists(":QuickfixReviewSendAgentAndClear") == 2)
assert(vim.fn.exists(":QuickfixReviewClearAgent") == 2)
assert(vim.fn.exists(":QuickfixReviewReloadAgentResponse") == 2)
assert(vim.fn.exists(":QuickfixReviewHoverAll") == 2)

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
assert(sent:find("Inspect this cleanup", 1, true))
assert(not sent:find("unreviewed producer row", 1, true))
assert(not sent:find("agent-response.json", 1, true))
assert(not sent:find("findings JSON", 1, true))
assert(not sent:find("Quickfix Review notes for this review:", 1, true))
assert(not sent:find("End of Quickfix Review notes.", 1, true))

local select = vim.ui.select
local selected_options
vim.ui.select = function(items, options, callback)
	selected_options = options
	assert(vim.tbl_contains(items, "question"))
	callback("question", 1)
end
notes.send_agent_from_template({ list = target, submit = false })
assert(selected_options.prompt == "Choose a Quickfix Review template")
assert(sent:find("Answer the question in these notes", 1, true))
assert(require("quickfix_review.config").get().template == "plain")
vim.ui.select = function(_, _, callback) callback("broader review", 2) end
notes.export_from_template({ list = target, destination = "sidekick" })
assert(sent:find("also look for other actionable issues", 1, true))
assert(require("quickfix_review.config").get().template == "plain")
vim.ui.select = function(_, _, callback) callback(nil) end
local cancelled_payload = sent
notes.export_from_template({ list = target, destination = "sidekick" })
assert(sent == cancelled_payload)
vim.ui.select = select

notes.setup({ template = "implement", persist_review_list = false, scope_policy = "repository" })
sender.register({ name = "sidekick", send = function(payload)
	sent = payload
	return true
end })
assert(notes.export({ list = target, destination = "sidekick" }))
assert(sent:find("Implement the requested changes", 1, true))
notes.setup({ template = "plain", persist_review_list = false, scope_policy = "repository" })
sender.register({ name = "sidekick", send = function(payload, opts)
	sent, submitted = payload, opts.submit
	return true
end })
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
	version = 2,
	origin = "agent",
	notes = {
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
assert(vim.fn.mkdir(response_dir, "p") == 1)
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
vim.wait(200)
assert(vim.fn.filereadable(ready_path) == 1 and vim.fn.filereadable(response_path) == 1)
local invalid, invalid_err = notes.reload_agent_response()
assert(not invalid and invalid_err:find("invalid findings JSON", 1, true))
assert(vim.fn.filereadable(response_path) == 1 and vim.fn.filereadable(ready_path) == 1)
assert(vim.fn.delete(response_path) == 0)
assert(vim.fn.delete(ready_path) == 0)
local agent_file = require("quickfix_review.agent.file")
agent_file.stop()
notes.setup({
	persist_review_list = false,
	scope_policy = "repository",
	agent = { response = { watch = false } },
})
-- setup resolves the scope (and its agent watcher) on the next event-loop tick:
-- let that pending work run before the watcher exercised below is installed.
vim.wait(100)
assert(vim.fn.writefile({ vim.json.encode({
	version = 1,
	origin = "agent",
	findings = { { id = "manual-default", path = "README.md", text = "Imported from the default path" } },
}) }, response_path) == 0)
vim.cmd("QuickfixReviewImport " .. vim.fn.fnameescape(response_path))
assert(vim.fn.filereadable(response_path) == 1)
owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local found_manual_default = false
for _, owned_item in ipairs(owned.items) do
	local note = annotations.get(owned_item)
	found_manual_default = found_manual_default or (note and note.id == "manual-default")
end
assert(found_manual_default)
assert(vim.fn.delete(response_path) == 0)

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

local scope_module = require("quickfix_review.scope")
local active_branch = assert(scope_module.branch(root))
local deferred_branch = "qfr-review-deferred"
local function response_payload(id, branch, version)
	local payload = {
		version = version or 2,
		origin = "agent",
		branch = branch,
		notes = { { id = id, path = "agent-import-test.md", line = 1, text = id } },
	}
	if payload.version == 1 then
		payload.findings = payload.notes
		payload.notes = nil
	end
	return payload
end
local function write_ready(name, payload)
	local path = vim.fs.joinpath(response_dir, name .. "-agent-response.json")
	assert(vim.fn.writefile({ vim.json.encode(payload) }, path) == 0)
	assert(vim.fn.writefile({}, path .. ".ready") == 0)
	return path
end
local function has_note(id)
	local list = lists.find_owned(scope_module.id(notes.scope()))
	for _, list_item in ipairs(list and list.items or {}) do
		local note = annotations.get(list_item)
		if note and (note.id == id or note.text == id) then
			return true
		end
	end
	return false
end

notes.setup({ persist_review_list = false, scope_policy = "repository", agent = { response = { watch = true } } })
vim.wait(100)
local matched_ready = write_ready("matched", response_payload("branch-match", active_branch))
local deferred_ready = write_ready("deferred", response_payload("branch-deferred", deferred_branch))
assert(vim.wait(2000, function()
	return vim.fn.filereadable(matched_ready) == 0
end, 20))
assert(has_note("branch-match"))
assert(vim.fn.filereadable(deferred_ready) == 1 and vim.fn.filereadable(deferred_ready .. ".ready") == 1)
assert(vim.system({ "git", "-C", root, "symbolic-ref", "HEAD", "refs/heads/" .. deferred_branch }):wait().code == 0)
vim.cmd("doautocmd FocusGained")
assert(vim.wait(2000, function()
	return vim.fn.filereadable(deferred_ready) == 0
end, 20))
assert(has_note("branch-deferred"))
assert(scope_module.branch(root) == deferred_branch)

notes.setup({ persist_review_list = false, scope_policy = "repository", agent = { response = { watch = false } } })
vim.wait(100)
local no_branch = write_ready("no-branch", response_payload("batch-no-branch", nil, 1))
local matching = write_ready("batch-match", response_payload("batch-match", deferred_branch))
local mismatching = write_ready("batch-mismatch", response_payload("batch-mismatch", active_branch))
local unsupported = write_ready("unsupported", { version = 99, origin = "agent", notes = {} })
local invalid_schema = write_ready("invalid-schema", { version = 2, origin = "agent", branch = 42, notes = {} })
local batch_ok = pcall(vim.cmd, "QuickfixReviewImport")
assert(not batch_ok)
assert(vim.fn.filereadable(no_branch) == 0 and vim.fn.filereadable(no_branch .. ".ready") == 0)
assert(vim.fn.filereadable(matching) == 0 and vim.fn.filereadable(matching .. ".ready") == 0)
assert(has_note("batch-no-branch") and has_note("batch-match"))
for _, path in ipairs({ mismatching, unsupported, invalid_schema }) do
	assert(vim.fn.filereadable(path) == 1 and vim.fn.filereadable(path .. ".ready") == 1)
end

local explicit_mismatch = vim.fs.joinpath(response_dir, "explicit-mismatch.json")
local explicit_payload = vim.json.encode(response_payload("explicit-override", active_branch))
assert(vim.fn.writefile({ explicit_payload }, explicit_mismatch) == 0)
local original_notify, import_message = vim.notify, nil
vim.notify = function(message)
	import_message = message
end
vim.cmd("QuickfixReviewImport " .. vim.fn.fnameescape(explicit_mismatch))
vim.notify = original_notify
assert(import_message:find("conflicts with active branch", 1, true))
assert(import_message:find(":QuickfixReviewImport! <file>", 1, true))
assert(not has_note("explicit-override"))
vim.cmd("QuickfixReviewImport! " .. vim.fn.fnameescape(explicit_mismatch))
assert(has_note("explicit-override"))
local explicit_unsupported = vim.fs.joinpath(response_dir, "explicit-unsupported.json")
assert(vim.fn.writefile({ vim.json.encode({ version = 99, notes = {} }) }, explicit_unsupported) == 0)
local unsupported_ok = pcall(vim.cmd, "QuickfixReviewImport! " .. vim.fn.fnameescape(explicit_unsupported))
assert(not unsupported_ok)
assert(not has_note("explicit-unsupported"))
assert(vim.fn.filereadable(explicit_unsupported) == 1)
assert(vim.system({ "git", "-C", root, "symbolic-ref", "HEAD", "refs/heads/" .. active_branch }):wait().code == 0)

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
local function marker_count(bufnr, text, combined)
	local count = 0
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
	for _, extmark in ipairs(extmarks) do
		local virt_text = extmark[4].virt_text
		if virt_text and virt_text[1] and virt_text[1][1]:find(text, 1, true) then
			assert(virt_text[1][2] == "QuickfixReviewMark")
			assert(not combined or extmark[4].hl_mode == "combine")
			count = count + 1
		end
	end
	return count
end
local function has_marker(bufnr, text, combined)
	return marker_count(bufnr, text, combined) > 0
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
assert(marker_count(0, "󰚩") == 2)
assert(marker_count(0, "󰏫") == 1)
-- Count hover draws: one per float window creation, plus one per content update of the
-- hover buffer (the float itself is reused now).
local open_win, set_lines = vim.api.nvim_open_win, vim.api.nvim_buf_set_lines
local previews = 0
local function is_float_buf(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			return true
		end
	end
	return false
end
vim.api.nvim_open_win = function(buf, enter, config)
	if config and config.relative and config.relative ~= "" then
		previews = previews + 1
	end
	return open_win(buf, enter, config)
end
vim.api.nvim_buf_set_lines = function(buf, ...)
	if is_float_buf(buf) then
		previews = previews + 1
	end
	return set_lines(buf, ...)
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
vim.api.nvim_open_win, vim.api.nvim_buf_set_lines = open_win, set_lines

local source_win = vim.api.nvim_get_current_win()
local function overlay_count()
	local count = 0
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		local config = vim.api.nvim_win_get_config(winid)
		if config.relative == "win" and config.win == source_win then
			count = count + 1
		end
	end
	return count
end
local function scroll_to(line)
	vim.api.nvim_win_set_cursor(source_win, { line, 0 })
	vim.api.nvim_win_call(source_win, function()
		vim.cmd("normal! zt")
	end)
	vim.api.nvim_exec_autocmds("WinScrolled", { modeline = false })
end
vim.api.nvim_win_set_height(source_win, 3)
scroll_to(15)
vim.cmd("QuickfixReviewHoverAll")
assert(overlay_count() == 0)
scroll_to(1)
assert(overlay_count() == 2)
scroll_to(15)
assert(overlay_count() == 0)
scroll_to(3)
assert(overlay_count() == 1)
vim.cmd("QuickfixReviewHoverAll")
assert(overlay_count() == 0)
scroll_to(1)
assert(overlay_count() == 0)
vim.cmd("QuickfixReviewHoverAll")
assert(overlay_count() == 2)
vim.cmd("vnew")
assert(overlay_count() == 0)
vim.cmd("close")
scroll_to(1)
assert(overlay_count() == 0)

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
