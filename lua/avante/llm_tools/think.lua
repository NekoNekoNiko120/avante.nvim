local Line = require("avante.ui.line")
local Base = require("avante.llm_tools.base")
local Highlights = require("avante.highlights")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "think"

function M.enabled()
  -- Always enable thinking tool for all models and providers
  -- Thinking is a fundamental capability that should be available everywhere
  return true
end

M.description =
  [[Use this tool to think through complex problems step by step. This helps you organize your thoughts and show your reasoning process to the user. Use it when you need to:
- Analyze a complex problem before taking action
- Brainstorm multiple solutions and evaluate their pros/cons
- Break down a large task into smaller steps
- Reflect on the results of previous actions
- Plan your next steps carefully

The user will see your thinking process, which helps them understand your approach and builds confidence in your solutions.

RULES:
- Use the `think` tool frequently, especially before making important decisions or tool calls
- Show your reasoning process clearly and step by step
- Consider multiple approaches and explain why you choose one over others
]]

M.support_streaming = true

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "thought",
      description = "Your thoughts.",
      type = "string",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the task was completed successfully",
    type = "string",
  },
  {
    name = "thoughts",
    description = "The thoughts that guided the solution",
    type = "string",
  },
}

---@class ThinkingInput
---@field thought string

---@type avante.LLMToolOnRender<ThinkingInput>
function M.on_render(input, opts)
  local state = opts.state
  local lines = {}
  
  -- Use simple, universal text that works in any language
  local text = state == "generating" and "🤔 Thinking" or "💭 Thoughts"
  
  table.insert(lines, Line:new({ { text, Highlights.AVANTE_THINKING } }))
  table.insert(lines, Line:new({ { "" } }))
  
  local content = input.thought or ""
  if content == "" and state == "generating" then
    table.insert(lines, Line:new({ { "> ...", Highlights.AVANTE_THINKING } }))
  else
    local text_lines = vim.split(content, "\n")
    for _, text_line in ipairs(text_lines) do
      table.insert(lines, Line:new({ { "> " .. text_line } }))
    end
  end
  
  return lines
end

---@type AvanteLLMToolFunc<ThinkingInput>
function M.func(input, opts)
  local on_complete = opts.on_complete
  if not on_complete then return false, "on_complete not provided" end
  on_complete(true, nil)
end

return M
