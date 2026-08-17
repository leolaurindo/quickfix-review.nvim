local M = {}
local lists = require("quickfix_notes.lists")
local annotations = require("quickfix_notes.annotations")
local location = require("quickfix_notes.location")

function M.entries(opts)
	opts = opts or {}
	local target = opts.source == "current" and lists.current()
	local value, err, resolved
	if target then
		value, err, resolved = lists.read({ kind = target.kind, id = target.id, winid = target.winid })
	else
		local owned = lists.find_owned(opts.scope_id)
		if not owned then
			return nil, "no QuickfixNotes list"
		end
		value, err, resolved = lists.read({ kind = "quickfix", id = owned.id })
	end
	if not value then
		return nil, err
	end
	local entries = {}
	for index, item in ipairs(value.items or {}) do
		local note = annotations.get(item)
		if note then
			local loc = location.canonical(note.location)
			entries[#entries + 1] = {
				list = resolved,
				index = index,
				id = note.id,
				note = note,
				path = loc.path,
				file = location.absolute(loc),
				line = loc.line,
				line_end = loc.line_end,
				text = annotations.composed_text(note),
				pos = { loc.line or 1, 0 },
			}
		end
	end
	return entries
end

function M.jump(entry)
	local value, err = lists.read(entry.list)
	if not value then
		return nil, err
	end
	local index
	for i, item in ipairs(value.items or {}) do
		if (annotations.get(item) or {}).id == entry.id then
			index = i
			break
		end
	end
	if not index then
		return nil, "note no longer exists"
	end
	local note = annotations.get(value.items[index])
	local path = location.absolute(note.location)
	if not path or vim.fn.filereadable(path) ~= 1 then
		return nil, "note path is not readable: " .. tostring(path)
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
	if note.location.line then
		pcall(vim.api.nvim_win_set_cursor, 0, { note.location.line, 0 })
	end
	return true
end

function M.pick(opts)
	local entries, err = M.entries(opts)
	if not entries then
		return nil, err
	end
	if #entries == 0 then
		return nil, "no annotated entries"
	end
	local function choose(entry)
		return M.jump(entry)
	end
	local ok, Snacks = pcall(require, "snacks")
	local function preview_with_note(ctx)
		local path = ctx.item.file
		if not path or vim.fn.filereadable(path) ~= 1 then
			return Snacks.picker.preview.file(ctx)
		end
		local source = vim.fn.readfile(path)
		local header = { "Quickfix Note", "-------------" }
		vim.list_extend(header, vim.split(ctx.item.text or "", "\n", { plain = true }))
		header[#header + 1] = ""
		vim.list_extend(header, source)
		ctx.preview:reset()
		ctx.preview:set_title(ctx.item.preview_title or vim.fn.fnamemodify(path, ":t"))
		ctx.preview:set_lines(header)
		ctx.preview:highlight({ file = path })
		local position = ctx.item.pos
		if position then
			ctx.item.pos = { position[1] + #header - #source, position[2] }
		end
		ctx.preview:loc()
		ctx.item.pos = position
	end
	if ok and Snacks.picker and Snacks.picker.pick then
		return Snacks.picker.pick({
			items = entries,
			format = function(item)
				return { { item.path .. ":" .. (item.line or ""), "String" }, { " - " .. item.text, "Normal" } }
			end,
			preview = preview_with_note,
			confirm = function(picker, item)
				picker:close()
				choose(item)
			end,
		})
	end
	local labels = vim.tbl_map(function(item)
		return item.path .. ":" .. (item.line or "") .. " - " .. item.text:gsub("\n", " ")
	end, entries)
	return vim.ui.select(labels, { prompt = "Quickfix note" }, function(_, index)
		if index then
			choose(entries[index])
		end
	end)
end

return M
