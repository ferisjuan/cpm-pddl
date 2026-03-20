-- ftplugin/pddl.lua
-- Buffer-local settings for PDDL files

if vim.b.did_ftplugin_pddl then return end
vim.b.did_ftplugin_pddl = true

local opt = vim.opt_local

-- PDDL uses Lisp-style indentation
opt.expandtab   = true
opt.shiftwidth  = 2
opt.tabstop     = 2
opt.softtabstop = 2

-- Treat '-' as part of a word (common in PDDL identifiers like :durative-action)
opt.iskeyword:append("-")

-- Comment string
opt.commentstring = "; %s"

-- Fold on parentheses
opt.foldmethod = "syntax"
opt.foldlevel  = 99   -- open all folds by default

-- Match parens for bracket highlighting
opt.showmatch  = true

-- Auto-pair helpers (if user has no dedicated plugin, minimal help)
vim.keymap.set("i", "(", "()<Left>", { buffer = true, desc = "Auto-close paren" })
vim.keymap.set("i", "(<CR>", "(<CR>)<Esc>O", { buffer = true })
