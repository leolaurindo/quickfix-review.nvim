local ok, sender = pcall(require, "quickfix_export.sender")
if not ok then
	error("Quickfix Review requires quickfix-export.nvim for destinations: " .. tostring(sender), 0)
end

return {
	destinations = sender.destinations,
	register = function(destination)
		return sender.register(destination)
	end,
	set_default = function(destination)
		return sender.set_default(destination)
	end,
	active = function()
		return sender.active()
	end,
	send = function(payload, opts, destination)
		return sender.send(payload, opts, destination)
	end,
}
