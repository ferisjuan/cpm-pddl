# cmp-pddl

> A [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) source for
> **PDDL** (Planning Domain Definition Language) — the standard
> input language for AI planners.

---

## Features

| Category | What's completed |
|---|---|
| **Top-level keywords** | `define`, `domain`, `problem` |
| **Domain sections** | `:requirements` `:types` `:constants` `:predicates` `:functions` `:action` `:durative-action` `:derived` |
| **Problem sections** | `:domain` `:objects` `:init` `:goal` `:metric` |
| **Requirements** | All 20+ standard PDDL requirement flags |
| **Action sub-keys** | `:parameters` `:precondition` `:effect` `:duration` `:condition` |
| **Logical operators** | `and` `or` `not` `imply` `forall` `exists` `when` |
| **Temporal operators** | `at start` `at end` `over all` |
| **Numeric operators** | `increase` `decrease` `assign` `scale-up` `scale-down` |
| **Comparison** | `>` `<` `>=` `<=` `=` |
| **Metric** | `minimize` `maximize` `total-time` `total-cost` |
| **Buffer variables** | `?var` names extracted from the current buffer |
| **Buffer identifiers** | predicate / object names extracted from the current buffer |
| **Snippets** | Full domain template, problem template, action, durative-action, `forall`, `exists`, `when` |

Context-aware: completions change depending on whether you are inside a domain
or problem file, inside `:requirements`, `:action`, `:precondition`, `:effect`,
`:init`, `:goal`, etc.

---

## Requirements

- Neovim ≥ 0.9
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ferisjuan/cmp-pddl",
  ft = "pddl",
  dependencies = { "hrsh7th/nvim-cmp" },
  config = function()
    require("cmp").setup.filetype("pddl", {
      sources = require("cmp").config.sources({
        { name = "pddl" },
        { name = "buffer" },
      }),
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ferisjuan/cmp-pddl",
  requires = { "hrsh7th/nvim-cmp" },
}
```

---

## Configuration

### Minimal setup (filetype-scoped)

```lua
local cmp = require("cmp")

-- Register source (done automatically by plugin/cmp_pddl.lua)
-- cmp.register_source("pddl", require("cmp_pddl").new())

-- Apply only to PDDL buffers
cmp.setup.filetype("pddl", {
  sources = cmp.config.sources({
    { name = "pddl",   priority = 1000 },
    { name = "buffer", priority = 500  },
  }),
})
```

### Global setup (add pddl source alongside your other sources)

```lua
require("cmp").setup({
  sources = require("cmp").config.sources({
    { name = "nvim_lsp" },
    { name = "luasnip"  },
    { name = "pddl"     },   -- ← add this
    { name = "buffer"   },
  }),
})
```

---

## Snippet support

Snippets use LSP snippet syntax (`insertTextFormat = 2`). For them to expand
you need a snippet engine registered with nvim-cmp, such as
[LuaSnip](https://github.com/L3MON4D3/LuaSnip) or
[vim-vsnip](https://github.com/hrsh7th/vim-vsnip).

| Trigger | Expands to |
|---|---|
| `define-domain` | Full domain skeleton |
| `define-problem` | Full problem skeleton |
| `snippet-action` | `:action` block |
| `snippet-durative-action` | `:durative-action` block |
| `snippet-forall` | `(forall ...)` quantifier |
| `snippet-exists` | `(exists ...)` quantifier |
| `snippet-when` | `(when ...)` conditional effect |

---

## Syntax highlighting

The plugin ships a `syntax/pddl.vim` file that highlights:

- Keywords and section headers
- Requirement flags
- Variables (`?var`)
- Logical / temporal / numeric operators
- Comments (`;`)
- Numbers

---

## Filetype settings (`ftplugin/pddl.lua`)

Automatically applied to every PDDL buffer:

- 2-space indentation
- `-` treated as part of a word (for identifiers like `:durative-action`)
- Comment string set to `; %s`
- Folding on parentheses with all folds open by default

---

## License

MIT
