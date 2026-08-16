local M = {}

local senders = {}
local default_name = "clipboard"

---Register a sender: { name, send(markdown, opts) }.
function M.register(s)
	if not s or not s.name or type(s.send) ~= "function" then
		return
	end
	senders[s.name] = s
end

---Set the default sender by name or module table.
function M.set_default(sender)
	if type(sender) == "string" then
		default_name = senders[sender] and sender or default_name
	elseif type(sender) == "table" and type(sender.send) == "function" and sender.name then
		default_name = sender.name
		senders[sender.name] = sender
	end
end

---The active sender's name.
function M.active()
	return default_name
end

---Send markdown through the default sender. Returns (ok, msg).
function M.send(markdown, opts)
	local s = senders[default_name]
	if not s then
		return false, "no sender configured"
	end
	local ok, result = pcall(s.send, markdown, opts or {})
	if not ok then
		return false, result
	end
	return true, result
end

function M.names()
	local out = {}
	for name in pairs(senders) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

return M
