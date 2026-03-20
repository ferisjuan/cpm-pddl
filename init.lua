-- cmp-pddl: nvim-cmp source for PDDL (Planning Domain Definition Language)
-- Provides completions for PDDL domain and problem files

local cmp = require("cmp")

local source = {}

-- ─── Completion item kinds ────────────────────────────────────────────────────
local Kind = cmp.lsp.CompletionItemKind

-- ─── PDDL keyword data ───────────────────────────────────────────────────────

local REQUIREMENTS = {
  ":strips",
  ":typing",
  ":negative-preconditions",
  ":disjunctive-preconditions",
  ":equality",
  ":existential-preconditions",
  ":universal-preconditions",
  ":quantified-preconditions",
  ":conditional-effects",
  ":fluents",
  ":numeric-fluents",
  ":object-fluents",
  ":adl",
  ":durative-actions",
  ":duration-inequalities",
  ":continuous-effects",
  ":derived-predicates",
  ":timed-initial-literals",
  ":preferences",
  ":constraints",
  ":action-costs",
}

local DOMAIN_SECTIONS = {
  { label = ":requirements", detail = "Declare PDDL requirements",    kind = Kind.Module },
  { label = ":types",        detail = "Define object type hierarchy",  kind = Kind.Module },
  { label = ":constants",    detail = "Declare constant objects",      kind = Kind.Module },
  { label = ":predicates",   detail = "Declare predicates",            kind = Kind.Module },
  { label = ":functions",    detail = "Declare numeric functions",     kind = Kind.Module },
  { label = ":action",       detail = "Define an instantaneous action",kind = Kind.Module },
  { label = ":durative-action", detail = "Define a durative action",   kind = Kind.Module },
  { label = ":derived",      detail = "Define a derived predicate",    kind = Kind.Module },
  { label = ":constraints",  detail = "Global plan constraints",       kind = Kind.Module },
}

local PROBLEM_SECTIONS = {
  { label = ":domain",  detail = "Reference the domain name",   kind = Kind.Module },
  { label = ":objects", detail = "Declare problem objects",     kind = Kind.Module },
  { label = ":init",    detail = "Initial state facts",         kind = Kind.Module },
  { label = ":goal",    detail = "Goal condition",              kind = Kind.Module },
  { label = ":constraints", detail = "Problem-level constraints", kind = Kind.Module },
  { label = ":metric",  detail = "Optimization metric",        kind = Kind.Module },
}

local ACTION_KEYWORDS = {
  { label = ":parameters",  detail = "Parameter list for this action",   kind = Kind.Property },
  { label = ":precondition",detail = "Action precondition formula",      kind = Kind.Property },
  { label = ":effect",      detail = "Action effect formula",            kind = Kind.Property },
  -- durative-action specific
  { label = ":duration",    detail = "Duration constraint",              kind = Kind.Property },
  { label = ":condition",   detail = "Condition over time intervals",    kind = Kind.Property },
}

local LOGICAL_OPS = {
  { label = "and",    detail = "Logical conjunction",           kind = Kind.Operator },
  { label = "or",     detail = "Logical disjunction",           kind = Kind.Operator },
  { label = "not",    detail = "Logical negation",              kind = Kind.Operator },
  { label = "imply",  detail = "Logical implication",           kind = Kind.Operator },
  { label = "forall", detail = "Universal quantification",      kind = Kind.Operator },
  { label = "exists", detail = "Existential quantification",    kind = Kind.Operator },
  { label = "when",   detail = "Conditional effect",            kind = Kind.Operator },
}

local NUMERIC_OPS = {
  { label = "increase",   detail = "Increase a numeric fluent",   kind = Kind.Function },
  { label = "decrease",   detail = "Decrease a numeric fluent",   kind = Kind.Function },
  { label = "assign",     detail = "Assign a numeric fluent",     kind = Kind.Function },
  { label = "scale-up",   detail = "Scale up a fluent",           kind = Kind.Function },
  { label = "scale-down", detail = "Scale down a fluent",         kind = Kind.Function },
}

local COMPARISON_OPS = {
  { label = ">",  detail = "Greater than",          kind = Kind.Operator },
  { label = "<",  detail = "Less than",             kind = Kind.Operator },
  { label = ">=", detail = "Greater than or equal", kind = Kind.Operator },
  { label = "<=", detail = "Less than or equal",    kind = Kind.Operator },
  { label = "=",  detail = "Equal",                 kind = Kind.Operator },
}

local TEMPORAL_KEYWORDS = {
  { label = "at start",   detail = "Condition/effect at action start", kind = Kind.Keyword },
  { label = "at end",     detail = "Condition/effect at action end",   kind = Kind.Keyword },
  { label = "over all",   detail = "Condition holds throughout",       kind = Kind.Keyword },
  { label = "at",         detail = "Timed initial literal prefix",     kind = Kind.Keyword },
}

local METRIC_KEYWORDS = {
  { label = "minimize",      detail = "Minimize metric expression", kind = Kind.Keyword },
  { label = "maximize",      detail = "Maximize metric expression", kind = Kind.Keyword },
  { label = "total-time",    detail = "Total plan time",            kind = Kind.Value },
  { label = "total-cost",    detail = "Total action cost",          kind = Kind.Value },
  { label = "is-violated",   detail = "Preference violation count", kind = Kind.Function },
  { label = "is-satisfied",  detail = "Preference satisfaction",    kind = Kind.Function },
}

local TOP_LEVEL_KEYWORDS = {
  { label = "define",   detail = "Begin a domain or problem definition", kind = Kind.Keyword },
  { label = "domain",   detail = "Declare domain name",                  kind = Kind.Keyword },
  { label = "problem",  detail = "Declare problem name",                 kind = Kind.Keyword },
}

-- ─── Snippet templates ────────────────────────────────────────────────────────

local SNIPPETS = {
  {
    label = "define-domain",
    detail = "Full domain template",
    kind = Kind.Snippet,
    insertText = [[(define (domain ${1:domain-name})
  (:requirements :strips :typing)
  (:types
    ${2:type1} - object
  )
  (:predicates
    (${3:predicate1} ?${4:obj} - ${5:type1})
  )
  (:action ${6:action-name}
    :parameters (?${7:param} - ${8:type1})
    :precondition (and
      (${9:predicate1} ?${7:param})
    )
    :effect (and
      (not (${9:predicate1} ?${7:param}))
    )
  )
)]],
    insertTextFormat = 2, -- snippet
  },
  {
    label = "define-problem",
    detail = "Full problem template",
    kind = Kind.Snippet,
    insertText = [[(define (problem ${1:problem-name})
  (:domain ${2:domain-name})
  (:objects
    ${3:obj1} - ${4:type1}
  )
  (:init
    (${5:predicate1} ${3:obj1})
  )
  (:goal
    (and
      (${6:goal-predicate} ${3:obj1})
    )
  )
)]],
    insertTextFormat = 2,
  },
  {
    label = "snippet-action",
    detail = "Instantaneous action block",
    kind = Kind.Snippet,
    insertText = [[(:action ${1:action-name}
  :parameters (?${2:param} - ${3:type})
  :precondition (and
    (${4:precond} ?${2:param})
  )
  :effect (and
    (${5:effect} ?${2:param})
  )
)]],
    insertTextFormat = 2,
  },
  {
    label = "snippet-durative-action",
    detail = "Durative action block",
    kind = Kind.Snippet,
    insertText = [[(:durative-action ${1:action-name}
  :parameters (?${2:param} - ${3:type})
  :duration (= ?duration ${4:1})
  :condition (and
    (at start (${5:start-cond} ?${2:param}))
    (over all (${6:inv-cond} ?${2:param}))
  )
  :effect (and
    (at start (not (${5:start-cond} ?${2:param})))
    (at end (${7:end-effect} ?${2:param}))
  )
)]],
    insertTextFormat = 2,
  },
  {
    label = "snippet-forall",
    detail = "Universal quantifier",
    kind = Kind.Snippet,
    insertText = [[(forall (?${1:var} - ${2:type})
  (${3:formula} ?${1:var})
)]],
    insertTextFormat = 2,
  },
  {
    label = "snippet-exists",
    detail = "Existential quantifier",
    kind = Kind.Snippet,
    insertText = [[(exists (?${1:var} - ${2:type})
  (${3:formula} ?${1:var})
)]],
    insertTextFormat = 2,
  },
  {
    label = "snippet-when",
    detail = "Conditional effect",
    kind = Kind.Snippet,
    insertText = [[(when (${1:condition})
  (${2:effect})
)]],
    insertTextFormat = 2,
  },
}

-- ─── Context detection ────────────────────────────────────────────────────────

--- Detect whether the current buffer is a PDDL domain or problem file
---@param lines string[]
---@return "domain"|"problem"|"unknown"
local function detect_file_type(lines)
  for _, line in ipairs(lines) do
    local lower = line:lower()
    if lower:match("%(%s*define%s+%(%s*domain") then return "domain" end
    if lower:match("%(%s*define%s+%(%s*problem") then return "problem" end
  end
  return "unknown"
end

--- Return the text content before cursor on the current line
---@param context table cmp context
---@return string
local function get_before_cursor(context)
  local col = context.cursor.col
  local line = context.cursor_line
  return line:sub(1, col - 1)
end

--- Determine current nesting context (inside :action, :precondition, etc.)
---@param lines string[]
---@param row integer  1-based current row
---@return table  { in_action=bool, in_durative=bool, in_precond=bool, in_effect=bool,
---                 in_requirements=bool, in_init=bool, in_goal=bool, in_metric=bool }
local function get_nesting_context(lines, row)
  local ctx = {
    in_action = false,
    in_durative = false,
    in_precond = false,
    in_effect = false,
    in_requirements = false,
    in_init = false,
    in_goal = false,
    in_metric = false,
  }
  -- Scan backwards from current line
  local depth = 0
  for i = row, 1, -1 do
    local line = lines[i]:lower()
    -- Track parenthesis balance (rough approximation)
    for ch in line:gmatch("[()]]") do
      if ch == ")" then depth = depth + 1
      elseif ch == "(" then depth = depth - 1 end
    end

    if line:match(":requirements") then ctx.in_requirements = true end
    if line:match(":action%s")     then ctx.in_action = true end
    if line:match(":durative%-action%s") then ctx.in_durative = true end
    if line:match(":precondition") then ctx.in_precond = true end
    if line:match(":effect")       then ctx.in_effect = true end
    if line:match(":init%s*$") or line:match(":init%s*%(") then ctx.in_init = true end
    if line:match(":goal%s")       then ctx.in_goal = true end
    if line:match(":metric%s")     then ctx.in_metric = true end

    -- Stop after we've climbed past the nearest open paren group
    if depth <= -2 then break end
  end
  return ctx
end

-- ─── Source implementation ────────────────────────────────────────────────────

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
  return { ":", "?", "(", " " }
end

source.is_available = function(self)
  -- Only activate for PDDL file type
  local ft = vim.bo.filetype
  return ft == "pddl"
end

source.get_debug_name = function()
  return "pddl"
end

source.complete = function(self, request, callback)
  local bufnr    = vim.api.nvim_get_current_buf()
  local cursor   = request.context.cursor
  local row      = cursor.row  -- 1-based
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local before   = get_before_cursor(request.context)

  local file_type = detect_file_type(all_lines)
  local nctx      = get_nesting_context(all_lines, row)

  local items = {}

  local function add(tbl)
    for _, item in ipairs(tbl) do
      local entry = {
        label            = item.label,
        kind             = item.kind,
        detail           = item.detail,
        insertText       = item.insertText or item.label,
        insertTextFormat = item.insertTextFormat or 1,
        documentation    = item.documentation,
      }
      table.insert(items, entry)
    end
  end

  -- ── Always available ──────────────────────────────────────────────────────
  add(TOP_LEVEL_KEYWORDS)
  add(SNIPPETS)

  -- ── Requirements block ────────────────────────────────────────────────────
  if nctx.in_requirements or before:match(":requirements") then
    for _, req in ipairs(REQUIREMENTS) do
      table.insert(items, {
        label  = req,
        kind   = Kind.EnumMember,
        detail = "PDDL requirement flag",
      })
    end
  end

  -- ── Domain-specific sections ──────────────────────────────────────────────
  if file_type == "domain" or file_type == "unknown" then
    add(DOMAIN_SECTIONS)
  end

  -- ── Problem-specific sections ─────────────────────────────────────────────
  if file_type == "problem" or file_type == "unknown" then
    add(PROBLEM_SECTIONS)
    if nctx.in_metric then
      add(METRIC_KEYWORDS)
    end
  end

  -- ── Action keywords ───────────────────────────────────────────────────────
  if nctx.in_action or nctx.in_durative then
    add(ACTION_KEYWORDS)
    if nctx.in_durative then
      add(TEMPORAL_KEYWORDS)
    end
  end

  -- ── Inside logical / effect formulae ─────────────────────────────────────
  if nctx.in_precond or nctx.in_goal or nctx.in_effect
      or nctx.in_init or nctx.in_action then
    add(LOGICAL_OPS)
    add(COMPARISON_OPS)
  end

  -- ── Numeric operations (inside effect blocks) ─────────────────────────────
  if nctx.in_effect then
    add(NUMERIC_OPS)
  end

  -- ── Collect variables and identifiers already typed in buffer ────────────
  local seen = {}
  for _, line in ipairs(all_lines) do
    -- Variables: ?varname
    for var in line:gmatch("%?[%w%-_]+") do
      if not seen[var] then
        seen[var] = true
        table.insert(items, {
          label  = var,
          kind   = Kind.Variable,
          detail = "PDDL variable",
        })
      end
    end
    -- Identifiers (predicates, types, objects): bare lowercase words inside parens
    for word in line:gmatch("%(([%a][%w%-_]*)") do
      if not seen[word] and #word > 1 then
        seen[word] = true
        table.insert(items, {
          label  = word,
          kind   = Kind.Function,
          detail = "PDDL identifier",
        })
      end
    end
  end

  callback({ items = items, isIncomplete = false })
end

return source
