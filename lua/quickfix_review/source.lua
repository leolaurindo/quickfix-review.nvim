local location = require("quickfix_review.location")
local M = {}

local function content(value)
	local path = location.absolute(value)
	if not path then
		return nil
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path and vim.bo[buf].modified then
			local separator = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), separator)
			return text .. (vim.bo[buf].endofline and separator or "")
		end
	end
	local ok, lines = pcall(vim.fn.readfile, path, "b")
	return ok and table.concat(lines, "\n") or nil
end

function M.fingerprint(value, algorithm)
	local text = content(value)
	if not text then
		return nil
	end
	if algorithm == "git" then
		local result = vim.system({ "git", "-C", value.root or vim.fn.getcwd(), "hash-object", "--stdin" },
			{ stdin = text, text = true }):wait()
		return result.code == 0 and ("git:" .. vim.trim(result.stdout)) or nil
	end
	return "sha256:" .. vim.fn.sha256(text)
end

function M.capture(value)
	local copy = vim.deepcopy(value)
	if not copy.fingerprint and not copy.revision and not copy.hash then
		copy.fingerprint = M.fingerprint(copy)
	end
	return copy
end

function M.matches(value, cache)
	if type(value.fingerprint) ~= "string" then
		return nil
	end
	local algorithm = value.fingerprint:match("^(%w+):")
	if algorithm ~= "git" and algorithm ~= "sha256" then
		return nil
	end
	local path = location.absolute(value)
	if not path then
		return nil
	end
	local key = algorithm .. ":" .. (value.root or vim.fn.getcwd()) .. ":" .. path
	local current = cache and cache[key]
	if current == nil then
		current = M.fingerprint(value, algorithm) or false
		if cache then
			cache[key] = current
		end
	end
	return current == value.fingerprint
end

function M.describe(value, cache)
	local matches = M.matches(value, cache)
	local historical = value.revision ~= nil or value.hash ~= nil
	local stale = not historical and value.line ~= nil and matches == false
	local labels = {}
	if value.deletion then
		labels[#labels + 1] = "deleted lines"
	end
	if value.deletion or (historical and matches ~= true) then
		if value.revision == "index" then
			labels[#labels + 1] = "index " .. (value.hash or "snapshot"):sub(1, 8)
		elseif value.revision or value.hash then
			labels[#labels + 1] = "commit " .. tostring(value.revision or value.hash):sub(1, 8)
		end
		if value.side == "old" and not value.deletion then
			labels[#labels + 1] = "old side"
		end
	end
	return labels, stale
end

return M
