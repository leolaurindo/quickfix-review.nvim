local M = {}

M.name = "sidekick"

---Send markdown into an attached sidekick AI CLI session.
function M.send(markdown, opts)
	opts = opts or {}
	local ok, cli = pcall(require, "sidekick.cli")
	if not ok or not cli then
		return false, "sidekick.nvim not installed"
	end
	cli.send({ msg = markdown, submit = opts.submit })
	return true
end

return M
