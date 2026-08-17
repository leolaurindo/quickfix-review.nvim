return {
	name = "clipboard",
	send = function(payload)
		vim.fn.setreg("+", payload)
		return true
	end,
}
