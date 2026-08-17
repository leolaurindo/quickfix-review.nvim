vim.env.XDG_DATA_HOME = "/tmp/quickfix-notes-test-data"
vim.env.XDG_STATE_HOME = "/tmp/quickfix-notes-test-state"
vim.opt.rtp:append(vim.fn.getcwd())

local notes = require("quickfix_notes")
local lists = require("quickfix_notes.lists")
local annotations = require("quickfix_notes.annotations")
local sender = require("quickfix_notes.sender")

notes.setup({ persist_review_list = false })
assert(vim.fn.exists(":QuickfixNotesAdd") == 2)
assert(vim.fn.exists(":QuickfixNotesExport") == 2)

local sent
sender.register({
	name = "test",
	send = function(payload)
		sent = payload
		return true
	end,
})
sender.set_default("test")

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
assert(notes.export_qf())
assert(sent == "- `README.md:3-4` - problem | Note: line one line two\n")

local active_id = vim.fn.getqflist({ id = 0 }).id
local owned, owned_target =
	lists.ensure_owned({ title = "Quickfix Notes" }, require("quickfix_notes.scope").id(notes.scope()))
assert(vim.fn.getqflist({ id = 0 }).id == active_id)
local owned_item = { filename = file, lnum = 10, valid = 1, text = "owned", user_data = {} }
local owned_location = { root = vim.fn.getcwd(), path = "README.md", line = 10, resolver = "normal" }
assert(annotations.set(owned_item, owned_location, "owned\nmultiline"))
owned.items[1] = owned_item
assert(lists.replace(owned_target, owned.items, 1, owned.changedtick))
assert(notes.export())
assert(sent == "- `README.md:10` - owned | Note: owned multiline\n")

local failing = {}
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

vim.fn.setloclist(0, {}, "r", { title = "local", items = { { filename = file, lnum = 7, text = "local problem" } } })
vim.cmd("lopen")
local local_entry = lists.current()
assert(local_entry.kind == "location")
local local_target = { kind = "location", id = local_entry.id, winid = local_entry.winid }
local local_location = assert(lists.location(local_entry, vim.fn.getcwd()))
assert(lists.update_item(local_target, local_entry.index, function(item)
	assert(annotations.set(item, local_location, "local note"))
	return true
end))
assert(notes.export({ list = local_target }))
assert(sent:find("local note", 1, true))

vim.fn.setqflist({}, "r", { title = "producer", items = { { filename = file, lnum = 9, text = "diagnostic" } } })
vim.cmd("copen")
local qf_ui = require("quickfix_notes.ui")
local qf_input = qf_ui.note_input
qf_ui.note_input = function(_, callback)
	callback({ text = "producer note" })
end
notes.add()
qf_ui.note_input = qf_input
local qf_ns = vim.api.nvim_get_namespaces().quickfix_notes
local qf_marks = vim.api.nvim_buf_get_extmarks(0, qf_ns, 0, -1, { details = true })
assert(#qf_marks == 1 and qf_marks[1][4].virt_text[1][1] == "  ▲")
local mirrored = assert(lists.find_owned(require("quickfix_notes.scope").id(notes.scope())))
local mirrored_note
for _, item in ipairs(mirrored.items) do
	local note = annotations.get(item)
	if note and note.text == "producer note" then
		mirrored_note = item
		assert(item.type == "")
	end
end
assert(mirrored_note)

local editor = require("quickfix_notes.ui")
local original_input = editor.note_input
editor.note_input = function(_, callback)
	callback({ text = "source note\nwith detail" })
end
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
notes.add()
editor.note_input = original_input
local restored_owned = assert(lists.find_owned(require("quickfix_notes.scope").id(notes.scope())))
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

vim.fn.setqflist({}, "r", { title = "files", items = { { filename = file } } })
local files_list = lists.current()
assert(notes.export({ list = { kind = "quickfix", id = files_list.id } }))
assert(sent == "- `README.md` - \n")

print("quickfix_notes tests passed")
