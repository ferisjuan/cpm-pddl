-- lua/cmp_pddl/syntax_tree.lua
-- Builds a tolerant S-expression tree from a token list.
-- Modelled after pddl-workspace's PddlSyntaxTreeBuilder:
--   • Never throws on incomplete/malformed input
--   • Unclosed parens just become nodes whose children end at EOF
--   • Extra closing parens are silently ignored
--
-- Node shape:
--   { type = "root"|"node"|"token", value = string|nil,
--     children = Node[], line = n, col = n,
--     open_line = n, close_line = n }

local M = {}

---@class SNode
---@field type     "root"|"node"|"token"
---@field value    string|nil          -- head atom for "node", raw value for "token"
---@field token_type string|nil        -- original token type for leaf tokens
---@field children SNode[]
---@field line     integer
---@field col      integer
---@field close_line integer|nil

local function new_node(value, line, col)
	return { type = "node", value = value, children = {}, line = line, col = col }
end

local function new_token(tok)
	return {
		type = "token",
		value = tok.value,
		token_type = tok.type,
		children = {},
		line = tok.line,
		col = tok.col,
	}
end

---Build an S-expression tree from a token list.
---@param tokens table[]  output of tokenizer.tokenize()
---@return SNode  root node
function M.build(tokens)
	local root = { type = "root", value = nil, children = {}, line = 1, col = 1 }
	local stack = { root } -- stack of open nodes

	local i = 1
	while i <= #tokens do
		local tok = tokens[i]

		if tok.type == "COMMENT" then
			-- skip comments in tree (they are already stored in token list if needed)
			i = i + 1
		elseif tok.type == "LPAREN" then
			-- Start a new node; peek ahead to find the head atom
			local head = nil
			local head_line, head_col = tok.line, tok.col
			-- Look for first non-comment, non-whitespace token after '('
			local j = i + 1
			while j <= #tokens and tokens[j].type == "COMMENT" do
				j = j + 1
			end
			if j <= #tokens and tokens[j].type ~= "RPAREN" and tokens[j].type ~= "LPAREN" then
				local candidate = tokens[j]
				if candidate.type == "KEYWORD" or candidate.type == "ATOM" then
					head = candidate.value
					-- We'll still add the head as a child token so callers can find it
				end
			end

			local node = new_node(head, head_line, head_col)
			local parent = stack[#stack]
			parent.children[#parent.children + 1] = node
			stack[#stack + 1] = node
			i = i + 1
		elseif tok.type == "RPAREN" then
			-- Close current node (unless we're at root — ignore extra close parens)
			if #stack > 1 then
				local closed = table.remove(stack)
				closed.close_line = tok.line
			end
			i = i + 1
		else
			-- Leaf token — attach to current parent
			local parent = stack[#stack]
			parent.children[#parent.children + 1] = new_token(tok)
			i = i + 1
		end
	end

	-- Any unclosed nodes are implicitly closed at EOF (tolerant behaviour)
	return root
end

-- ─── Tree query helpers ───────────────────────────────────────────────────────

---Find all direct-child nodes whose head matches a keyword/atom value.
---@param node SNode
---@param head string   e.g. ":action", "define", ":predicates"
---@return SNode[]
function M.find_children(node, head)
	local result = {}
	for _, child in ipairs(node.children) do
		if child.type == "node" and child.value == head then
			result[#result + 1] = child
		end
	end
	return result
end

---Find the first direct-child node with a given head (or nil).
---@param node SNode
---@param head string
---@return SNode|nil
function M.find_child(node, head)
	return M.find_children(node, head)[1]
end

---Recursively search the whole subtree for nodes with a given head.
---@param node  SNode
---@param head  string
---@return SNode[]
function M.find_all(node, head)
	local result = {}
	local function walk(n)
		if n.type == "node" and n.value == head then
			result[#result + 1] = n
		end
		for _, ch in ipairs(n.children) do
			walk(ch)
		end
	end
	walk(node)
	return result
end

---Return a flat list of leaf token values from a node (non-recursive).
---Skips the first child if it is the head keyword already stored in node.value.
---@param node    SNode
---@param skip_head boolean  default true
---@return string[]
function M.leaf_values(node, skip_head)
	if skip_head == nil then
		skip_head = true
	end
	local result = {}
	local first = true
	for _, ch in ipairs(node.children) do
		if ch.type == "token" then
			if first and skip_head and ch.value == node.value then
			-- skip the head token itself
			else
				result[#result + 1] = ch.value
			end
			first = false
		end
	end
	return result
end

---Return atom children only (no nested nodes), with their token_type.
---@param node SNode
---@return {value:string, token_type:string}[]
function M.atoms(node)
	local result = {}
	for _, ch in ipairs(node.children) do
		if ch.type == "token" and ch.token_type ~= "COMMENT" then
			result[#result + 1] = { value = ch.value, token_type = ch.token_type }
		end
	end
	return result
end

return M
