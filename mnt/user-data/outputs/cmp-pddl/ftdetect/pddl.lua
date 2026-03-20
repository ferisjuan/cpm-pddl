-- ftdetect/pddl.lua
-- Automatically set filetype for .pddl files

vim.filetype.add({
  extension = {
    pddl = "pddl",
  },
  pattern = {
    -- Files that start with (define (domain ...) or (define (problem ...)
    [".*%.pddl"] = "pddl",
  },
})
