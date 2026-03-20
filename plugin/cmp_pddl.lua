-- plugin/cmp_pddl.lua
-- Auto-registration entry point for cmp-pddl

-- Guard against double-loading
if vim.g.loaded_cmp_pddl then
	return
end
vim.g.loaded_cmp_pddl = true

-- Defer registration until after VimEnter so nvim-cmp is guaranteed loaded
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		local ok, cmp = pcall(require, "cmp")
		if not ok then
			vim.notify("[cmp-pddl] nvim-cmp not found. Please install hrsh7th/nvim-cmp.", vim.log.levels.WARN)
			return
		end
		cmp.register_source("pddl", require("cmp_pddl").new())
	end,
})

vim.api.nvim_create_user_command("PddlParse", function()
	local parser = require("cmp_pddl.parser")
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local text = table.concat(lines, "\n")
	local ft = parser.detect_file_type(text)

	local result
	if ft == "domain" then
		result = parser.parse_domain(text)
	elseif ft == "problem" then
		result = parser.parse_problem(text)
	else
		print("Not a PDDL file")
		return
	end

	local out = vim.split(vim.inspect(result), "\n")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
	vim.cmd("split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.bo[buf].filetype = "lua"
end, { desc = "Parse current PDDL buffer and show structure" })
