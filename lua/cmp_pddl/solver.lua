-- lua/cmp_pddl/solver.lua
-- Communicates with a planning-as-a-service server (solver.planning.domains:5001)
--
-- Confirmed API (solver.planning.domains:5001):
--   GET  /package                              -> { planner_id: {description,...}, ... }
--   POST /package/{planner}/solve              -> { result: "/check/{uuid}?external=True" }
--   GET  /check/{uuid}?external=True           -> { status: "ok"|"error", result: {...} }

local M = {}

-- ─── Config ───────────────────────────────────────────────────────────────────

local CONFIG_FILE = vim.fn.stdpath("data") .. "/cmp_pddl.json"

local function load_config()
	local f = io.open(CONFIG_FILE, "r")
	if not f then
		return { servers = {}, last_server = nil, last_planner = nil }
	end
	local raw = f:read("*a")
	f:close()
	local ok, cfg = pcall(vim.fn.json_decode, raw)
	if ok and type(cfg) == "table" then
		return cfg
	end
	return { servers = {}, last_server = nil, last_planner = nil }
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

-- ─── HTTP ─────────────────────────────────────────────────────────────────────

local function curl(args, on_done)
	local out = {}
	local all_args = { "curl", "-s", "--max-time", "30" }
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

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function decode(body)
	if not body or body == "" then
		return nil, "empty response"
	end
	-- Detect HTML (error page) before trying JSON decode
	if body:match("^%s*<!") or body:match("^%s*<html") then
		local title = body:match("<title>(.-)</title>") or "HTML error page"
		return nil, title
	end
	local ok, val = pcall(vim.fn.json_decode, body)
	if not ok then
		return nil, "json decode: " .. tostring(val)
	end
	return val, nil
end

-- Flatten lines — nvim_buf_set_lines rejects strings with embedded \n
local function flatten(lines)
	local flat = {}
	for _, l in ipairs(lines) do
		for _, part in ipairs(vim.split(tostring(l), "\n", { plain = true })) do
			table.insert(flat, part)
		end
	end
	return flat
end

-- ─── Result buffer ────────────────────────────────────────────────────────────

local function get_or_create_buf(title)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(b) == title then
			return b
		end
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, title)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.keymap.set("n", "q", ":bd<CR>", { buffer = buf, silent = true })
	return buf
end

local function set_buf_lines(buf, lines)
	local flat = flatten(lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, flat)
	vim.bo[buf].modifiable = false
end

local function ensure_visible(buf, height)
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(w) == buf then
			return
		end
	end
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_height(0, height or 15)
end

-- ─── Loading state ────────────────────────────────────────────────────────────

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function loading_lines(server, planner, attempt, max, message)
	local frame = spinner_frames[(attempt % #spinner_frames) + 1]
	local bar_width = 20
	local filled = math.floor((attempt / max) * bar_width)
	local bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)

	return {
		"",
		"  " .. frame .. "  " .. message,
		"",
		"  Server  : " .. server,
		"  Planner : " .. planner,
		"",
		"  Progress  [" .. bar .. "]  " .. attempt .. "/" .. max,
		"",
		"  Press q to cancel",
	}
end

-- ─── Plan renderer ────────────────────────────────────────────────────────────

local function render_result(data, server, planner, buf)
	local lines = {
		"  ============================================================",
		"  PDDL Plan Result",
		"  ============================================================",
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
			table.insert(lines, "  ✓  Goal already satisfied — empty plan")
		else
			table.insert(lines, string.format("  ✓  Plan found — %d step%s", #steps, #steps == 1 and "" or "s"))
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
		table.insert(lines, "  ✗  No solution  (status: " .. status .. ")")
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
	table.insert(lines, "  Press q to close")

	set_buf_lines(buf, lines)
	ensure_visible(buf, math.min(#lines + 2, 25))
end

-- ─── Polling ──────────────────────────────────────────────────────────────────

local function poll(poll_url, planner, server, buf, attempt, max)
	attempt = attempt or 1

	-- Update loading state in the buffer
	vim.schedule(function()
		set_buf_lines(buf, loading_lines(server, planner, attempt, max, "Solving... waiting for plan"))
		ensure_visible(buf, 12)
	end)

	if attempt > max then
		vim.schedule(function()
			set_buf_lines(buf, {
				"",
				"  ✗  Timed out after " .. max .. " attempts.",
				"  Try a faster planner or increase the timeout.",
				"",
			})
		end)
		return
	end

	vim.defer_fn(function()
		http_get(poll_url, function(body, err)
			vim.schedule(function()
				if err then
					set_buf_lines(buf, { "", "  ✗  Poll error: " .. err, "" })
					return
				end

				local data, derr = decode(body)
				if not data then
					set_buf_lines(buf, {
						"",
						"  ✗  Bad poll response: " .. (derr or "?"),
						"  URL: " .. poll_url,
						"",
					})
					return
				end

				local status = (data.status or ""):lower()
				if status == "ok" or status == "error" then
					render_result(data, server, planner, buf)
				else
					-- Still pending — recurse
					poll(poll_url, planner, server, buf, attempt + 1, max)
				end
			end)
		end)
	end, 2000)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function M.solve(server, planner, domain, problem)
	set_last(server, planner)

	local title = "PDDL-Plan[" .. planner .. "]"
	local buf = get_or_create_buf(title)
	local url = server .. "/package/" .. planner .. "/solve"
	local payload = vim.fn.json_encode({ domain = domain, problem = problem })

	-- Show loading state immediately
	set_buf_lines(buf, loading_lines(server, planner, 0, 30, "Submitting job..."))
	ensure_visible(buf, 12)

	http_post(url, payload, function(body, err)
		vim.schedule(function()
			if err then
				set_buf_lines(buf, { "", "  ✗  Submission failed: " .. err, "" })
				return
			end

			local data, derr = decode(body)
			if not data then
				set_buf_lines(buf, {
					"",
					"  ✗  Bad submission response: " .. (derr or "?"),
					"  URL: " .. url,
					"",
				})
				return
			end

			-- Server returns { "result": "/check/{uuid}?external=True" }
			local poll_path = type(data.result) == "string" and data.result or nil

			if poll_path then
				local poll_url = server .. poll_path
				set_buf_lines(buf, loading_lines(server, planner, 1, 30, "Job queued — polling for result..."))
				poll(poll_url, planner, server, buf, 1, 30)
			else
				-- Immediate result (some servers/planners return synchronously)
				render_result(data, server, planner, buf)
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
			local desc = type(meta) == "table" and (meta.description or meta.name or "") or ""
			table.insert(planners, { id = id, description = desc })
		end
		table.sort(planners, function(a, b)
			return a.id < b.id
		end)
		on_done(planners, nil)
	end)
end

return M
