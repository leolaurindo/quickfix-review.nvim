local M = { destinations = {}, default = "clipboard" }

function M.register(destination)
	if destination and destination.name and type(destination.send) == "function" then
		M.destinations[destination.name] = destination
	end
end

function M.set_default(value)
	if type(value) == "string" and M.destinations[value] then
		M.default = value
	elseif type(value) == "table" then
		M.register(value)
		M.default = value.name
	end
end

function M.active()
	return M.default
end

function M.send(payload, opts, destination)
	local item = M.destinations[destination or M.default]
	if not item then
		return false, "no destination configured"
	end
	local ok, result, err = pcall(item.send, payload, opts or {})
	if not ok then
		return false, result
	end
	if result == false then
		return false, err or "destination failed"
	end
	return true, result
end

return M
