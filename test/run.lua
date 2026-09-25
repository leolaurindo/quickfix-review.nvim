vim.env.XDG_DATA_HOME = "/tmp/quickfix_review-test-data"
vim.env.XDG_STATE_HOME = "/tmp/quickfix_review-test-state"
local root = vim.fn.getcwd()

local function add_dependency(env, sibling)
	local path = vim.env[env]
	if not path or path == "" then
		path = vim.fs.joinpath(vim.fn.fnamemodify(root, ":h"), sibling)
	end
	vim.opt.rtp:prepend(path)
end

add_dependency("QUICKFIX_ACTIONS_PATH", "quickfix-actions.nvim")
add_dependency("QUICKFIX_EXPORT_PATH", "quickfix-export.nvim")
vim.opt.rtp:prepend(root)

local notes = require("quickfix_review")
local lists = require("quickfix_review.lists")
local annotations = require("quickfix_review.annotations")
local sender = require("quickfix_review.sender")
local resolver = require("quickfix_review.resolver")

local system = vim.system
local git_calls = 0
vim.system = function(args)
	git_calls = git_calls + 1
	local stdout = args[2] == "rev-parse" and args[3] == "--show-toplevel" and root .. "\n" or "main\n"
	return { wait = function()
		return { code = 0, stdout = stdout }
	end }
end
assert(require("quickfix_review.scope").resolve("repository", nil, root).root == root)
assert(git_calls == 1)
assert(require("quickfix_review.scope").resolve("branch", nil, root).branch == "main")
assert(git_calls == 3)
vim.system = system

notes.setup({ persist_review_list = false, agent = { response = { watch = false } } })
assert(vim.fn.exists(":QuickfixReviewAdd") == 2)
assert(vim.fn.exists(":QuickfixReviewImport") == 2)
assert(vim.fn.exists(":QuickfixReviewExport") == 2)
assert(vim.fn.exists(":QuickfixReviewExportUser") == 2)
assert(vim.fn.exists(":QuickfixReviewExportAgentNotes") == 2)
assert(vim.api.nvim_get_commands({}).QuickfixReviewExportAgent == nil)
assert(vim.fn.exists(":QuickfixReviewExportFromTemplate") == 2)
assert(vim.fn.exists(":QuickfixReviewSendAgentFromTemplate") == 2)
assert(vim.fn.exists(":QuickfixActionsDelete") == 2)
assert(vim.fn.exists(":QuickfixExport") == 2)

local sent
sender.register({
	name = "test",
	send = function(payload)
		sent = payload
		return true
	end,
})
sender.set_default("test")
local saved, save_err = notes.save_list("without-persist", { watch = false })
assert(not saved and save_err == "quickfix_persist is required")

local file = vim.fs.joinpath(vim.fn.getcwd(), "README.md")
vim.fn.setqflist({}, "r", {
	title = "diagnostics",
	context = { source = "test", keep = true },
	items = { { filename = file, lnum = 3, end_lnum = 4, col = 2, text = "problem", user_data = { code = "X1" } } },
})
local producer = lists.current()
local producer_target = { kind = producer.kind, id = producer.id }
local producer_location = assert(lists.location(producer, vim.fn.getcwd()))
assert(lists.update_item(producer_target, producer.index, function(item)
	assert(annotations.set(item, producer_location, "line one\nline two"))
	return true
end, nil))

local after = assert(lists.read(producer_target))
assert(after.items[1].user_data.code == "X1")
assert(annotations.get(after.items[1]).text == "line one\nline two")
assert(lists.item(producer_target, 1).user_data.code == "X1")
assert(notes.export_qf())
assert(sent == "- `README.md:3-4` - line one line two\n")

local active_id = vim.fn.getqflist({ id = 0 }).id
local owned, owned_target =
	lists.ensure_owned({ title = "QuickfixReview" }, require("quickfix_review.scope").id(notes.scope()))
assert(vim.fn.getqflist({ id = 0 }).id == active_id)
local owned_item = { filename = file, lnum = 10, valid = 1, text = "owned", user_data = {} }
local owned_location = { root = vim.fn.getcwd(), path = "README.md", line = 10, resolver = "normal" }
assert(annotations.set(owned_item, owned_location, "owned\nmultiline"))
owned.items[1] = owned_item
assert(lists.replace(owned_target, owned.items, 1, owned.changedtick))
assert(notes.export())
assert(sent == "- `README.md:10` - owned multiline\n")

sender.register({
	name = "failing",
	send = function()
		return false, "nope"
	end,
})
sender.set_default("failing")
assert(not notes.export_and_clear({ list = producer_target }))
assert(annotations.get(assert(lists.read(producer_target)).items[1]))
sender.set_default("test")
assert(notes.export_and_clear({ list = producer_target }))
assert(not annotations.get(assert(lists.read(producer_target)).items[1]))

vim.fn.setloclist(0, {}, "r", {
	title = "local",
	items = { { filename = file, lnum = 7, text = "local problem", user_data = { keep = true } } },
})
vim.cmd("lopen")
local local_entry = lists.current()
assert(local_entry.kind == "location")
local local_target = { kind = "location", id = local_entry.id, winid = local_entry.winid }
local local_location = assert(lists.location(local_entry, vim.fn.getcwd()))
assert(lists.update_item(local_target, local_entry.index, function(item)
	assert(annotations.set(item, local_location, "local note"))
	return true
end))
assert(assert(lists.read(local_target)).items[1].user_data.keep)
assert(notes.export({ list = local_target }))
assert(sent:find("local note", 1, true))

vim.fn.setqflist({}, "r", { title = "producer", items = { { filename = file, lnum = 9, text = "diagnostic" } } })
vim.cmd("copen")
	local qf_ui = require("quickfix_review.ui")
local qf_input = qf_ui.note_input
qf_ui.note_input = function(_, callback)
	callback({ text = "producer note" })
end
notes.add()
qf_ui.note_input = qf_input
	local qf_ns = vim.api.nvim_get_namespaces().quickfix_review
local qf_marks = vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true })
assert(#qf_marks == 1 and qf_marks[1][4].virt_text[1][1] == "  󰏫")
local qf_target = { kind = "quickfix", id = vim.fn.getqflist({ id = 0 }).id }
assert(notes.clear_annotations({ list = qf_target }))
assert(#vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true }) == 0)

qf_input = qf_ui.note_input
qf_ui.note_input = function(_, callback)
	callback({ text = "producer note" })
end
notes.add()
qf_ui.note_input = qf_input
assert(#vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true }) == 1)
assert(notes.export_and_clear({ list = qf_target }))
assert(#vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true }) == 0)

qf_input = qf_ui.note_input
qf_ui.note_input = function(_, callback)
	callback({ text = "producer note" })
end
notes.add()
qf_ui.note_input = qf_input
	local mirrored = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local mirrored_note
for _, item in ipairs(mirrored.items) do
	local note = annotations.get(item)
	if note and note.text == "producer note" then
		mirrored_note = item
		assert(item.type == "")
	end
end
assert(mirrored_note)

	local editor = require("quickfix_review.ui")
local original_input = editor.note_input
editor.note_input = function(_, callback)
	callback({ text = "source note\nwith detail" })
end
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
notes.add()
editor.note_input = original_input
	local restored_owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local found_source
for _, item in ipairs(restored_owned.items) do
	local note = annotations.get(item)
	if note and note.text == "source note\nwith detail" then
		found_source = item
		assert(item.filename == file)
		assert(item.lnum == 2 and item.valid == 1)
	end
end
assert(found_source)

local uri_buf = vim.api.nvim_create_buf(true, false)
local uri = "editor:///" .. file:sub(2)
vim.api.nvim_buf_set_name(uri_buf, uri)
vim.api.nvim_set_current_buf(uri_buf)
local uri_location = assert(resolver.location(uri_buf))
assert(uri_location.resolver == "generic")
assert(uri_location.path == "README.md" and not uri_location.line)
local uri_input = editor.note_input
editor.note_input = function(_, callback)
	callback({ text = "URI file note" })
end
notes.add()
editor.note_input = uri_input
	local uri_owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local uri_note
for _, item in ipairs(uri_owned.items) do
	local note = annotations.get(item)
	if note and note.text == "URI file note" then
		uri_note = item
		assert(item.filename == file and not note.location.line and not note.location.line_end)
	end
end
assert(uri_note)

local invalid_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(invalid_buf, "editor:///does/not/exist.lua")
assert(not resolver.location(invalid_buf))

local invalid_payload, invalid_payload_err = notes.import_findings({ version = 2, notes = { invalid = true } })
assert(not invalid_payload and invalid_payload_err:find("notes array", 1, true))
local unsupported_version_payload, unsupported_version_err = require("quickfix_review.import").validate({
	version = 1,
	findings = { { path = "README.md", text = "Unsupported payload" } },
})
assert(not unsupported_version_payload and unsupported_version_err:find("version 2 and a notes array", 1, true))
local agent_payload = {
	version = 2,
	origin = "agent",
	label = "discard this",
	notes = {
		{
			id = "agent-001",
			location = { path = "README.md", line = 12, label = "discard this too" },
			text = "The agent found a review concern.",
			label = "discard this as well",
		},
		{
			id = "agent-002",
			path = "README.md",
			text = "The finding applies to this file.",
		},
	},
}
local imported = assert(notes.import_findings(agent_payload))
assert(imported.added == 2 and imported.updated == 0 and #imported.errors == 0)
local imported_owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local imported_note
for _, item in ipairs(imported_owned.items) do
	local note = annotations.get(item)
	if note and note.id == "agent-001" then
		imported_note = note
		assert(vim.deep_equal(note.metadata, { origin = "agent" }))
		assert(item.filename == file and item.lnum == 12)
	end
end
assert(imported_note)
local imported_records = assert(require("quickfix_review.export").records({
	list = { kind = "quickfix", id = imported_owned.id },
	include_agent_notes = true,
}))
local exported_metadata
for _, record in ipairs(imported_records) do
	if record.text == imported_note.text then
		exported_metadata = record.metadata
		assert(record.id == nil and record.created_at == nil)
	end
end
assert(vim.deep_equal(exported_metadata, imported_note.metadata))
local agent_records = assert(require("quickfix_review.export").records({
	list = { kind = "quickfix", id = imported_owned.id },
	note_origin = "agent",
}))
assert(#agent_records == 2)
assert(agent_records[1].labels[#agent_records[1].labels] == "agent")
local user_records = assert(require("quickfix_review.export").records({
	list = { kind = "quickfix", id = imported_owned.id },
	note_origin = "user",
}))
for _, record in ipairs(user_records) do
	assert(not record.text:find("agent", 1, true))
end

local updated = assert(notes.import_findings({
	version = 2,
	origin = "agent",
	notes = {
		{ id = "agent-001", path = "README.md", line = 13, text = "The updated review concern." },
	},
}))
assert(updated.added == 0 and updated.updated == 1 and #updated.errors == 0)
local updated_owned = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
for _, item in ipairs(updated_owned.items) do
	local note = annotations.get(item)
	if note and note.id == "agent-001" then
		assert(note.text == "The updated review concern.")
		assert(note.metadata.origin == "agent")
		assert(item.lnum == 13)
	end
end

local import_path = vim.fn.tempname()
assert(vim.fn.writefile({ vim.json.encode({
	version = 2,
	notes = { { id = "agent-003", path = "README.md", line = 14, text = "Imported through the command." } },
}) }, import_path) == 0)
vim.api.nvim_cmd({ cmd = "QuickfixReviewImport", args = { import_path } }, {})
vim.fn.delete(import_path)
local command_import = assert(lists.find_owned(require("quickfix_review.scope").id(notes.scope())))
local command_note
for _, item in ipairs(command_import.items) do
	local note = annotations.get(item)
	if note and note.id == "agent-003" then
		command_note = note
	end
end
assert(command_note)
assert(command_note.metadata.origin == "agent")

local partially_imported = assert(notes.import_findings({
	version = 2,
	notes = {
		{ id = "outside", path = "../outside.lua", line = 1, text = "must be rejected" },
		{ id = "agent-004", path = "docs/integrations.md", line = 1, text = "The valid finding remains importable." },
	},
}))
assert(partially_imported.added == 1 and #partially_imported.errors == 1)

vim.fn.setqflist({}, "r", { title = "files", items = { { filename = file } } })
local files_list = lists.current()
assert(notes.export({ list = { kind = "quickfix", id = files_list.id } }))
assert(sent == "- `README.md` - \n")

local stale_id = files_list.id + 999
local stale, stale_err = lists.read({ kind = "quickfix", id = stale_id })
assert(not stale and stale_err:find("stale quickfix list id", 1, true))

print("quickfix_review tests passed")
