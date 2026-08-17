local M = {}

local config = require("reviewnotes.config")
local store = require("reviewnotes.store")
local notes_qf_id

local function location(note)
	local line = note.line and ":" .. note.line or ""
	if note.line_end and note.line_end ~= note.line then
		line = line .. "-" .. note.line_end
	end
	return note.file .. line
end

function M.jump(note)
	local file = note.file
	if vim.fn.filereadable(file) ~= 1 and not file:find("^%w+://") then
		local scope = store.scope()
		file = scope and scope.root and scope.root .. "/" .. file or file
	end
	vim.cmd.edit(vim.fn.fnameescape(file))
	if note.line then
		pcall(vim.api.nvim_win_set_cursor, 0, { note.line, 0 })
	end
end

local function notes_qf(title)
	if notes_qf_id then
		local qf = vim.fn.getqflist({ id = notes_qf_id, title = 1 })
		if qf.id == notes_qf_id and qf.title == title then
			return notes_qf_id
		end
	end
	for nr = 1, vim.fn.getqflist({ nr = "$" }).nr do
		local qf = vim.fn.getqflist({ nr = nr, id = 1, title = 1 })
		if qf.title == title then
			notes_qf_id = qf.id
			return notes_qf_id
		end
	end
end

function M.sync_quickfix(notes)
	local title = config.get().quickfix_title
	local active = vim.fn.getqflist({ id = 0, nr = 0 })
	local items = {}
	for _, note in ipairs(notes) do
		items[#items + 1] = {
			bufnr = 0,
			lnum = 0,
			valid = 0,
			type = "N",
			module = location(note),
			text = (note.text or ""):gsub("\n", " "),
			user_data = { quickfix_notes = note },
		}
	end

	local id = notes_qf(title)
	if id then
		vim.fn.setqflist({}, "r", { id = id, title = title, items = items })
	elseif #items > 0 then
		vim.fn.setqflist({}, " ", { nr = "$", title = title, items = items })
		id = vim.fn.getqflist({ id = 0 }).id
		notes_qf_id = id
		if active.id and active.id ~= id then
			vim.cmd("silent " .. active.nr .. "chistory")
		end
	end
	return id
end

function M.clear_quickfix()
	local id = notes_qf(config.get().quickfix_title)
	if id then
		vim.fn.setqflist({}, "r", { id = id, title = config.get().quickfix_title, items = {} })
	end
end

function M.open(notes)
	notes = notes or store.all()
	local id = M.sync_quickfix(notes)
	if not id then
		vim.notify("quickfix-notes: no notes", vim.log.levels.INFO)
		return
	end
	local nr = vim.fn.getqflist({ id = id, nr = 0 }).nr
	vim.cmd("silent " .. nr .. "chistory")
	vim.cmd("copen")
end

return M
