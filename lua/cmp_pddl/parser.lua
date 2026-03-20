-- lua/cmp_pddl/parser.lua
-- Extracts structured DomainInfo / ProblemInfo from a syntax tree.
-- Modelled after pddl-workspace's DomainInfo / ProblemInfo classes.
--
-- Works on incomplete documents — missing sections produce empty tables,
-- never nil errors, so callers can always access .predicates, .actions, etc.

local tokenizer = require("cmp_pddl.tokenizer")
local syntax_tree = require("cmp_pddl.syntax_tree")

local M = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

--- Return atoms of a node, skipping the first one if it matches the head keyword.
--- e.g. for (domain blocksworld): atoms=[domain, blocksworld] → returns [blocksworld]
---@param node SNode
---@return {value:string, token_type:string}[]
local function content_atoms(node)
	local all = syntax_tree.atoms(node)
	if #all > 0 and all[1].value == node.value then
		local result = {}
		for i = 2, #all do
			result[#result + 1] = all[i]
		end
		return result
	end
	return all
end

--- Scan a node's children sequentially and return a table mapping each
--- bare KEYWORD token to the next sibling NODE after it.
--- This handles PDDL action bodies where sub-keys like :parameters,
--- :precondition, :effect are bare keyword tokens (NOT wrapped in parens),
--- each immediately followed by a node like (?x - block) or (and ...).
---
--- e.g.  :action pick-up
---         :parameters (?x - block)   → map[":parameters"] = <node (?x - block)>
---         :precondition (and ...)     → map[":precondition"] = <node and>
---@param node SNode
---@return table<string, SNode>
local function scan_keyword_map(node)
	local map = {}
	local children = node.children
	local i = 1
	while i <= #children do
		local ch = children[i]
		if ch.type == "token" and ch.token_type == "KEYWORD" then
			-- find the next node sibling (skip any intervening tokens like the name)
			local j = i + 1
			while j <= #children and children[j].type == "token" do
				j = j + 1
			end
			if j <= #children and children[j].type == "node" then
				map[ch.value] = children[j]
			end
		end
		i = i + 1
	end
	return map
end

-- ─── Typed-list parser ────────────────────────────────────────────────────────
-- Handles:  obj1 obj2 - type1  obj3 - type2  obj4   (implicit type = object)
-- Input: flat list of {value, token_type} atoms

---@param atoms {value:string, token_type:string}[]
---@return {name:string, type:string}[]
local function parse_typed_list(atoms)
	local result = {}
	local pending = {}
	local i = 1
	while i <= #atoms do
		local a = atoms[i]
		if a.value == "-" then
			local typ = (atoms[i + 1] and atoms[i + 1].value) or "object"
			for _, name in ipairs(pending) do
				result[#result + 1] = { name = name, type = typ }
			end
			pending = {}
			i = i + 2
		else
			pending[#pending + 1] = a.value
			i = i + 1
		end
	end
	for _, name in ipairs(pending) do
		result[#result + 1] = { name = name, type = "object" }
	end
	return result
end

-- ─── Predicate / function signature parser ────────────────────────────────────
-- Each child of (:predicates ...) looks like:  (pred-name ?a - t1 ?b - t2)

---@param node SNode
---@return {name:string, params:{name:string,type:string}[]}
local function parse_signature(node)
	return {
		name = node.value or "?",
		params = parse_typed_list(content_atoms(node)),
	}
end

-- ─── Parameter list extractor ─────────────────────────────────────────────────
-- :parameters can appear as:
--   a) a bare keyword followed by a node:  :parameters (?x - block)
--   b) a child node whose head is :parameters
-- The keyword_map (from scan_keyword_map) handles case (a).

---@param keyword_map table<string, SNode>
---@return {name:string, type:string}[]
local function extract_params(keyword_map)
	local param_node = keyword_map[":parameters"]
	if not param_node then
		return {}
	end
	-- The params list may be the node itself (head = nil, children = ?x - block)
	-- or a single child node wrapping them.  Either way, gather all atoms.
	local function all_atoms_flat(n)
		local acc = {}
		for _, ch in ipairs(n.children) do
			if ch.type == "token" and ch.token_type ~= "COMMENT" then
				acc[#acc + 1] = ch
			elseif ch.type == "node" then
				for _, a in ipairs(all_atoms_flat(ch)) do
					acc[#acc + 1] = a
				end
			end
		end
		return acc
	end
	return parse_typed_list(all_atoms_flat(param_node))
end

-- ─── DomainInfo ───────────────────────────────────────────────────────────────

---@class TypeInfo
---@field name   string
---@field parent string

---@class PredicateInfo
---@field name   string
---@field params {name:string, type:string}[]

---@class ActionInfo
---@field name   string
---@field kind   "action"|"durative-action"
---@field params {name:string, type:string}[]
---@field line   integer

---@class DomainInfo
---@field name         string
---@field requirements string[]
---@field types        TypeInfo[]
---@field constants    {name:string, type:string}[]
---@field predicates   PredicateInfo[]
---@field functions    PredicateInfo[]
---@field actions      ActionInfo[]
---@field raw          string

---@param text string
---@return DomainInfo, string|nil
function M.parse_domain(text)
	local info = {
		name = "",
		requirements = {},
		types = {},
		constants = {},
		predicates = {},
		functions = {},
		actions = {},
		raw = text,
	}

	local tokens = tokenizer.tokenize(text)
	local root = syntax_tree.build(tokens)

	local define = syntax_tree.find_child(root, "define")
	if not define then
		return info, "missing (define ...) block"
	end

	-- (domain <name>)
	local domain_node = syntax_tree.find_child(define, "domain")
	if domain_node then
		local a = content_atoms(domain_node)[1]
		info.name = a and a.value or ""
	end

	-- (:requirements :flag ...)
	local req_node = syntax_tree.find_child(define, ":requirements")
	if req_node then
		for _, a in ipairs(syntax_tree.atoms(req_node)) do
			if a.token_type == "KEYWORD" and a.value ~= ":requirements" then
				info.requirements[#info.requirements + 1] = a.value
			end
		end
	end

	-- (:types ...)  — collect all tokens recursively so "child - parent" pairs work
	local types_node = syntax_tree.find_child(define, ":types")
	if types_node then
		local flat = {}
		local function collect(n)
			for _, ch in ipairs(n.children) do
				if ch.type == "token" and ch.token_type ~= "COMMENT" and ch.value ~= ":types" then
					flat[#flat + 1] = ch
				elseif ch.type == "node" then
					collect(ch)
				end
			end
		end
		collect(types_node)
		for _, t in ipairs(parse_typed_list(flat)) do
			info.types[#info.types + 1] = { name = t.name, parent = t.type }
		end
		-- Always include the root 'object' type (implicit in all PDDL domains)
		local has_object = false
		for _, t in ipairs(info.types) do
			if t.name == "object" then
				has_object = true
				break
			end
		end
		if not has_object then
			table.insert(info.types, 1, { name = "object", parent = "object" })
		end
	end

	-- (:constants ...)
	local const_node = syntax_tree.find_child(define, ":constants")
	if const_node then
		info.constants = parse_typed_list(content_atoms(const_node))
	end

	-- (:predicates (pred ?a - t) ...)
	local pred_node = syntax_tree.find_child(define, ":predicates")
	if pred_node then
		for _, ch in ipairs(pred_node.children) do
			if ch.type == "node" then
				info.predicates[#info.predicates + 1] = parse_signature(ch)
			end
		end
	end

	-- (:functions (f ?a - t) ...)
	local func_node = syntax_tree.find_child(define, ":functions")
	if func_node then
		for _, ch in ipairs(func_node.children) do
			if ch.type == "node" then
				info.functions[#info.functions + 1] = parse_signature(ch)
			end
		end
	end

	-- (:action name :parameters (...) :precondition (...) :effect (...))
	-- Sub-keys are BARE keyword tokens (not nodes), so we use scan_keyword_map.
	local function parse_action(action_node, kind)
		-- name: first ATOM token after the ":action"/":durative-action" head token
		local aname = ""
		for _, ch in ipairs(action_node.children) do
			if ch.type == "token" and ch.token_type == "ATOM" then
				aname = ch.value
				break
			end
		end
		local kmap = scan_keyword_map(action_node)
		local params = extract_params(kmap)
		info.actions[#info.actions + 1] = {
			name = aname,
			kind = kind,
			params = params,
			line = action_node.line,
		}
	end

	for _, n in ipairs(syntax_tree.find_children(define, ":action")) do
		parse_action(n, "action")
	end
	for _, n in ipairs(syntax_tree.find_children(define, ":durative-action")) do
		parse_action(n, "durative-action")
	end

	return info, nil
end

-- ─── ProblemInfo ──────────────────────────────────────────────────────────────

---@class InitFact
---@field text string

---@class ProblemInfo
---@field name    string
---@field domain  string
---@field objects {name:string, type:string}[]
---@field init    InitFact[]
---@field goal    string
---@field metric  string|nil
---@field raw     string

---@param text string
---@return ProblemInfo, string|nil
function M.parse_problem(text)
	local info = {
		name = "",
		domain = "",
		objects = {},
		init = {},
		goal = "",
		metric = nil,
		raw = text,
	}

	local tokens = tokenizer.tokenize(text)
	local root = syntax_tree.build(tokens)

	local define = syntax_tree.find_child(root, "define")
	if not define then
		return info, "missing (define ...) block"
	end

	-- (problem <name>)
	local prob_node = syntax_tree.find_child(define, "problem")
	if prob_node then
		local a = content_atoms(prob_node)[1]
		info.name = a and a.value or ""
	end

	-- (:domain <name>)
	local domain_ref = syntax_tree.find_child(define, ":domain")
	if domain_ref then
		local a = content_atoms(domain_ref)[1]
		info.domain = a and a.value or ""
	end

	-- (:objects ...)
	local obj_node = syntax_tree.find_child(define, ":objects")
	if obj_node then
		info.objects = parse_typed_list(content_atoms(obj_node))
	end

	-- (:init (fact1 ...) (fact2 ...) ...)
	local init_node = syntax_tree.find_child(define, ":init")
	if init_node then
		local function serialize(n)
			if n.type == "token" then
				return n.value
			end
			local parts = {}
			for _, c in ipairs(n.children) do
				parts[#parts + 1] = serialize(c)
			end
			return "(" .. table.concat(parts, " ") .. ")"
		end
		for _, ch in ipairs(init_node.children) do
			if ch.type == "node" then
				info.init[#info.init + 1] = { text = serialize(ch) }
			end
		end
	end

	-- (:goal (...))
	local goal_node = syntax_tree.find_child(define, ":goal")
	if goal_node then
		local function serialize(n)
			if n.type == "token" then
				return n.value
			end
			local parts = {}
			for _, c in ipairs(n.children) do
				parts[#parts + 1] = serialize(c)
			end
			return "(" .. table.concat(parts, " ") .. ")"
		end
		for _, ch in ipairs(goal_node.children) do
			if ch.type == "node" then
				info.goal = serialize(ch)
				break
			end
		end
	end

	-- (:metric minimize ...)
	local metric_node = syntax_tree.find_child(define, ":metric")
	if metric_node then
		local parts = {}
		for _, a in ipairs(content_atoms(metric_node)) do
			parts[#parts + 1] = a.value
		end
		info.metric = table.concat(parts, " ")
	end

	return info, nil
end

-- ─── Validation ───────────────────────────────────────────────────────────────

---@class ValidationResult
---@field ok       boolean
---@field errors   string[]
---@field warnings string[]

---@param domain  DomainInfo
---@param problem ProblemInfo
---@return ValidationResult
function M.validate(domain, problem)
	local r = { ok = true, errors = {}, warnings = {} }
	local function err(msg)
		r.ok = false
		r.errors[#r.errors + 1] = msg
	end
	local function warn(msg)
		r.warnings[#r.warnings + 1] = msg
	end

	-- domain name match
	if problem.domain ~= "" and domain.name ~= "" and problem.domain ~= domain.name then
		err(("Problem references domain '%s' but open domain is '%s'"):format(problem.domain, domain.name))
	end

	-- build known type set
	local known_types = { object = true }
	for _, t in ipairs(domain.types) do
		known_types[t.name] = true
	end
	for _, c in ipairs(domain.constants) do
		known_types[c.type] = true
	end

	for _, obj in ipairs(problem.objects) do
		if not known_types[obj.type] then
			err(("Object '%s' has unknown type '%s'"):format(obj.name, obj.type))
		end
	end

	if #domain.predicates == 0 then
		warn("Domain declares no predicates")
	end
	if #domain.actions == 0 then
		warn("Domain declares no actions")
	end
	if #problem.init == 0 then
		warn("Problem :init is empty")
	end
	if problem.goal == "" then
		warn("Problem has no :goal")
	end

	return r
end

-- ─── Utilities ────────────────────────────────────────────────────────────────

---@param text string
---@return "domain"|"problem"|"unknown"
function M.detect_file_type(text)
	local lower = text:lower()
	if lower:match("%(define%s+%(domain") then
		return "domain"
	end
	if lower:match("%(define%s+%(problem") then
		return "problem"
	end
	return "unknown"
end

---Find domain and problem buffers among all loaded PDDL buffers.
---@param current_buf integer
---@return integer|nil domain_buf, integer|nil problem_buf
function M.find_pair(current_buf)
	local domain_buf, problem_buf
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "pddl" then
			local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
			local ft = M.detect_file_type(table.concat(lines, "\n"))
			if ft == "domain" and not domain_buf then
				domain_buf = b
			end
			if ft == "problem" and not problem_buf then
				problem_buf = b
			end
		end
	end
	return domain_buf, problem_buf
end

return M
