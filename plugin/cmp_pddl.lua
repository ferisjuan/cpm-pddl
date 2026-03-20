-- plugin/cmp_pddl.lua
-- Auto-registration entry point for cmp-pddl

-- Guard against double-loading
if vim.g.loaded_cmp_pddl then return end
vim.g.loaded_cmp_pddl = true

-- Defer registration until after VimEnter so nvim-cmp is guaranteed loaded
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local ok, cmp = pcall(require, "cmp")
    if not ok then
      vim.notify(
        "[cmp-pddl] nvim-cmp not found. Please install hrsh7th/nvim-cmp.",
        vim.log.levels.WARN
      )
      return
    end
    cmp.register_source("pddl", require("cmp_pddl").new())
  end,
})
