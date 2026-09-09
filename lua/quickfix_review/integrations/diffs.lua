local location = require("quickfix_review.location")
local M = {}

local function valid_range(value)
	return type(value) == "table"
		and type(value.start) == "number" and value.start >= 0 and value.start % 1 == 0
		and type(value.count) == "number" and value.count >= 0 and value.count % 1 == 0
		and (value.count == 0 or value.start > 0)
end

-- Consume the producer's data contract; neither plugin requires the other.
function M.location(data)
	if type(data) ~= "table" or data.version ~= 1 then
		return nil, "unsupported quickfix_diffs metadata version"
	end
	if type(data.root) ~= "string" or type(data.path) ~= "string" or data.path == "" then
		return nil, "diff item has no source path"
	end
	local side = data.deleted and "old" or "new"
	local range
	if not data.full_diff then
		if not valid_range(data.old) or not valid_range(data.new) then
			return nil, "diff item has no usable hunk range"
		end
		side = data.new.count > 0 and "new" or "old"
		range = data[side]
	end
	local endpoint = side == "old" and "base" or "target"
	local revision = data[endpoint .. "_revision"]
	if data[endpoint] == "index" then
		revision = "index"
	elseif data[endpoint] ~= "worktree" and not revision then
		return nil, "diff item has no resolved source revision"
	end
	return location.canonical({
		root = data.root,
		path = data.path,
		line = range and range.count > 0 and range.start or nil,
		line_end = range and range.count > 0 and range.start + range.count - 1 or nil,
		side = revision and side or nil,
		revision = revision,
		hash = revision and data[side .. "_blob"] or nil,
		fingerprint = data[side .. "_fingerprint"],
		deletion = data.deletion or nil,
	})
end

return M
