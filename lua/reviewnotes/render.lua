local markdown = require("quickfix_notes.formatters.markdown")

local M = {}

function M.note_line(note)
	return markdown
		.format({
			{
				path = note.path or note.file,
				line = note.line,
				line_end = note.line_end,
				text = note.text,
			},
		})
		:gsub("\n$", "")
end

function M.render(notes)
	local records = {}
	for _, note in ipairs(notes or {}) do
		records[#records + 1] = {
			path = note.path or note.file,
			line = note.line,
			line_end = note.line_end,
			text = note.text,
		}
	end
	return markdown.format(records)
end

function M.render_quickfix(records)
	return markdown.format(records or {})
end

return M
