local M = {}

local config = require("reviewnotes.config")
local store = require("reviewnotes.store")
local notes_qf_id

function M.loc(n)
	local loc = n.file
	if n.line then
		local prefix = n.side == "old" and "~" or ""
		loc = string.format("%s:%s%d", n.file, prefix, n.line)
		if n.line_end and n.line_end ~= n.line then
			loc = loc .. "-" .. prefix .. n.line_end
		end
	end
	return loc
end

local function text_of(n)
	return (n.text or ""):gsub("\n", " "):match("^%s*(.-)%s*$") or ""
end

function M.jump(note)
	local abs = note.file
	if vim.fn.filereadable(abs) == 1 or abs:find("^%w+://") then
		vim.cmd.edit(vim.fn.fnameescape(abs))
	else
		local root = store.scope() and store.scope().root
		if root then
			vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. note.file))
		end
	end
	if note.line then
		pcall(vim.api.nvim_win_set_cursor, 0, { note.line, 0 })
	end
end

-- quickfix ------------------------------------------------------------

local function notes_qf(title)
	if notes_qf_id then
		local qf = vim.fn.getqflist({ id = notes_qf_id, title = 0 })
		if qf.id == notes_qf_id and qf.title == title then
			return notes_qf_id
		end
	end
	for nr = 1, vim.fn.getqflist({ nr = "$" }).nr do
		local qf = vim.fn.getqflist({ nr = nr, id = 0, title = 0 })
		if qf.title == title then
			notes_qf_id = qf.id
			return notes_qf_id
		end
	end
end

local function quickfix(notes)
	local title = config.get().quickfix_title
	local qf = {}
	for _, n in ipairs(notes) do
		qf[#qf + 1] = {
			filename = n.file,
			lnum = n.line or 1,
			-- Let quicker preserve the note text when adding source context.
			type = "N",
			text = text_of(n),
			user_data = n,
		}
	end
	local id = notes_qf(title)
	if id then
		vim.fn.setqflist({}, "r", { id = id, title = title, items = qf })
	else
		vim.fn.setqflist({}, " ", { nr = "$", title = title, items = qf })
		id = vim.fn.getqflist({ id = 0 }).id
		notes_qf_id = id
	end
	local nr = vim.fn.getqflist({ id = id, nr = 0 }).nr
	vim.cmd("silent " .. nr .. "chistory")
	vim.cmd("copen")
end

-- snacks --------------------------------------------------------------

local function snacks(notes)
	local ok, picker = pcall(require, "snacks.picker")
	if not ok or not picker.pick then
		return nil
	end
	local preview = require("snacks.picker.preview")
	local truncate = require("snacks.picker.util").truncate
	local list = {}
	for _, n in ipairs(notes) do
		list[#list + 1] = {
			file = n.file,
			pos = { n.line or 1, 0 },
			text = text_of(n),
			note = n,
		}
	end
	picker.pick({
		title = "Review Notes",
		items = list,
		preview = function(ctx)
			local file = ctx.item.file
			if vim.fn.filereadable(file) ~= 1 then
				local scope = store.scope()
				file = scope and scope.root and scope.root .. "/" .. file or file
			end
			if vim.fn.filereadable(file) ~= 1 then
				return preview.file(ctx)
			end

			local info = vim.fn.getwininfo(ctx.win)[1]
			local width = math.max(1, vim.api.nvim_win_get_width(ctx.win) - (info and info.textoff or 0))
			local comment = truncate(text_of(ctx.item.note), width)
			local lines = { comment, ("─"):rep(width), "" }
			vim.list_extend(lines, vim.fn.readfile(file))

			ctx.preview:reset()
			ctx.preview:set_title(vim.fn.fnamemodify(file, ":t"))
			ctx.preview:set_lines(lines)
			ctx.preview:highlight({ file = file })
			vim.api.nvim_buf_add_highlight(ctx.buf, -1, "Normal", 0, 0, -1)
			vim.api.nvim_buf_add_highlight(ctx.buf, -1, "NonText", 1, 0, -1)
		end,
		format = function(item)
			return {
				{ M.loc(item.note), "SnacksPickerLabel" },
			}
		end,
		confirm = function(p, item)
			p:close()
			if item and item.note then
				M.jump(item.note)
			end
		end,
		actions = {
			delete_note = function(p)
				local selected = p:selected({ fallback = true })
				local deleted = {}
				for _, item in ipairs(selected) do
					if item.note then
						store.delete(item.note.id)
						deleted[item.note.id] = true
					end
				end
				p.opts.items = vim.tbl_filter(function(item)
					return item.note and not deleted[item.note.id]
				end, p.opts.items)
				require("reviewnotes.marks").refresh()
				p:refresh()
			end,
		},
		win = {
			input = { keys = { x = { "delete_note", mode = { "n" } } } },
			list = { keys = { x = "delete_note" } },
		},
	})
	return true
end

-- telescope -----------------------------------------------------------

local function telescope(notes)
	local ok, pickers = pcall(require, "telescope.pickers")
	local ok2, finders = pcall(require, "telescope.finders")
	local ok3, sorters = pcall(require, "telescope.sorters")
	local ok4, actions = pcall(require, "telescope.actions")
	local ok5, state = pcall(require, "telescope.actions.state")
	if not (ok and ok2 and ok3 and ok4 and ok5) then
		return nil
	end

	local list = {}
	for _, n in ipairs(notes) do
		list[#list + 1] = {
			file = n.file,
			pos = { n.line or 1, 0 },
			text = M.loc(n) .. "  " .. text_of(n),
			note = n,
		}
	end
	pickers
		.new({}, {
			prompt_title = "Review Notes",
			finder = finders.new_table({
				results = list,
				entry_maker = function(item)
					return {
						value = item,
						display = item.text,
						ordinal = item.text,
						filename = item.file,
						lnum = item.pos[1],
					}
				end,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function()
				actions.select_default:replace(function(pb)
					local entry = state.get_selected_entry()
					actions.close(pb)
					if entry and entry.value and entry.value.note then
						M.jump(entry.value.note)
					end
				end)
				return true
			end,
		})
		:find()
	return true
end

-- mini.picker ---------------------------------------------------------

local function mini(notes)
	local ok, minipick = pcall(require, "mini.pick")
	if not ok or not minipick.start then
		return nil
	end
	local list = {}
	for _, n in ipairs(notes) do
		list[#list + 1] = {
			file = n.file,
			pos = { n.line or 1, 0 },
			text = M.loc(n) .. "  " .. text_of(n),
			note = n,
		}
	end
	minipick.start({
		source = {
			name = "Review Notes",
			items = list,
			choose = function(_, item)
				if item and item.note then
					M.jump(item.note)
				end
			end,
		},
	})
	return true
end

---Open the notes list with the configured backend. Falls back through the list.
---@param backend "quickfix"|"snacks"|"telescope"|"mini"
function M.open(notes, backend)
	notes = notes or store.all()
	if #notes == 0 then
		vim.notify("reviewnotes: no notes", vim.log.levels.INFO)
		return
	end

	if backend == "quickfix" then
		quickfix(notes)
		return
	end

	local handler = backend == "snacks" and snacks or backend == "telescope" and telescope or backend == "mini" and mini
	if handler then
		local ok = handler(notes)
		if ok then
			return
		end
		vim.notify("reviewnotes: " .. backend .. " not available, falling back", vim.log.levels.WARN)
	end

	local chain = { "snacks", "telescope", "mini", "quickfix" }
	for _, b in ipairs(chain) do
		if b ~= backend then
			local fn = b == "snacks" and snacks or b == "telescope" and telescope or b == "mini" and mini or quickfix
			if fn(notes) then
				return
			end
		end
	end
	quickfix(notes)
end

return M
