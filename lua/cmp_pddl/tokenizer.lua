-- lua/cmp_pddl/tokenizer.lua
-- Converts raw PDDL text into a flat list of typed tokens.
-- Tolerant: never throws, always returns whatever tokens it finds.
--
-- Token types:
--   LPAREN   (
--   RPAREN   )
--   KEYWORD  :requirements  :action  :strips  etc.
--   VARIABLE ?param
--   ATOM     any bare identifier / number / operator
--   COMMENT  ; ... (stored but ignored by the tree builder)

local M = {}

---@class Token
---@field type  "LPAREN"|"RPAREN"|"KEYWORD"|"VARIABLE"|"ATOM"|"COMMENT"
---@field value string
---@field line  integer   1-based
---@field col   integer   1-based

---Tokenize a PDDL string.
---@param text string
---@return Token[]
function M.tokenize(text)
	local tokens = {}
	local i = 1
	local line = 1
	local col = 1
	local len = #text

	local function advance(n)
		n = n or 1
		for _ = 1, n do
			if i <= len then
				if text:sub(i, i) == "\n" then
					line = line + 1
					col = 1
				else
					col = col + 1
				end
				i = i + 1
			end
		end
	end

	local function peek(offset)
		offset = offset or 0
		return text:sub(i + offset, i + offset)
	end

	local function push(typ, value, l, c)
		tokens[#tokens + 1] = { type = typ, value = value, line = l, col = c }
	end

	while i <= len do
		local ch = peek()
		local tl = line
		local tc = col

		-- Whitespace
		if ch:match("%s") then
			advance()

		-- Comment  ; ... \n
		elseif ch == ";" then
			local start = i
			while i <= len and peek() ~= "\n" do
				advance()
			end
			push("COMMENT", text:sub(start, i - 1), tl, tc)

		-- Left paren
		elseif ch == "(" then
			push("LPAREN", "(", tl, tc)
			advance()

		-- Right paren
		elseif ch == ")" then
			push("RPAREN", ")", tl, tc)
			advance()

		-- Variable  ?identifier
		elseif ch == "?" then
			local start = i
			advance() -- consume '?'
			while i <= len and peek():match("[%w%-_]") do
				advance()
			end
			push("VARIABLE", text:sub(start, i - 1):lower(), tl, tc)

		-- Keyword  :identifier
		elseif ch == ":" then
			local start = i
			advance() -- consume ':'
			while i <= len and peek():match("[%w%-_]") do
				advance()
			end
			push("KEYWORD", text:sub(start, i - 1):lower(), tl, tc)

		-- Atom: identifier, number, operator (-, =, <, >, etc.)
		else
			local start = i
			-- Grab everything that is not whitespace or structural
			while i <= len and not peek():match("[%s%(%)%;]") do
				advance()
			end
			local val = text:sub(start, i - 1)
			if #val > 0 then
				push("ATOM", val:lower(), tl, tc)
			else
				advance() -- safety: skip unknown single char
			end
		end
	end

	return tokens
end

return M
