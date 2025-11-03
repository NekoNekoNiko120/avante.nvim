local Base = require("avante.llm_tools.base")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "get_current_diagnostics"

M.description = "Get LSP diagnostics from the currently active file that the user is working on. This is useful when the AI needs to understand what errors or warnings exist in the file being discussed."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "severity",
      description = "Filter diagnostics by severity level: 'error', 'warn', 'info', 'hint', or 'all' (default: 'all')",
      type = "string",
      optional = true,
    },
    {
      name = "include_context",
      description = "Include surrounding code context for each diagnostic. Default: false",
      type = "boolean",
      optional = true,
    },
  },
  usage = {
    severity = "Filter by severity: 'error', 'warn', 'info', 'hint', or 'all'",
    include_context = "Include code context around diagnostics",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "diagnostics",
    description = "Array of diagnostic information with line numbers, messages, and severity",
    type = "string",
  },
  {
    name = "file_info",
    description = "Information about the current file",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the operation failed",
    type = "string",
    optional = true,
  },
}

---@param bufnr number
---@param line_num number
---@param context_lines number
---@return string[]
local function get_line_context(bufnr, line_num, context_lines)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local start_line = math.max(1, line_num - context_lines)
  local end_line = math.min(total_lines, line_num + context_lines)
  
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local context = {}
  
  for i, line in ipairs(lines) do
    local actual_line_num = start_line + i - 1
    local prefix = actual_line_num == line_num and ">>> " or "    "
    table.insert(context, string.format("%s%d: %s", prefix, actual_line_num, line))
  end
  
  return context
end

---@type AvanteLLMToolFunc<{ severity?: string, include_context?: boolean }>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete
  
  if not on_complete then 
    return false, "on_complete is required" 
  end
  
  local severity_filter = input.severity or "all"
  local include_context = input.include_context or false
  
  if on_log then 
    on_log("severity: " .. severity_filter .. ", include_context: " .. tostring(include_context))
  end
  
  -- Get the current buffer from the sidebar context
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.code or not sidebar.code.bufnr then
    return false, "No active buffer found in sidebar context"
  end
  
  local bufnr = sidebar.code.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Current buffer is not valid"
  end
  
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(buf_name, ":~:.")
  
  if on_log then on_log("Getting diagnostics for buffer: " .. relative_path) end
  
  -- Get diagnostics for the current buffer
  local diagnostics = Utils.lsp.get_diagnostics(bufnr)
  
  -- Filter by severity if specified
  if severity_filter ~= "all" then
    local filtered = {}
    for _, diag in ipairs(diagnostics) do
      if string.lower(diag.severity) == string.lower(severity_filter) then
        table.insert(filtered, diag)
      end
    end
    diagnostics = filtered
  end
  
  -- Enhance diagnostics with context if requested
  local enhanced_diagnostics = {}
  for _, diag in ipairs(diagnostics) do
    local enhanced_diag = {
      line = diag.start_line,
      end_line = diag.end_line,
      message = diag.content,
      severity = diag.severity,
      source = diag.source,
    }
    
    if include_context then
      enhanced_diag.context = get_line_context(bufnr, diag.start_line, 2)
    end
    
    table.insert(enhanced_diagnostics, enhanced_diag)
  end
  
  -- Create summary
  local summary = {
    total = #enhanced_diagnostics,
    errors = 0,
    warnings = 0,
    info = 0,
    hints = 0,
  }
  
  for _, diag in ipairs(enhanced_diagnostics) do
    if diag.severity == "ERROR" then
      summary.errors = summary.errors + 1
    elseif diag.severity == "WARN" then
      summary.warnings = summary.warnings + 1
    elseif diag.severity == "INFO" then
      summary.info = summary.info + 1
    elseif diag.severity == "HINT" then
      summary.hints = summary.hints + 1
    end
  end
  
  local file_info = {
    path = relative_path,
    full_path = buf_name,
    line_count = vim.api.nvim_buf_line_count(bufnr),
    filetype = vim.bo[bufnr].filetype,
  }
  
  local result = {
    diagnostics = enhanced_diagnostics,
    summary = summary,
    file_info = file_info,
  }
  
  local json_str = vim.json.encode(result)
  on_complete(json_str, nil)
end

return M