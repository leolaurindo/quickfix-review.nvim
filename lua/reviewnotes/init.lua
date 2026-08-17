local notes = require("quickfix_notes")

notes.note = notes.add
notes.note_range = notes.note_range
notes.list = notes.open_list
notes.list_quickfix = notes.open_list
notes.export_qf = notes.export
notes.clear = notes.clear_annotations

local function alias(name, fn, opts)
	vim.api.nvim_create_user_command(name, fn, vim.tbl_extend("force", { force = true }, opts or {}))
end

local function install_compat_commands()
	alias("ReviewNote", function(o)
		if o.range > 0 then
			notes.note_range(o.line1, o.line2)
		else
			notes.add()
		end
	end, { range = true })
	alias("ReviewQfNote", notes.add)
	alias("ReviewQfEdit", notes.edit)
	alias("ReviewExport", notes.export)
	alias("ReviewExportQf", notes.export)
	alias("ReviewExportList", notes.export)
	alias("ReviewExportAndClear", notes.export_and_clear)
	alias("ReviewClear", notes.clear_annotations)
	alias("ReviewList", notes.open_list)
	alias("ReviewQf", notes.open_list)
	alias("ReviewHide", require("quickfix_notes.marks").hide)
	alias("ReviewShow", require("quickfix_notes.marks").show)
	alias("ReviewMode", require("quickfix_notes.marks").toggle)
	alias("ReviewNext", notes.next)
	alias("ReviewPrev", notes.prev)
	alias("ReviewSend", notes.send)
end

local setup = notes.setup
function notes.setup(opts)
	local result = setup(opts)
	install_compat_commands()
	return result
end

return notes
