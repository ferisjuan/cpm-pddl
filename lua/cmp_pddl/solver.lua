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

-- Apply syntax highlighting to the result buffer
local function apply_highlights(buf)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		-- Define highlight groups
		vim.api.nvim_set_hl(0, "PddlTitle", { fg = "#7aa2f7", bold = true })
		vim.api.nvim_set_hl(0, "PddlSuccess", { fg = "#9ece6a", bold = true })
		vim.api.nvim_set_hl(0, "PddlError", { fg = "#f7768e", bold = true })
		vim.api.nvim_set_hl(0, "PddlStepNumber", { fg = "#bb9af7", bold = true })
		vim.api.nvim_set_hl(0, "PddlAction", { fg = "#7dcfff" })
		vim.api.nvim_set_hl(0, "PddlMeta", { fg = "#565f89", italic = true })
		vim.api.nvim_set_hl(0, "PddlBorder", { fg = "#3b4261" })
		vim.api.nvim_set_hl(0, "PddlArrow", { fg = "#ff9e64" })

		local ns = vim.api.nvim_create_namespace("pddl_plan")
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		for i, line in ipairs(lines) do
			local lnum = i - 1

			-- Title and borders
			if line:match("^╔") or line:match("^╚") or line:match("^║") then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlBorder", lnum, 0, -1)
			end

			-- Success/error messages
			if line:match("✓") then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlSuccess", lnum, 0, -1)
			elseif line:match("✗") then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlError", lnum, 0, -1)
			end

			-- Step numbers and arrows
			local step_start, step_end = line:find("%s+%d+%.%s+")
			if step_start then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlStepNumber", lnum, step_start - 1, step_end)
				-- Highlight the action after the number
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlAction", lnum, step_end, -1)
			end

			-- Arrows and flow indicators
			if line:match("↓") or line:match("→") or line:match("├") or line:match("└") then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlArrow", lnum, 0, -1)
			end

			-- Metadata (Server, Planner, Cost)
			if line:match("Server") or line:match("Planner") or line:match("Cost") or line:match("Steps") then
				local colon_pos = line:find(":")
				if colon_pos then
					vim.api.nvim_buf_add_highlight(buf, ns, "PddlMeta", lnum, 0, colon_pos)
				end
			end

			-- Headers
			if line:match("PDDL Plan") or line:match("═") then
				vim.api.nvim_buf_add_highlight(buf, ns, "PddlTitle", lnum, 0, -1)
			end
		end
	end)
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
	local bar_width = 30
	local filled = math.floor((attempt / max) * bar_width)
	local empty = bar_width - filled
	local bar = string.rep("█", filled) .. string.rep("░", empty)
	local percent = math.floor((attempt / max) * 100)

	return {
		"",
		"╔════════════════════════════════════════════════════════════════╗",
		"║                                                                ║",
		"║  " .. frame .. "  " .. message .. string.rep(" ", 58 - #message) .. "║",
		"║                                                                ║",
		"╠════════════════════════════════════════════════════════════════╣",
		"║                                                                ║",
		"║  Server  : " .. server .. string.rep(" ", 50 - #server) .. "║",
		"║  Planner : " .. planner .. string.rep(" ", 50 - #planner) .. "║",
		"║                                                                ║",
		"║  [" .. bar .. "]  " .. percent .. "%  ║",
		"║                                                                ║",
		"╚════════════════════════════════════════════════════════════════╝",
		"",
		"  Press q to cancel",
	}
end

-- ─── Plan renderer ────────────────────────────────────────────────────────────

-- Save plan to file
local function save_plan_to_file(steps, domain_path, problem_path)
	if not domain_path or domain_path == "" then
		return nil, "No domain path provided"
	end

	-- Derive plan filename from domain/problem
	-- E.g., domain.pddl + problem.pddl -> domain_problem_plan.pddl
	local domain_name = vim.fn.fnamemodify(domain_path, ":t:r") -- filename without extension
	local problem_name = problem_path and vim.fn.fnamemodify(problem_path, ":t:r") or "problem"
	local dir = vim.fn.fnamemodify(domain_path, ":h")

	local plan_filename = domain_name .. "_" .. problem_name .. "_plan.pddl"
	local plan_path = dir .. "/" .. plan_filename

	-- Format a plan action: remove parentheses and add emoji by keyword
	local action_emojis = {
		["PICK-UP"] = "⬆️",
		["PUT-DOWN"] = "⬇️",
		["STACK"] = "📦",
		["UNSTACK"] = "📤",
	}
	local function format_step(step)
		local formatted = step:gsub("^%((.-)%)$", "%1")
		local keyword = formatted:match("^([A-Z%-]+)")
		if keyword and action_emojis[keyword] then
			formatted = formatted:gsub("^" .. keyword, action_emojis[keyword] .. " " .. keyword, 1)
		end
		return formatted
	end

	-- Write plan to file
	local content = {}
	for i, step in ipairs(steps) do
		table.insert(content, string.format("%d. %s", i, format_step(step)))
	end

	local f = io.open(plan_path, "w")
	if not f then
		return nil, "Could not write to " .. plan_path
	end

	f:write(table.concat(content, "\n"))
	f:write("\n")
	f:close()

	return plan_path, nil
end

local function render_result(data, server, planner, buf, domain_path, problem_path)
	local lines = {
		"",
		"╔════════════════════════════════════════════════════════════════╗",
		"║                        PDDL Plan Result                        ║",
		"╚════════════════════════════════════════════════════════════════╝",
		"",
	}

	local status = (data.status or "unknown"):lower()

	if status == "ok" then
		local result = data.result or {}
		local output = type(result.output) == "table" and result.output or {}
		local plan_str = type(output.plan) == "string" and output.plan or ""

		-- Parse the plan string into steps
		local steps = {}
		for _, line in ipairs(vim.split(plan_str, "\n", { plain = true })) do
			local trimmed = line:match("^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				table.insert(steps, trimmed)
			end
		end

		-- Extract cost from stdout
		local stdout = result.stdout or ""
		local cost = stdout:match("Plan found with cost: ([%d%.]+)")

		-- Header info
		table.insert(lines, "  📋 Server   : " .. server)
		table.insert(lines, "  🤖 Planner  : " .. planner)
		if #steps > 0 then
			table.insert(lines, "  📊 Steps    : " .. #steps)
		end
		if cost then
			table.insert(lines, "  💰 Cost     : " .. cost)
		end
		table.insert(lines, "")

		if #steps == 0 then
			table.insert(lines, "  ✓  Goal already satisfied — no actions needed!")
			table.insert(lines, "")
		else
			table.insert(lines, "  ✓  Plan found successfully!")
			table.insert(lines, "")

			-- Save plan to file
			local plan_path, save_err = save_plan_to_file(steps, domain_path, problem_path)
			if plan_path then
				table.insert(lines, "  💾 Saved to : " .. plan_path)
				table.insert(lines, "")
			elseif save_err then
				table.insert(lines, "  ⚠  Could not save plan: " .. save_err)
				table.insert(lines, "")
			end

			table.insert(lines, "  ┌─────────────────────────────────────────────────────────┐")

			for i, step in ipairs(steps) do
				if i == 1 then
					table.insert(lines, "  │  START")
				end
				table.insert(lines, "  │     ↓")
				table.insert(lines, string.format("  │  %2d. %s", i, step))
			end

			table.insert(lines, "  │     ↓")
			table.insert(lines, "  │  🎯 GOAL")
			table.insert(lines, "  └─────────────────────────────────────────────────────────┘")
			table.insert(lines, "")
		end

		-- Show planner log if verbose
		if stdout ~= "" then
			table.insert(lines, "  ─── Planner Output ─────────────────────────────────────────")
			for _, l in ipairs(vim.split(stdout, "\n", { plain = true })) do
				local trimmed = l:match("^%s*(.-)%s*$")
				if trimmed and trimmed ~= "" then
					table.insert(lines, "  " .. trimmed)
				end
			end
			table.insert(lines, "  ────────────────────────────────────────────────────────────")
		end
	else
		-- Error case
		table.insert(lines, "  📋 Server   : " .. server)
		table.insert(lines, "  🤖 Planner  : " .. planner)
		table.insert(lines, "")
		table.insert(lines, "  ✗  No solution found (status: " .. status .. ")")
		table.insert(lines, "")

		local result = data.result or {}
		local output = type(result.output) == "table" and result.output or {}
		local detail = result.stderr or output.plan or result.stdout or data.error or ""
		if detail ~= "" then
			table.insert(lines, "  ─── Error Details ──────────────────────────────────────────")
			for _, l in ipairs(vim.split(tostring(detail), "\n", { plain = true })) do
				local trimmed = l:match("^%s*(.-)%s*$")
				if trimmed and trimmed ~= "" then
					table.insert(lines, "  " .. trimmed)
				end
			end
			table.insert(lines, "  ────────────────────────────────────────────────────────────")
		end
	end

	table.insert(lines, "")
	table.insert(lines, "  Press q to close this buffer")
	table.insert(lines, "")

	set_buf_lines(buf, lines)
	apply_highlights(buf)
	ensure_visible(buf, math.min(#lines + 2, 30))
end

-- ─── Polling ──────────────────────────────────────────────────────────────────

local function poll(poll_url, planner, server, buf, attempt, max, domain_path, problem_path)
	attempt = attempt or 1

	-- Update loading state in the buffer
	vim.schedule(function()
		set_buf_lines(buf, loading_lines(server, planner, attempt, max, "Solving... waiting for plan"))
		apply_highlights(buf)
		ensure_visible(buf, 17)
	end)

	if attempt > max then
		vim.schedule(function()
			set_buf_lines(buf, {
				"",
				"  ✗  Timed out after " .. max .. " attempts.",
				"  Try a faster planner or increase the timeout.",
				"",
			})
			apply_highlights(buf)
		end)
		return
	end

	vim.defer_fn(function()
		http_get(poll_url, function(body, err)
			vim.schedule(function()
				if err then
					set_buf_lines(buf, { "", "  ✗  Poll error: " .. err, "" })
					apply_highlights(buf)
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
					apply_highlights(buf)
					return
				end

				local status = (data.status or ""):lower()
				if status == "ok" or status == "error" then
					render_result(data, server, planner, buf, domain_path, problem_path)
				else
					-- Still pending — recurse
					poll(poll_url, planner, server, buf, attempt + 1, max, domain_path, problem_path)
				end
			end)
		end)
	end, 2000)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function M.solve(server, planner, domain, problem, domain_path, problem_path)
	set_last(server, planner)

	local title = "PDDL-Plan[" .. planner .. "]"
	local buf = get_or_create_buf(title)
	local url = server .. "/package/" .. planner .. "/solve"
	local payload = vim.fn.json_encode({ domain = domain, problem = problem })

	-- Show loading state immediately
	set_buf_lines(buf, loading_lines(server, planner, 0, 30, "Submitting job..."))
	apply_highlights(buf)
	ensure_visible(buf, 17)

	http_post(url, payload, function(body, err)
		vim.schedule(function()
			if err then
				set_buf_lines(buf, { "", "  ✗  Submission failed: " .. err, "" })
				apply_highlights(buf)
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
				apply_highlights(buf)
				return
			end

			-- Server returns { "result": "/check/{uuid}?external=True" }
			local poll_path = type(data.result) == "string" and data.result or nil

			if poll_path then
				local poll_url = server .. poll_path
				set_buf_lines(buf, loading_lines(server, planner, 1, 30, "Job queued — polling for result..."))
				apply_highlights(buf)
				poll(poll_url, planner, server, buf, 1, 30, domain_path, problem_path)
			else
				-- Immediate result (some servers/planners return synchronously)
				render_result(data, server, planner, buf, domain_path, problem_path)
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
