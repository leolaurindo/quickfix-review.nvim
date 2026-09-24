local annotations = require("quickfix_review.annotations")
local lists = require("quickfix_review.lists")
local location = require("quickfix_review.location")

local M = {}

local function flatten(text)
	return (text or ""):gsub("\n", " ")
end

local function read_payload(source)
	if type(source) == "table" then
		return source
	end
	if type(source) ~= "string" or source == "" then
		return nil, "findings source must be a table or JSON file path"
	end
	if vim.fn.filereadable(source) ~= 1 then
		return nil, "findings file is not readable: " .. source
	end
	local ok, contents = pcall(vim.fn.readfile, source)
	if not ok then
		return nil, "could not read findings file: " .. tostring(contents)
	end
	local decode_ok, decoded = pcall(vim.json.decode, table.concat(contents, "\n"))
	if not decode_ok then
		return nil, "invalid findings JSON: " .. tostring(decoded)
	end
	return decoded
end

local function inside_root(root, path)
	if path == root then
		return true
	end
	local prefix = root == "/" and "/" or root .. "/"
	return path:sub(1, #prefix) == prefix
end

local function resolves_inside(root, path)
	local real_root = vim.uv.fs_realpath(root) or root
	local probe, real = path
	repeat
		real = vim.uv.fs_realpath(probe)
		probe = vim.fs.dirname(probe)
	until real or probe == vim.fs.dirname(probe)
	return not real or inside_root(real_root, real)
end

local function finding_location(finding, root)
	local input = type(finding.location) == "table" and finding.location or finding
	local path = input.path or input.file or finding.path
	if type(path) ~= "string" or path == "" then
		return nil, "missing path"
	end
	local line = input.line or finding.line
	local line_end = input.line_end or finding.line_end
	if line ~= nil and (tonumber(line) == nil or tonumber(line) < 1 or tonumber(line) % 1 ~= 0) then
		return nil, "line must be a positive integer"
	end
	if line_end ~= nil
		and (tonumber(line_end) == nil or tonumber(line_end) < 1 or tonumber(line_end) % 1 ~= 0)
	then
		return nil, "line_end must be a positive integer"
	end
	if line_end and line and tonumber(line_end) < tonumber(line) then
		return nil, "line_end must not precede line"
	end
	local value = location.canonical({
		root = root,
		path = path,
		line = line,
		line_end = line_end,
		side = input.side or finding.side,
		revision = input.revision or finding.revision,
		hash = input.hash or finding.hash,
		resolver = input.resolver or finding.resolver,
	})
	local absolute = value and location.absolute(value)
	if
		not value
		or not value.path
		or not absolute
		or not inside_root(root, absolute)
		or not resolves_inside(root, absolute)
	then
		return nil, "path is outside the current repository"
	end
	return value
end

local function finding_text(finding)
	if type(finding.text) ~= "string" or vim.trim(finding.text) == "" then
		return nil, "text must be a non-empty string"
	end
	return finding.text
end

local function finding_id(finding, value, text, opts, index)
	if opts.id_namespace then
		return opts.id_namespace .. ":" .. index, true
	end
	if finding.id ~= nil then
		if type(finding.id) ~= "string" or finding.id == "" then
			return nil, "id must be a non-empty string"
		end
		return finding.id, true
	end
	local encoded = vim.json.encode({ path = value.path, line = value.line, line_end = value.line_end, text = text })
	local ok, digest = pcall(vim.fn.sha256, encoded)
	return "import:" .. (ok and digest or encoded:gsub("[^%w]+", "-")), false
end

local function metadata(finding, opts, payload)
	local value = type(finding.metadata) == "table" and vim.deepcopy(finding.metadata) or {}
	for _, key in ipairs({ "severity", "confidence", "category", "evidence", "suggestion" }) do
		if finding[key] ~= nil then
			value[key] = vim.deepcopy(finding[key])
		end
	end
	value.origin = opts.origin or value.origin or finding.origin or payload.origin
	return next(value) and value or nil
end

local function prepare(payload, opts)
	local entries
	if type(payload) == "table" and payload.version == 1 and vim.islist(payload.findings) then
		entries = payload.findings
	elseif type(payload) == "table" and payload.version == 2 and vim.islist(payload.notes) then
		entries = payload.notes
	else
		return nil, "notes payload must contain version 2 and a notes array (or legacy version 1 findings)"
	end
	local encoded, encode_err = pcall(vim.json.encode, payload)
	if not encoded then
		return nil, "notes payload is not JSON-serializable: " .. tostring(encode_err)
	end
	local prepared, errors = {}, {}
	for index, finding in ipairs(entries) do
		if type(finding) ~= "table" then
			errors[#errors + 1] = ("finding %d: must be an object"):format(index)
		else
			local value, location_err = finding_location(finding, opts.root)
			local text, text_err = finding_text(finding)
			if not value then
				errors[#errors + 1] = ("finding %d: %s"):format(index, location_err)
			elseif not text then
				errors[#errors + 1] = ("finding %d: %s"):format(index, text_err)
			else
				local id, has_id = finding_id(finding, value, text, opts, index)
				if not id then
					errors[#errors + 1] = ("finding %d: %s"):format(index, has_id)
				else
					prepared[#prepared + 1] = {
						id = id,
						has_id = has_id,
						location = value,
						text = text,
						metadata = metadata(finding, opts, payload),
						col = tonumber(finding.col) or 0,
						end_col = tonumber(finding.end_col) or 0,
					}
				end
			end
		end
	end
	return prepared, errors
end

local function update_item(item, finding)
	local note, err = annotations.update(item, finding.text, finding.location, finding.metadata)
	if not note then
		return nil, err
	end
	item.filename = location.absolute(finding.location)
	item.lnum = finding.location.line
	item.end_lnum = finding.location.line_end
	item.col = finding.col
	item.end_col = finding.end_col
	item.valid = 1
	item.type = ""
	item.module = ""
	item.text = flatten(note.text)
	return note
end

function M.run(source, opts)
	opts = opts or {}
	if not opts.root or not opts.scope_id then
		return nil, "repository scope is required"
	end
	if opts.mode and opts.mode ~= "merge" then
		return nil, "unsupported import mode: " .. tostring(opts.mode)
	end
	local payload, payload_err = read_payload(source)
	if not payload then
		return nil, payload_err
	end
	local prepared, prepare_result = prepare(payload, opts)
	if not prepared then
		return nil, prepare_result
	end
	local result = { added = 0, updated = 0, unchanged = 0, skipped = #prepare_result, errors = prepare_result }
	if #prepared == 0 then
		return result
	end
	local owned, target = lists.ensure_owned({ title = opts.title or "Quickfix Review" }, opts.scope_id)
	local items = vim.deepcopy(owned.items or {})
	local by_id, by_location = {}, {}
	for index, item in ipairs(items) do
		local note = annotations.get(item)
		if note then
			local origin = annotations.origin(note) .. "\0"
			by_id[origin .. note.id] = index
			by_location[origin .. location.key(note.location)] = index
		end
	end
	for _, finding in ipairs(prepared) do
		local origin = annotations.origin(finding) .. "\0"
		local index = by_id[origin .. finding.id]
		if not index and not finding.has_id then
			index = by_location[origin .. location.key(finding.location)]
		end
		if index then
			local item = items[index]
			local old = annotations.get(item)
			local unchanged = old
				and old.text == finding.text
				and location.equal(old.location, finding.location)
				and vim.deep_equal(old.metadata, finding.metadata)
				and (tonumber(item.col) or 0) == finding.col
				and (tonumber(item.end_col) or 0) == finding.end_col
			if unchanged then
				result.unchanged = result.unchanged + 1
			else
				local note, update_err = update_item(item, finding)
				if not note then
					result.errors[#result.errors + 1] = "could not update " .. finding.id .. ": " .. update_err
					result.skipped = result.skipped + 1
				else
					result.updated = result.updated + 1
					by_id[origin .. note.id] = index
					by_location[origin .. location.key(note.location)] = index
				end
			end
		else
			local item = {
				filename = location.absolute(finding.location),
				lnum = finding.location.line,
				end_lnum = finding.location.line_end,
				col = finding.col,
				end_col = finding.end_col,
				valid = 1,
				type = "",
				text = flatten(finding.text),
				user_data = {},
			}
			local note, set_err = annotations.set(item, finding.location, finding.text, { id = finding.id }, finding.metadata)
			if not note then
				result.errors[#result.errors + 1] = "could not add " .. finding.id .. ": " .. set_err
				result.skipped = result.skipped + 1
			else
				items[#items + 1] = item
				by_id[origin .. note.id] = #items
				by_location[origin .. location.key(note.location)] = #items
				result.added = result.added + 1
			end
		end
	end
	if result.added > 0 or result.updated > 0 then
		local ok, replace_err = lists.replace(target, items, owned.idx, owned.changedtick)
		if not ok then
			return nil, replace_err
		end
	end
	return result
end

return M
