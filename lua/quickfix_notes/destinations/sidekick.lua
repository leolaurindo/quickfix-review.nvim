return {
	name = "sidekick",
	send = function(payload, opts)
		local ok, cli = pcall(require, "sidekick.cli")
		if not ok or not cli then
			return false, "sidekick.nvim not installed"
		end
		local called, result = pcall(cli.send, { msg = payload, submit = opts and opts.submit })
		if not called then
			return false, result
		end
		if result == false then
			return false, "sidekick rejected the payload"
		end
		return true
	end,
}
