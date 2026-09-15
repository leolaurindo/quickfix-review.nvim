local M = {}

local function git(args, cwd)
	local result = vim.system(args, { cwd = cwd, text = true }):wait()
	return result.code == 0 and vim.trim(result.stdout or "") or nil
end

function M.resolve(policy, custom, cwd)
	cwd = cwd or vim.fn.getcwd()
	local root = git({ "git", "rev-parse", "--show-toplevel" }, cwd) or vim.fs.normalize(cwd)
	if policy == "repository" then
		return { policy = "repository", root = root }
	end
	if policy == "custom" and type(custom) == "table" then
		return { policy = "custom", root = vim.fs.normalize(custom.root or root), branch = custom.branch }
	end
	local branch = git({ "git", "symbolic-ref", "--short", "HEAD" }, root)
	if not branch then
		branch = git({ "git", "rev-parse", "--short", "HEAD" }, root)
	end
	return { policy = "branch", root = root, branch = branch }
end

function M.id(value)
	return table.concat({ value.policy or "repository", value.root or "", value.branch or "<detached>" }, "\0")
end

return M
