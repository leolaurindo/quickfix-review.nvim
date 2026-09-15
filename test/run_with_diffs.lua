local project = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
	QUICKFIX_DIFFS_PATH = "quickfix-diffs.nvim",
}) do
	local path = vim.env[env]
	vim.opt.rtp:prepend(path and path ~= "" and path or vim.fs.joinpath(project, "..", sibling))
end
vim.opt.rtp:prepend(project)

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function git(...)
	local args = { "git", "-C", root }
	vim.list_extend(args, { ... })
	local result = vim.system(args, { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end
local file = root .. "/example.txt"
vim.fn.writefile({ "one", "two", "three", "four", "five" }, file)
git("init", "-q")
git("add", "example.txt")
git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "base")
local base = git("rev-parse", "HEAD")
vim.cmd.cd(root)
vim.cmd.edit(file)

local review = require("quickfix_review")
assert(package.loaded.quickfix_diffs == nil)
local lists = require("quickfix_review.lists")
local annotations = require("quickfix_review.annotations")
local exporter = require("quickfix_review.export")
local ui = require("quickfix_review.ui")
local marks = require("quickfix_review.marks")
review.setup({
	persist_review_list = false,
	agent = { response = { watch = false } },
	quickfix = { prefill = false },
})
local diffs = require("quickfix_diffs")
diffs.setup({ open = true })

local function annotate(opts, text)
	local items, err, target = diffs.open(opts)
	assert(items and #items > 0, err)
	local before = assert(lists.read(target))
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	local window = vim.api.nvim_get_current_win()
	local input = ui.note_input
	ui.note_input = function(_, callback)
		callback({ text = text })
	end
	review.add()
	ui.note_input = input
	assert(vim.api.nvim_get_current_win() == window)
	assert(vim.fn.getqflist({ id = 0 }).id == target.id)
	local after = assert(lists.read(target))
	assert(after.items[1].text == before.items[1].text)
	assert(vim.deep_equal(after.items[1].user_data.quickfix_diffs, before.items[1].user_data.quickfix_diffs))
	local annotation = assert(annotations.get(after.items[1]))
	return annotation, target, after
end

vim.fn.writefile({ "one", "TWO", "THREE", "four", "five" }, file)
local worktree, producer = annotate({ mode = "unstaged" }, "worktree note")
assert(worktree.location.line == 2 and worktree.location.line_end == 3)
assert(worktree.location.revision == nil and worktree.location.hash == nil)
local ns = vim.api.nvim_get_namespaces().quickfix_review
vim.cmd("wincmd p")
marks.render()
assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1)

local owned = assert(lists.find_owned())
local saved = assert(lists.read({ kind = "quickfix", id = owned.id }))
review.open_list()
local _, _, next_target = diffs.open({ mode = "unstaged" })
assert(next_target.id ~= owned.id and next_target.id ~= producer.id)
assert(vim.deep_equal(assert(lists.read({ kind = "quickfix", id = owned.id })).items, saved.items))
assert(annotations.get(assert(lists.read(producer)).items[1]).id == worktree.id)
assert(not annotations.get(assert(lists.read(next_target)).items[1]))

git("add", "example.txt")
local staged, staged_target = annotate({ mode = "staged" }, "index note")
assert(staged.location.revision == "index" and staged.location.hash == git("rev-parse", ":example.txt"))
assert(staged.location.side == "new" and staged.location.line_end == 3)
local staged_records = assert(exporter.records({ list = staged_target }))
assert(staged_records[1].labels == nil and staged_records[1].stale == nil)
local before_file_note = assert(lists.read(staged_target))
local file_input = ui.note_input
ui.note_input = function(_, callback) callback({ text = "staged file note" }) end
vim.cmd("QuickfixReviewAddFile")
ui.note_input = file_input
assert(vim.deep_equal(assert(lists.read(staged_target)).items, before_file_note.items))
local file_entry
for _, candidate in ipairs(assert(require("quickfix_review.picker").entries())) do
	if candidate.text == "staged file note" then file_entry = candidate end
end
assert(file_entry and not file_entry.line and file_entry.note.location.revision == "index")
git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "change")
local head = git("rev-parse", "HEAD")
local historical, historical_target = annotate({ spec = base .. "...HEAD" }, "historical note")
assert(historical.location.revision == head and historical.location.line == 2)
local records = assert(exporter.records({ list = historical_target }))
assert(records[1].revision == head and records[1].side == "new" and records[1].hash == historical.location.hash)
assert(records[1].labels == nil)
assert(assert(exporter.format(records, "markdown")) == "- `example.txt:2-3` - historical note\n")
vim.fn.writefile({ "different", "contents" }, file)
records = assert(exporter.records({ list = historical_target }))
assert(records[1].labels[1] == "commit " .. head:sub(1, 8) and not records[1].stale)
assert(assert(exporter.records({ list = staged_target })) [1].labels[1]:find("index ", 1, true))
local worktree_records = assert(exporter.records({ list = producer }))
assert(worktree_records[1].stale and worktree_records[1].labels[1] == "location may be stale")
vim.fn.writefile({ "one", "TWO", "THREE", "four", "five" }, file)
assert(not assert(exporter.records({ list = producer }))[1].stale)

-- Index/commit notes must not add triangles to the working-tree source buffer.
vim.cmd("wincmd p")
marks.render()
assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1)

vim.fn.delete(file)
local deletion, deletion_target = annotate({ mode = "head" }, "restore this file")
assert(deletion.location.side == "old" and deletion.location.revision == head)
assert(deletion.location.line == 1 and deletion.location.line_end == 5)
records = assert(exporter.records({ list = deletion_target }))
assert(records[1].line == 1 and records[1].line_end == 5 and records[1].side == "old")
assert(records[1].labels[1] == "deleted lines")
assert(assert(exporter.format(records, "markdown")):find("[deleted lines; commit " .. head:sub(1, 8) .. "]", 1, true))
assert(assert(exporter.records({ list = deletion_target, warn_stale = false }))[1].labels[1] == "deleted lines")
local indexed_deletion = annotate({ mode = "unstaged" }, "index deletion")
assert(indexed_deletion.location.revision == "index" and indexed_deletion.location.line == 1)

local owned_after_deletion = assert(lists.find_owned())
for _, item in ipairs(owned_after_deletion.items) do
	if annotations.get(item).id == indexed_deletion.id then
		assert(item.lnum == 1 and item.end_lnum == 5)
	end
end

local full, full_target, full_snapshot = annotate({ mode = "head", full_diff = true }, "full-file note")
assert(full.location.line == nil and full.location.line_end == nil and full.location.side == "old")
local mirrored = assert(lists.find_owned())
local found
for _, item in ipairs(mirrored.items) do
	if annotations.get(item).id == full.id then
		found = true
		assert(item.lnum == 0 and (item.end_lnum or 0) == 0, vim.inspect(item))
	end
end
assert(found)
local captured
require("quickfix_export").register({ name = "diff-test", send = function(payload)
	captured = payload
	return true
end })
assert(review.export({ list = full_target, destination = "diff-test",
	text = function(item, annotation)
		return annotation.text .. "\n\n" .. item.text
	end,
	format = function(values)
		assert(values[1].line == nil and values[1].revision == head)
		return values[1].text
	end,
}))
assert(captured == "full-file note\n\n" .. full_snapshot.items[1].text)
assert(captured:find("-one", 1, true))

local value, err = lists.location({ item = { filename = file, lnum = 1,
	user_data = { quickfix_diffs = { version = 99 } },
} })
assert(not value and err:find("unsupported", 1, true))
local normal = assert(lists.location({ item = { filename = file, lnum = 4 } }, root))
assert(normal.line == 4 and normal.revision == nil)
local data = vim.deepcopy(full_snapshot.items[1].user_data.quickfix_diffs)
data.full_diff, data.deleted = false, false
data.old, data.new = { start = 1, count = 1 }, { start = 0, count = 1 }
value, err = require("quickfix_review.integrations.diffs").location(data)
assert(not value and err:find("range", 1, true))
data.full_diff, data.root = true, project
vim.fn.setqflist({}, " ", { items = { { filename = file, lnum = 1, text = "other repo",
	user_data = { quickfix_diffs = data },
} } })
local called = false
local input = ui.note_input
ui.note_input = function() called = true end
review.add()
ui.note_input = input
assert(not called and not annotations.get(vim.fn.getqflist()[1]))
print("quickfix_review with diffs tests passed")
