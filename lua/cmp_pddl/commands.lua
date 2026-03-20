-- lua/cmp_pddl/commands.lua
-- Defines all :Pddl* user commands.
-- Sourced once by plugin/cmp_pddl.lua

local M = {}

function M.setup()
	local parser = require("cmp_pddl.parser")
	local solver = require("cmp_pddl.solver")

	-- ── :PddlParse ─────────────────────────────────────────────────────────────
	-- Parse the current buffer and display the AST in a split.
	vim.api.nvim_create_user_command("PddlParse", function()
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local text = table.concat(lines, "\n")
		local ft = parser.detect_file_type(text)
		local result, err

		if ft == "domain" then
			result, err = parser.parse_domain(text)
		elseif ft == "problem" then
			result, err = parser.parse_problem(text)
		else
			vim.notify("[cmp-pddl] Not a PDDL domain or problem file", vim.log.levels.WARN)
			return
		end

		if err then
			vim.notify("[cmp-pddl] Parse error: " .. err, vim.log.levels.ERROR)
			return
		end

		local out = vim.split(vim.inspect(result), "\n")
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].buftype = "nofile"
		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_win_set_height(0, 20)
		vim.keymap.set("n", "q", ":bd<CR>", { buffer = buf, silent = true })
	end, { desc = "Parse current PDDL buffer and show structure" })

	-- ── :PddlSolve ─────────────────────────────────────────────────────────────
	-- Pick server → pick planner → submit → show plan in new buffer.
	vim.api.nvim_create_user_command("PddlSolve", function()
		-- 1. Find domain + problem buffers
		local cur = vim.api.nvim_get_current_buf()
		local domain_buf, problem_buf = parser.find_pair(cur)

		if not domain_buf then
			vim.notify("[cmp-pddl] No PDDL domain buffer found — open a domain file", vim.log.levels.ERROR)
			return
		end
		if not problem_buf then
			vim.notify("[cmp-pddl] No PDDL problem buffer found — open a problem file", vim.log.levels.ERROR)
			return
		end

		local d_text = table.concat(vim.api.nvim_buf_get_lines(domain_buf, 0, -1, false), "\n")
		local p_text = table.concat(vim.api.nvim_buf_get_lines(problem_buf, 0, -1, false), "\n")

		-- 2. Validate before sending
		local domain, derr = parser.parse_domain(d_text)
		local problem, perr = parser.parse_problem(p_text)

		if not domain then
			vim.notify("[cmp-pddl] Domain parse error: " .. (derr or "?"), vim.log.levels.ERROR)
			return
		end
		if not problem then
			vim.notify("[cmp-pddl] Problem parse error: " .. (perr or "?"), vim.log.levels.ERROR)
			return
		end

		local val = parser.validate(domain, problem)
		for _, w in ipairs(val.warnings) do
			vim.notify("[cmp-pddl] " .. w, vim.log.levels.WARN)
		end
		if not val.ok then
			vim.notify("[cmp-pddl] Validation failed:\n" .. table.concat(val.errors, "\n"), vim.log.levels.ERROR)
			return
		end

		-- 3. Pick server
		M._pick_server(function(server)
			if not server then
				return
			end

			-- 4. Pick planner
			M._pick_planner(server, function(planner)
				if not planner then
					return
				end

				-- 5. Solve
				solver.solve(server, planner, domain.raw, problem.raw)
			end)
		end)
	end, { desc = "Send domain+problem to a PDDL solver and show the plan" })

	-- ── :PddlAddServer ─────────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("PddlAddServer", function()
		M._prompt_new_server(function() end)
	end, { desc = "Add a PDDL solver server URL" })

	-- ── :PddlServers ───────────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("PddlServers", function()
		local servers = solver.get_servers()
		if #servers == 0 then
			vim.notify("[cmp-pddl] No servers saved. Use :PddlAddServer", vim.log.levels.INFO)
			return
		end
		local lines = { "", "  Saved PDDL solver servers:", "" }
		for i, s in ipairs(servers) do
			table.insert(lines, string.format("  [%d]  %-20s  %s", i, s.name, s.url))
		end
		table.insert(lines, "")
		table.insert(lines, "  :PddlAddServer to add  |  :PddlSolve to run")
		table.insert(lines, "")
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].buftype = "nofile"
		vim.cmd("botright split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_win_set_height(0, #lines + 2)
		vim.keymap.set("n", "q", ":bd<CR>", { buffer = buf, silent = true })
	end, { desc = "List saved PDDL solver servers" })
end

-- ─── Server picker ────────────────────────────────────────────────────────────

function M._pick_server(on_done)
	local solver = require("cmp_pddl.solver")
	local servers = solver.get_servers()
	local last_server, _ = solver.get_last()

	-- Build select items
	local items = {}
	local item_map = {}

	for _, s in ipairs(servers) do
		local label = s.name .. "  (" .. s.url .. ")"
		if s.url == last_server then
			label = "★ " .. label
		end
		table.insert(items, label)
		item_map[label] = s.url
	end

	table.insert(items, "+ Add new server…")

	vim.ui.select(items, { prompt = "Select PDDL solver server:" }, function(choice)
		if not choice then
			on_done(nil)
			return
		end

		if choice == "+ Add new server…" then
			M._prompt_new_server(function(url)
				if url then
					on_done(url)
				end
			end)
		else
			on_done(item_map[choice])
		end
	end)
end

-- ─── New server prompt ────────────────────────────────────────────────────────

function M._prompt_new_server(on_done)
	local solver = require("cmp_pddl.solver")

	vim.ui.input({
		prompt = "Server URL: ",
		default = "https://solver.planning.domains:5001",
	}, function(url)
		if not url or url == "" then
			on_done(nil)
			return
		end
		url = url:gsub("/$", "") -- strip trailing slash

		vim.ui.input({
			prompt = "Friendly name: ",
			default = url:match("//([^:/]+)") or "solver",
		}, function(name)
			if not name or name == "" then
				name = url
			end
			solver.add_server(url, name)
			vim.notify("[cmp-pddl] Server saved: " .. name .. " → " .. url, vim.log.levels.INFO)
			on_done(url)
		end)
	end)
end

-- ─── Planner picker ───────────────────────────────────────────────────────────

function M._pick_planner(server, on_done)
	local solver = require("cmp_pddl.solver")
	local _, last_planner = solver.get_last()

	vim.notify("[cmp-pddl] Fetching planners from " .. server .. " …", vim.log.levels.INFO)

	solver.fetch_planners(server, function(planners, err)
		vim.schedule(function()
			if err or not planners or #planners == 0 then
				-- Fallback: let user type a planner name manually
				vim.notify(
					"[cmp-pddl] Could not fetch planner list"
						.. (err and (": " .. err) or " — server returned nothing")
						.. ". Enter planner name manually.",
					vim.log.levels.WARN
				)

				vim.ui.input({
					prompt = "Planner name (e.g. bfws-pref): ",
					default = last_planner or "lama-first",
				}, function(p)
					if p and p ~= "" then
						on_done(p)
					end
				end)
				return
			end

			-- Build select items, star the last used one
			local items = {}
			local item_map = {}
			for _, p in ipairs(planners) do
				local label = p.id
				if p.description ~= "" then
					label = label .. "  —  " .. p.description
				end
				if p.id == last_planner then
					label = "★ " .. label
				end
				table.insert(items, label)
				item_map[label] = p.id
			end

			vim.ui.select(items, { prompt = "Select planner  (" .. #items .. " available):" }, function(choice)
				if not choice then
					on_done(nil)
					return
				end
				on_done(item_map[choice])
			end)
		end)
	end)
end

return M
