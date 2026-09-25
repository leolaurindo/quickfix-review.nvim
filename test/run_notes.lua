local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	vim.opt.rtp:prepend(vim.env[env] or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local file, other = root .. "/one.txt", root .. "/two.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
vim.fn.writefile({ "a", "b", "c", "d" }, other)
vim.cmd.cd(root)
vim.cmd.edit(file)

local review = require("quickfix_review")
local lists = require("quickfix_review.lists")
local annotations = require("quickfix_review.annotations")
local picker = require("quickfix_review.picker")
local exporter = require("quickfix_review.export")
local source = require("quickfix_review.source")
local mover = require("quickfix_review.reanchor")
local ui = require("quickfix_review.ui")
review.setup({
	persist_review_list = false,
	agent = { response = { watch = false } },
	notes_list = { width = 32, vertical_side = "right", linebreak = true, breakindent = true },
})
assert(vim.fn.exists(":QuickfixReviewAddFile") == 2)
assert(vim.fn.exists(":QuickfixReviewListFile") == 2)
assert(vim.fn.exists(":QuickfixReviewListVertical") == 2)
assert(vim.fn.exists(":QuickfixReviewListWrap") == 2)
assert(vim.fn.exists(":QuickfixReviewReanchor") == 2)
assert(vim.fn.exists(":QuickfixReviewSearch") == 2)

local function input(text)
	ui.note_input = function(_, callback) callback({ text = text }) end
end
local function entry(text)
	for _, item in ipairs(assert(picker.entries())) do
		if item.text == text then return item end
	end
	error("missing note " .. text)
end
local function choose(id)
	vim.ui.select = function(entries, opts, callback)
		assert(opts.prompt == "Re-anchor note here" and type(opts.format_item(entries[1])) == "string")
		for _, item in ipairs(entries) do
			if item.id == id then callback(item); return end
		end
		error("missing candidate")
	end
end

local function assert_vertical(win, side)
	local info = vim.fn.getwininfo(win)[1]
	for _, peer in ipairs(vim.api.nvim_list_wins()) do
		if peer ~= win then
			local peer_info = vim.fn.getwininfo(peer)[1]
			assert(info.winrow == peer_info.winrow)
			assert(vim.api.nvim_win_get_height(win) == vim.api.nvim_win_get_height(peer))
			assert(vim.api.nvim_win_get_width(win) < vim.api.nvim_win_get_width(peer))
			if side == "right" then
				assert(info.wincol > peer_info.wincol)
			else
				assert(info.wincol < peer_info.wincol)
			end
			return
		end
	end
	error("vertical Notes list must have an adjacent editor window")
end

input("line note")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
review.add()
local line_note = entry("line note")
assert(line_note.note.location.fingerprint:match("^sha256:"))
assert(lists.update_item(line_note.list, line_note.index, function(value)
	annotations.get(value).metadata = { severity = "high", evidence = "preserve this" }
	return true
end, line_note.id))
line_note = entry("line note")
input("file note")
vim.cmd("QuickfixReviewAddFile")
local file_note = entry("file note")
assert(not file_note.line and file_note.id ~= line_note.id)
assert(entry("line note").line == 4)
local records = assert(exporter.records({ list = file_note.list, root = root }))
assert(assert(exporter.format(records, "markdown")):find("- `one.txt` - file note", 1, true))
assert(not records[1].labels and not records[2].labels)

assert(review.open_list())
local list_win = vim.api.nvim_get_current_win()
assert(vim.bo.buftype == "quickfix" and vim.fn.getwininfo(list_win)[1].quickfix == 1)
for option, expected in pairs({ wrap = false, linebreak = true, breakindent = true }) do
	assert(vim.api.nvim_get_option_value(option, { win = list_win }) == expected)
end
local classic_items = vim.fn.getqflist({ id = 0, all = 1 }).items
assert(#classic_items == 2 and classic_items[1].text == "line note")
vim.cmd.QuickfixReviewListVertical()
list_win = vim.api.nvim_get_current_win()
assert(vim.bo.buftype == "quickfix" and vim.api.nvim_win_get_width(list_win) == 32)
assert(vim.fn.getwininfo(list_win)[1].quickfix == 1)
assert(vim.api.nvim_get_option_value("wrap", { win = list_win }) == true)
assert_vertical(list_win, "right")
assert(vim.o.splitright == false)
local vertical_items = vim.fn.getqflist({ id = 0, all = 1 }).items
assert(#vertical_items == 2 and vertical_items[1].text == "line note")
vim.o.splitright = true
vim.cmd("QuickfixReviewListVertical left")
list_win = vim.api.nvim_get_current_win()
assert_vertical(list_win, "left")
assert(vim.o.splitright == true)
vim.o.splitright = false
vim.cmd.cclose()
assert(review.open_list({ layout = "top" }))
list_win = vim.api.nvim_get_current_win()
local top_info = vim.fn.getwininfo(list_win)[1]
assert(vim.bo.buftype == "quickfix")
local has_editor_below = false
for _, peer in ipairs(vim.api.nvim_list_wins()) do
	if peer ~= list_win then
		local peer_info = vim.fn.getwininfo(peer)[1]
		assert(peer_info.wincol == top_info.wincol)
		assert(peer_info.winrow > top_info.winrow)
		has_editor_below = true
	end
end
assert(has_editor_below)
vim.cmd.cclose()
vim.cmd.QuickfixReviewListWrap()
list_win = vim.api.nvim_get_current_win()
assert(vim.fn.getwininfo(list_win)[1].quickfix == 1)
assert(vim.api.nvim_get_option_value("wrap", { win = list_win }) == true)
vim.cmd.cclose()
review.setup({
	persist_review_list = false,
	agent = { response = { watch = false } },
	notes_list = { width = 40, linebreak = true, breakindent = true },
})
assert(require("quickfix_review.config").get().notes_list.vertical_side == "right")
assert(review.open_list())
list_win = vim.api.nvim_get_current_win()
assert(vim.fn.getwininfo(list_win)[1].quickfix == 1)
for option, expected in pairs({ wrap = false, linebreak = true, breakindent = true }) do
	assert(vim.api.nvim_get_option_value(option, { win = list_win }) == expected)
end
vim.cmd.cclose()
assert(review.open_file_notes())
local file_view = vim.fn.getqflist({ id = 0, all = 1 })
assert(file_view.context.quickfix_review.role == "file_notes" and #file_view.items == 2)
for _, item in ipairs(file_view.items) do
	local note = assert(annotations.get(item))
	assert(note.location.path == "one.txt")
	local canonical
	for _, owned_item in ipairs(assert(lists.find_owned(require("quickfix_review.scope").id(review.scope()))).items) do
		local original = annotations.get(owned_item)
		if original and original.id == note.id then canonical = original end
	end
	assert(canonical and vim.deep_equal(note, canonical))
end
vim.cmd.cclose()

-- Unsaved edits, external writes, deletion, and restoring the original content.
vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
records = assert(exporter.records({ list = line_note.list, root = root }))
assert(records[1].stale and records[1].labels[1] == "location may be stale")
assert(not records[2].stale)
local suppressed = assert(exporter.records({ list = line_note.list, root = root, warn_stale = false }))
assert(suppressed[1].stale and suppressed[1].labels == nil)
vim.cmd("edit!")
assert(source.matches(line_note.note.location))
vim.fn.writefile({ "different" }, file)
assert(source.matches(line_note.note.location) == false)
vim.fn.delete(file)
assert(source.matches(line_note.note.location) == false)
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
assert(source.matches(line_note.note.location))

-- Editing the text is not a re-anchor, even if the source has changed.
vim.api.nvim_buf_set_lines(0, 0, 1, false, { "changed" })
local item = { user_data = { quickfix_review = vim.deepcopy(line_note.note) } }
assert(annotations.update(item, "edited"))
assert(annotations.get(item).location.fingerprint == line_note.note.location.fingerprint)
assert(source.matches(annotations.get(item).location) == false)

local sent, warnings = nil, 0
require("quickfix_export").register({ name = "notes-test", send = function(payload)
	sent = payload
	return true
end })
local notify = vim.notify
vim.notify = function(message, level)
	if level == vim.log.levels.WARN and message:find("stale", 1, true) then warnings = warnings + 1 end
end
assert(review.export({ list = line_note.list, destination = "notes-test" }))
assert(warnings == 1 and sent:find("[location may be stale]", 1, true))
review.setup({ persist_review_list = false, warn_stale = false, agent = { response = { watch = false } } })
assert(review.export({ list = line_note.list, destination = "notes-test" }))
assert(warnings == 1 and not sent:find("stale", 1, true))
vim.notify = notify
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
vim.cmd("edit!")

-- Range and file-level destinations are explicit; identity and text survive.
choose(line_note.id)
vim.cmd("2,3QuickfixReviewReanchor")
local moved = entry("line note")
assert(moved.id == line_note.id and moved.line == 2 and moved.line_end == 3)
assert(moved.note.created_at == line_note.note.created_at and source.matches(moved.note.location))
assert(vim.deep_equal(moved.note.metadata, line_note.note.metadata))
vim.cmd("QuickfixReviewReanchor!")
assert(not entry("line note").line)

for _, kind in ipairs({ "quickfix", "location" }) do
	vim.cmd.edit(file)
	local owner = vim.api.nvim_get_current_win()
	local items = { { filename = file, lnum = 5, text = "producer", user_data = { keep = true } } }
	if kind == "quickfix" then
		vim.fn.setqflist({}, " ", { items = items })
		vim.cmd("copen")
	else
		vim.fn.setloclist(owner, {}, " ", { items = items })
		vim.cmd("lopen")
	end
	local current = assert(lists.current())
	local target = { kind = kind, id = current.id, winid = current.winid }
	input(kind .. " note")
	review.add()
	local original = entry(kind .. " note")
	assert(vim.deep_equal(original.note.origin, target))
	local search_select = vim.ui.select
	local search_buffer = vim.api.nvim_get_current_buf()
	vim.ui.select = function(search_items, opts, callback)
		local label = opts.format_item(search_items[1])
		assert(label:find("producer", 1, true) and label:find(kind .. " note", 1, true))
		callback(search_items[1], 1)
	end
	assert(review.search({ list = target }))
	assert(vim.api.nvim_get_current_buf() == search_buffer and vim.api.nvim_win_get_cursor(0)[1] == 1)
	vim.ui.select = search_select
	local producer_before = assert(lists.read(target))
	input("another file note")
	review.add_file()
	assert(vim.deep_equal(assert(lists.read(target)).items, producer_before.items))
	assert(entry(kind .. " note").line == 5)
	vim.api.nvim_set_current_win(owner)
	vim.cmd.edit(other)
	vim.api.nvim_win_set_cursor(0, { 3, 0 })
	choose(original.id)
	review.reanchor()
	local relocated = entry(kind .. " note")
	assert(relocated.id == original.id and relocated.path == "two.txt" and relocated.line == 3)
	local producer_after = assert(lists.read(target))
	assert(producer_after.items[1].text == "producer" and producer_after.items[1].lnum == 5)
	assert(producer_after.items[1].user_data.keep)
	assert(vim.deep_equal(annotations.get(producer_after.items[1]), relocated.note))
	local copy = assert(lists.item(relocated.list, relocated.index))
	assert(vim.api.nvim_buf_get_name(copy.bufnr) == other and copy.lnum == 3)

	-- A cancelled picker, changed destination, or concurrent note edit must not move it.
	vim.ui.select = function(_, _, callback) callback(nil) end
	review.reanchor()
	assert(vim.deep_equal(entry(kind .. " note").note, relocated.note))
	local destination = source.capture({ root = root, path = "two.txt", line = 2 })
	vim.api.nvim_buf_set_lines(0, 0, 0, false, { "inserted" })
	local ok, err = mover.apply(relocated, destination)
	assert(not ok and err:find("destination changed", 1, true))
	vim.cmd("edit!")
	local changed = assert(lists.read(relocated.list))
	annotations.get(changed.items[relocated.index]).metadata = { severity = "high" }
	assert(lists.replace(relocated.list, changed.items, changed.idx, changed.changedtick))
	ok, err = mover.apply(relocated, destination)
	assert(not ok and err:find("note changed", 1, true))
	-- Restore the fixture, then verify rollback when the producer write fails.
	changed = assert(lists.read(relocated.list))
	changed.items[relocated.index].user_data.quickfix_review = vim.deepcopy(relocated.note)
	assert(lists.replace(relocated.list, changed.items, changed.idx, changed.changedtick))
	local replace = lists.replace
	lists.replace = function(t, ...)
		if t.id == target.id then return nil, "producer unavailable" end
		return replace(t, ...)
	end
	ok, err = mover.apply(relocated, destination)
	lists.replace = replace
	assert(not ok and err == "producer unavailable")
	assert(vim.deep_equal(entry(kind .. " note").note, relocated.note))

	-- An edit made in the managed list before picking is canonical, not a conflict.
	changed = assert(lists.read(relocated.list))
	annotations.get(changed.items[relocated.index]).metadata = { severity = "high" }
	assert(lists.replace(relocated.list, changed.items, changed.idx, changed.changedtick))
	choose(relocated.id)
	review.reanchor()
	relocated = entry(kind .. " note")
	assert(relocated.note.metadata.severity == "high")
	assert(vim.deep_equal(annotations.get(assert(lists.read(target)).items[1]), relocated.note))
	-- An original edited after the picker opened must not be overwritten.
	local pending = mover.capture(entry(kind .. " note"))
	local edited = assert(lists.read(target))
	annotations.get(edited.items[1]).text = "concurrent producer edit"
	assert(lists.replace(target, edited.items, edited.idx, edited.changedtick))
	ok, err = mover.apply(pending, destination)
	assert(not ok and err:find("note changed", 1, true))
	assert(entry(kind .. " note").line == relocated.line)

	-- A vanished original annotation does not prevent moving the managed note.
	local removed = assert(lists.read(target))
	annotations.remove(removed.items[1])
	assert(lists.replace(target, removed.items, removed.idx, removed.changedtick))
	assert(mover.apply(relocated, destination))
	assert(entry(kind .. " note").line == 2)
	assert(not annotations.get(assert(lists.read(target)).items[1]))
end

print("quickfix_review note lifecycle tests passed")
