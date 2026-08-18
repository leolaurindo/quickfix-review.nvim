vim.env.XDG_DATA_HOME = "/tmp/quickreview-test-data"
vim.env.XDG_STATE_HOME = "/tmp/quickreview-test-state"
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

local notes = require("quickreview")
local lists = require("quickreview.lists")
local annotations = require("quickreview.annotations")
local sender = require("quickreview.sender")
local resolver = require("quickreview.resolver")

notes.setup({ persist_review_list = false })
assert(vim.fn.exists(":QuickReviewAdd") == 2)
assert(vim.fn.exists(":QuickReviewExport") == 2)
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
	lists.ensure_owned({ title = "QuickReview" }, require("quickreview.scope").id(notes.scope()))
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
	local qf_ui = require("quickreview.ui")
local qf_input = qf_ui.note_input
qf_ui.note_input = function(_, callback)
	callback({ text = "producer note" })
end
notes.add()
qf_ui.note_input = qf_input
	local qf_ns = vim.api.nvim_get_namespaces().quickreview
local qf_marks = vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true })
assert(#qf_marks == 1 and qf_marks[1][4].virt_text[1][1] == "  ▲")
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
	local mirrored = assert(lists.find_owned(require("quickreview.scope").id(notes.scope())))
local mirrored_note
for _, item in ipairs(mirrored.items) do
	local note = annotations.get(item)
	if note and note.text == "producer note" then
		mirrored_note = item
		assert(item.type == "")
	end
end
assert(mirrored_note)

	local editor = require("quickreview.ui")
local original_input = editor.note_input
editor.note_input = function(_, callback)
	callback({ text = "source note\nwith detail" })
end
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
notes.add()
editor.note_input = original_input
	local restored_owned = assert(lists.find_owned(require("quickreview.scope").id(notes.scope())))
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
	local uri_owned = assert(lists.find_owned(require("quickreview.scope").id(notes.scope())))
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

vim.fn.setqflist({}, "r", { title = "files", items = { { filename = file } } })
local files_list = lists.current()
assert(notes.export({ list = { kind = "quickfix", id = files_list.id } }))
assert(sent == "- `README.md` - \n")

local stale_id = files_list.id + 999
local stale, stale_err = lists.read({ kind = "quickfix", id = stale_id })
assert(not stale and stale_err:find("stale quickfix list id", 1, true))

print("quickreview tests passed")
