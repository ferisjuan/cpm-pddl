-- lua/cmp_pddl/solver.lua
-- Communicates with a planning-as-a-service server (solver.planning.domains:5001)
--
-- API flow:
--   GET  /package                        -> { planner_id: {description, ...}, ... }
--   POST /package/{planner}/solve        -> { result: job_id }
--   GET  /package/{planner}/result/{id}  -> { status: "PENDING"|"ok"|"error", result: {...} }

local M = {}

-- ─── Config storage ───────────────────────────────────────────────────────────

local CONFIG_FILE = vim.fn.stdpath("data") .. "/cmp_pddl.json"

local function load_config()
	local f = io.open(CONFIG_FILE, "r")
	if not f then
		return { servers = {}, last_server = nil, last_planner = nil }
	end
	local raw = f:read("*a")
	f:close()
	local ok, cfg = pcall(vim.fn.json_decode, raw)
	return (ok and type(cfg) == "table") and cfg or { servers = {}, last_server = nil, last_planner = nil }
end

local function save_config(cfg)
	local f = io.open(CONFIG_FILE, "w")
	if not f then
		return
	end
	f:write(vim.fn.json_encode(cfg))
	f:close()
end

function M.add_server(url, name)
	local cfg = load_config()
	for _, s in ipairs(cfg.servers) do
		if s.url == url then
			s.name = name
			save_config(cfg)
			return
		end
	end
	table.insert(cfg.servers, { url = url, name = name })
	save_config(cfg)
end

function M.get_servers()
	return load_config().servers
end

function M.get_last()
	local cfg = load_config()
	return cfg.last_server, cfg.last_planner
end

local function set_last(server, planner)
	local cfg = load_config()
	cfg.last_server = server
	cfg.last_planner = planner
	save_config(cfg)
end

-- ─── HTTP via curl ────────────────────────────────────────────────────────────

local function curl(args, on_done)
	local out = {}
	local all_args = { "curl", "-s", "--max-time", "15" }
	for _, a in ipairs(args) do
		table.insert(all_args, a)
	end
	vim.fn.jobstart(all_args, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			vim.list_extend(out, data)
		end,
		on_exit = function(_, code)
			local body = table.concat(out, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
			if code ~= 0 then
				on_done(nil, "curl exit " .. code)
			else
				on_done(body, nil)
			end
		end,
	})
end

local function http_get(url, on_done)
	curl({ url }, on_done)
end

local function http_post(url, payload, on_done)
	curl({ "-X", "POST", "-H", "Content-Type: application/json", "-d", payload, url }, on_done)
end

-- ─── JSON decode ─────────────────────────────────────────────────────────────

local function decode(body)
	if not body or body == "" then
		return nil, "empty response"
	end
	local ok, val = pcall(vim.fn.json_decode, body)
	if not ok then
		return nil, "json decode error: " .. tostring(val)
	end
	return val, nil
end

-- ─── Result buffer ────────────────────────────────────────────────────────────

-- Flatten a list of strings — nvim_buf_set_lines cannot accept strings
-- that contain embedded newline characters.
local function flatten_lines(lines)
	local flat = {}
	for _, line in ipairs(lines) do
		local parts = vim.split(tostring(line), "\n", { plain = true })
		for _, part in ipairs(parts) do
			table.insert(flat, part)
		end
	end
	return flat
end

local function open_result_buf(lines, title)
	local existing = nil
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(b):match(vim.pesc(title)) then
			existing = b
			break
		end
	end

	local flat = flatten_lines(lines)
	local buf = existing or vim.api.nvim_create_buf(false, true)

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, flat)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_name(buf, title)

	local visible = false
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then
			visible = true
			break
		end
	end
	if not visible then
		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_win_set_height(0, math.min(#flat + 2, 20))
	end

	vim.keymap.set("n", "q", ":bd<CR>", { buffer = buf, silent = true, desc = "Close plan buffer" })

	return buf
end

-- ─── Plan renderer ────────────────────────────────────────────────────────────

local function render_result(data, server, planner)
	local lines = {
		"============================================================",
		"  PDDL Plan Result",
		"============================================================",
		"",
		"  Server  : " .. server,
		"  Planner : " .. planner,
		"",
	}

	local status = (data.status or "unknown"):lower()

	if status == "ok" then
		local result = data.result or {}
		local plan = result.plan or {}

		local steps = {}
		for _, step in ipairs(plan) do
			if type(step) == "string" then
				table.insert(steps, step)
			elseif type(step) == "table" then
				local name = step.name or step.action or vim.inspect(step)
				local time = step.time and string.format("[%6.3f] ", tonumber(step.time)) or ""
				table.insert(steps, time .. name)
			end
		end

		if #steps == 0 then
			table.insert(lines, "  Plan found — goal already satisfied (empty plan)")
		else
			table.insert(lines, string.format("  Plan found — %d step%s", #steps, #steps == 1 and "" or "s"))
			table.insert(lines, "")
			table.insert(lines, "  ----------------------------------------------------")
			for i, step in ipairs(steps) do
				table.insert(lines, string.format("  %3d.  %s", i, step))
			end
			table.insert(lines, "  ----------------------------------------------------")
		end

		if result.cost then
			table.insert(lines, "")
			table.insert(lines, "  Cost     : " .. tostring(result.cost))
		end
		if result.makespan then
			table.insert(lines, "  Makespan : " .. tostring(result.makespan))
		end

		if result.output and result.output ~= "" then
			table.insert(lines, "")
			table.insert(lines, "  -- Planner output ----------------------------------")
			for _, l in ipairs(vim.split(tostring(result.output), "\n", { plain = true })) do
				table.insert(lines, "  " .. l)
			end
		end
	else
		table.insert(lines, "  No solution found  (status: " .. status .. ")")
		table.insert(lines, "")

		local detail = nil
		if type(data.result) == "table" then
			detail = data.result.error or data.result.stderr or data.result.output
		end
		detail = detail or data.error

		if detail and detail ~= "" then
			table.insert(lines, "  -- Planner output ----------------------------------")
			for _, l in ipairs(vim.split(tostring(detail), "\n", { plain = true })) do
				table.insert(lines, "  " .. l)
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  Press q to close this buffer")

	open_result_buf(lines, "PDDL-Plan[" .. planner .. "]")
end

-- ─── Polling ──────────────────────────────────────────────────────────────────

local function poll(url, planner, server, interval, max_attempts, attempt)
	attempt = attempt or 1
	if attempt > max_attempts then
		vim.schedule(function()
			open_result_buf({
				"",
				"  Timed out waiting for planner result.",
				"  Try again or choose a faster planner.",
				"",
			}, "PDDL-Plan[" .. planner .. "]")
		end)
		return
	end

	vim.defer_fn(function()
		http_get(url, function(body, err)
			vim.schedule(function()
				if err then
					open_result_buf({ "", "  Poll error: " .. err, "" }, "PDDL-Plan[" .. planner .. "]")
					return
				end

				local data, derr = decode(body)
				if not data then
					open_result_buf({ "", "  Bad response: " .. (derr or "?"), "" }, "PDDL-Plan[" .. planner .. "]")
					return
				end

				local status = (data.status or ""):lower()

				if status == "pending" or status == "started" or status == "" then
					local wait_lines = flatten_lines({
						"",
						"  Solving ...  (attempt " .. attempt .. "/" .. max_attempts .. ")",
						"  Server  : " .. server,
						"  Planner : " .. planner,
						"",
					})
					for _, b in ipairs(vim.api.nvim_list_bufs()) do
						local bname = vim.api.nvim_buf_get_name(b)
						if bname:match("PDDL%-Plan%[" .. vim.pesc(planner) .. "%]") then
							vim.bo[b].modifiable = true
							vim.api.nvim_buf_set_lines(b, 0, -1, false, wait_lines)
							vim.bo[b].modifiable = false
						end
					end
					poll(url, planner, server, interval, max_attempts, attempt + 1)
				else
					render_result(data, server, planner)
				end
			end)
		end)
	end, interval)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function M.solve(server, planner, domain, problem)
	set_last(server, planner)

	local url = server .. "/package/" .. planner .. "/solve"
	local payload = vim.fn.json_encode({ domain = domain, problem = problem })

	open_result_buf({
		"",
		"  Submitting to " .. server,
		"  Planner : " .. planner,
		"",
		"  Waiting for job id ...",
		"",
	}, "PDDL-Plan[" .. planner .. "]")

	http_post(url, payload, function(body, err)
		vim.schedule(function()
			if err then
				open_result_buf({ "", "  Submission failed: " .. err, "" }, "PDDL-Plan[" .. planner .. "]")
				return
			end

			local data, derr = decode(body)
			if not data then
				open_result_buf({ "", "  Bad response: " .. (derr or body or "?"), "" }, "PDDL-Plan[" .. planner .. "]")
				return
			end

			-- The server returns {"result": "/check/{uuid}?external=True"}
			-- The result field is the full poll path — just prepend the server base URL.
			local poll_path = nil
			if type(data.result) == "string" then
				poll_path = data.result
			end

			if poll_path then
				local poll_url = server .. poll_path
				poll(poll_url, planner, server, 2000, 30, 1)
			else
				-- Some servers return the plan immediately
				render_result(data, server, planner)
			end
		end)
	end)
end

function M.fetch_planners(server, on_done)
	http_get(server .. "/package", function(body, err)
		if err then
			on_done(nil, err)
			return
		end
		local data, derr = decode(body)
		if not data then
			on_done(nil, derr)
			return
		end

		local planners = {}
		for id, meta in pairs(data) do
			local desc = ""
			if type(meta) == "table" then
				desc = meta.description or meta.name or ""
			end
			table.insert(planners, { id = id, description = desc })
		end
		table.sort(planners, function(a, b)
			return a.id < b.id
		end)
		on_done(planners, nil)
	end)
end

return M
