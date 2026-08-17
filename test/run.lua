vim.opt.rtp:append(vim.fn.getcwd())

local notes = require("quickfix_notes")
local list = require("reviewnotes.list")
local sender = require("reviewnotes.sender")
local store = require("reviewnotes.store")
local file = vim.fs.joinpath(vim.fn.getcwd(), "README.md")

notes.setup({})
assert(vim.fn.exists(":QuickfixNotesAdd") == 2)
assert(vim.fn.exists(":QuickfixNotesExportList") == 2)

local sent
sender.register({
	name = "test",
	send = function(markdown)
		sent = markdown
	end,
})
sender.set_default("test")
store.clear()

vim.fn.setqflist({}, "r", {
	title = "diagnostics",
	context = { source = "test" },
	items = { { filename = file, lnum = 3, text = "problem", user_data = { code = "X1" } } },
})
local quickfix_entry = list.current()
local quickfix_location = assert(list.location(quickfix_entry, store.scope().root))
store.add(quickfix_location, "explain this")
notes.export_qf()
assert(sent:find("problem", 1, true))
assert(sent:find("Note: explain this", 1, true))

vim.fn.setqflist({}, "r", {
	title = "other diagnostics",
	context = { source = "test" },
	items = { { filename = file, lnum = 3, text = "problem", user_data = { code = "X1" } } },
})
local other_location = assert(list.location(list.current(), store.scope().root))
assert(quickfix_location.item_key ~= other_location.item_key)
assert(not store.at(other_location))

vim.fn.setloclist(0, {}, "r", { title = "local", items = { { filename = file, lnum = 7, text = "local problem" } } })
vim.cmd("lopen")
local location_entry = list.current()
assert(location_entry.kind == "location")
store.add(assert(list.location(location_entry, store.scope().root)), "local note")
notes.export_qf()
assert(sent:find("local problem", 1, true))
assert(sent:find("Note: local note", 1, true))
