local root = vim.fn.getcwd()
for env, sibling in pairs({
	QUICKFIX_ACTIONS_PATH = "quickfix-actions.nvim",
	QUICKFIX_EXPORT_PATH = "quickfix-export.nvim",
}) do
	local path = vim.env[env]
	vim.opt.rtp:prepend(path and path ~= "" and path or vim.fs.joinpath(root, "..", sibling))
end
vim.opt.rtp:prepend(root)

local review = require("quickfix_review")
local actions = require("quickfix_actions")
local annotations = require("quickfix_review.annotations")
local exporter = require("quickfix_review.export")
local generic = require("quickfix_export")
review.setup({ persist_review_list = false, agent = { response = { watch = false } } })
local sent
generic.register({ name = "plan-test", send = function(payload)
	sent = payload
	return true
end })

for _, case in ipairs({
	{ kind = "quickfix" },
	{ kind = "location" },
	{ kind = "quickfix", prefill = false },
	{ kind = "location", prefill = false },
}) do
	local kind = case.kind
	local current_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
	if current_info and current_info.quickfix == 1 then
		vim.cmd(current_info.loclist == 1 and "lclose" or "cclose")
	end
	review.setup({
		persist_review_list = false,
		agent = { response = { watch = false } },
		quickfix = { prefill = case.prefill },
	})
	vim.cmd("only")
	local owner = vim.api.nvim_get_current_win()
	local items = {
		{ filename = root .. "/README.md", lnum = 3, text = "producer message", user_data = { keep = "private" } },
		{ valid = 0, text = "context" },
		{ filename = root .. "/README.md", lnum = 4, text = "plain" },
	}
	if kind == "quickfix" then
		vim.fn.setqflist({}, " ", { items = items, title = "producer" })
		vim.cmd("copen")
	else
		vim.fn.setloclist(owner, {}, " ", { items = items, title = "producer" })
		vim.cmd("lopen")
	end
	local target = assert(actions.current())
	target = { kind = kind, id = target.id, winid = target.winid }
	local window = vim.api.nvim_get_current_win()
	review.add()
	assert(vim.bo.filetype == "text")
	local initial = case.prefill == false and "" or "producer message"
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { initial }))
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "review note", "detail" })
	vim.cmd("QuickfixReviewQuit")
	assert(vim.api.nvim_get_current_win() == window)
	assert(actions.current().id == target.id)
	local snapshot = assert(actions.read(target))
	assert(snapshot.items[1].text == "producer message")
	assert(snapshot.items[1].user_data.keep == "private")
	assert(annotations.get(snapshot.items[1]).text == "review note\ndetail")
	local marks = vim.api.nvim_buf_get_extmarks(
		0,
		vim.api.nvim_get_namespaces().quickfix_review,
		0,
		-1,
		{ details = true }
	)
	assert(#marks == 1 and marks[1][4].hl_mode == "combine")
	review.add()
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "review note", "detail" }))
	vim.cmd("QuickfixReviewQuit")

	snapshot = assert(actions.read(target))
	local metadata = { severity = "high", confidence = 0.9, evidence = { "proof" }, suggestion = "fix" }
	annotations.get(snapshot.items[1]).metadata = metadata
	assert(actions.replace(target, snapshot.items, snapshot.idx, snapshot.changedtick))
	local owned = assert(require("quickfix_review.lists").find_owned(require("quickfix_review.scope").id(review.scope())))
	local mirrored
	for _, item in ipairs(owned.items) do
		if annotations.get(item).id == annotations.get(snapshot.items[1]).id then
			mirrored = item
		end
	end
	assert(mirrored and mirrored.text == "review note detail" and mirrored.type == "")
	local before = assert(actions.read(target))
	local records = assert(exporter.records({ list = target }))
	assert(#records == 2 and records[2].index == 3 and records[2].text == "plain")
	assert(vim.deep_equal(records[1].metadata, metadata) and records[2].metadata == nil)
	assert(records[1].id == nil and records[1].user_data == nil and records[1].created_at == nil)
	assert(assert(generic.records({ list = target }))[1].metadata == nil)
	assert(vim.deep_equal(vim.json.decode(assert(exporter.format(records, "json")))[1].metadata, metadata))
	records[1].metadata.evidence[1] = "changed"
	assert(vim.deep_equal(assert(actions.read(target)), before))
	assert(review.export({ list = target, destination = "plan-test", format = function(values, opts)
		assert(opts.list.id == target.id)
		return values[1].metadata.severity .. ": " .. values[1].text
	end }))
	assert(sent == "high: review note\ndetail")
	assert(review.export({ list = target, destination = "plan-test", text = function(item, annotation)
		return annotation and item.text .. " / " .. annotation.text or item.text
	end }))
	assert(sent:find("producer message / review note detail", 1, true))
	assert(not review.export_and_clear({ list = target, destination = "plan-test", format = function()
		return nil, "template rejected"
	end }))
	assert(vim.deep_equal(assert(actions.read(target)), before))
end

-- Reject non-JSON-safe metadata even for custom formatters.
local original_records = generic.records
generic.records = function()
	return { { index = 1 } }, nil, { snapshot = { items = { { user_data = { quickfix_review = {
		version = 1, id = "bad", text = "note", metadata = { callback = function() end },
	} } } } } }
end
local records, err = exporter.records({ list = { kind = "quickfix", id = 1 } })
generic.records = original_records
assert(not records and err:find("invalid annotation metadata", 1, true))
print("quickfix_review export/UI tests passed")
