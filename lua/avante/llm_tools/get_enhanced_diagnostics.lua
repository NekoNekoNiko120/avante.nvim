local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "get_enhanced_diagnostics"

M.description = "Get comprehensive LSP diagnostics from files with filtering options. This tool provides detailed information about errors, warnings, hints, and other code issues. It can filter by severity level and supports multiple files or entire project scanning."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The path to the file or directory in the current project scope. Use '.' for entire project.",
      type = "string",
    },
    {
      name = "severity",
      description = "Filter diagnostics by severity level: 'error', 'warn', 'info', 'hint', or 'all' (default: 'all')",
      type = "string",
      optional = true,
    },
    {
      name = "include_source",
      description = "Include the source of the diagnostic (e.g., 'typescript', 'eslint'). Default: true",
      type = "boolean",
      optional = true,
    },
    {
      name = "max_results",
      description = "Maximum number of diagnostics to return. Default: 50",
      type = "number",
      optional = true,
    },
  },
  usage = {
    path = "The path to the file or directory in the current project scope",
    severity = "Filter by severity: 'error', 'warn', 'info', 'hint', or 'all'",
    include_source = "Include diagnostic source information",
    max_results = "Maximum number of results to return",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "diagnostics",
    description = "Array of diagnostic information with file paths, line numbers, messages, and severity",
    type = "string",
  },
  {
    name = "summary",
    description = "Summary of diagnostic counts by severity",
    type = "string",
  },
  {
    name = "error",
    description = "Error message if the operation failed",
    type = "string",
    optional = true,
  },
}

---@param severity_filter string
---@return table
local function get_severity_levels(severity_filter)
  local levels = {}
  if severity_filter == "error" then
    levels = { vim.diagnostic.severity.ERROR }
  elseif severity_filter == "warn" then
    levels = { vim.diagnostic.severity.WARN }
  elseif severity_filter == "info" then
    levels = { vim.diagnostic.severity.INFO }
  elseif severity_filter == "hint" then
    levels = { vim.diagnostic.severity.HINT }
  else -- "all" or any other value
    levels = {
      vim.diagnostic.severity.ERROR,
      vim.diagnostic.severity.WARN,
      vim.diagnostic.severity.INFO,
      vim.diagnostic.severity.HINT,
    }
  end
  return levels
end

---@param diagnostics table[]
---@param max_results number
---@return table[]
local function limit_results(diagnostics, max_results)
  if #diagnostics <= max_results then
    return diagnostics
  end
  
  -- Prioritize errors, then warnings, then info, then hints
  table.sort(diagnostics, function(a, b)
    local severity_order = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4 }
    local a_order = severity_order[a.severity] or 5
    local b_order = severity_order[b.severity] or 5
    return a_order < b_order
  end)
  
  local result = {}
  for i = 1, math.min(max_results, #diagnostics) do
    table.insert(result, diagnostics[i])
  end
  return result
end

---@param diagnostics table[]
---@return table
local function create_summary(diagnostics)
  local summary = {
    total = #diagnostics,
    errors = 0,
    warnings = 0,
    info = 0,
    hints = 0,
  }
  
  for _, diag in ipairs(diagnostics) do
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
  
  return summary
end

---@type AvanteLLMToolFunc<{ path: string, severity?: string, include_source?: boolean, max_results?: number }>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete
  
  if not input.path then 
    return false, "path is required" 
  end
  
  if not on_complete then 
    return false, "on_complete is required" 
  end
  
  local severity_filter = input.severity or "all"
  local include_source = input.include_source ~= false -- default true
  local max_results = input.max_results or 50
  
  if on_log then 
    on_log("path: " .. input.path .. ", severity: " .. severity_filter .. ", max_results: " .. max_results)
  end
  
  local abs_path = Helpers.get_abs_path(input.path)
  if not Helpers.has_permission_to_access(abs_path) then 
    return false, "No permission to access path: " .. abs_path 
  end
  
  local Path = require("plenary.path")
  local path_obj = Path:new(abs_path)
  
  local all_diagnostics = {}
  
  if path_obj:is_dir() then
    -- Scan directory for files
    if on_log then on_log("Scanning directory: " .. abs_path) end
    
    -- Get all files in directory (recursively)
    local files = {}
    path_obj:walk(function(file_path, file_type)
      if file_type == "file" then
        local ext = vim.fn.fnamemodify(file_path, ":e")
        -- Only include common code file extensions
        local code_extensions = {
          "lua", "py", "js", "ts", "jsx", "tsx", "go", "rs", "c", "cpp", "h", "hpp",
          "java", "kt", "swift", "rb", "php", "cs", "fs", "ml", "hs", "elm", "dart",
          "vue", "svelte", "html", "css", "scss", "sass", "less", "json", "yaml", "yml",
          "toml", "xml", "md", "tex", "r", "jl", "nim", "zig", "v", "sol"
        }
        if vim.tbl_contains(code_extensions, ext) then
          table.insert(files, file_path)
        end
      end
    end)
    
    -- Limit number of files to scan to prevent overwhelming
    local max_files = 20
    if #files > max_files then
      if on_log then on_log("Too many files (" .. #files .. "), limiting to " .. max_files) end
      files = vim.list_slice(files, 1, max_files)
    end
    
    for _, file_path in ipairs(files) do
      local diagnostics = Utils.lsp.get_diagnostics_from_filepath(file_path)
      for _, diag in ipairs(diagnostics) do
        local enhanced_diag = {
          file = vim.fn.fnamemodify(file_path, ":~:."),
          line = diag.start_line,
          end_line = diag.end_line,
          message = diag.content,
          severity = diag.severity,
        }
        if include_source and diag.source then
          enhanced_diag.source = diag.source
        end
        table.insert(all_diagnostics, enhanced_diag)
      end
    end
  else
    -- Single file
    if not path_obj:exists() then
      return false, "File does not exist: " .. abs_path
    end
    
    local diagnostics = Utils.lsp.get_diagnostics_from_filepath(abs_path)
    for _, diag in ipairs(diagnostics) do
      local enhanced_diag = {
        file = vim.fn.fnamemodify(abs_path, ":~:."),
        line = diag.start_line,
        end_line = diag.end_line,
        message = diag.content,
        severity = diag.severity,
      }
      if include_source and diag.source then
        enhanced_diag.source = diag.source
      end
      table.insert(all_diagnostics, enhanced_diag)
    end
  end
  
  -- Filter by severity if specified
  if severity_filter ~= "all" then
    local filtered = {}
    for _, diag in ipairs(all_diagnostics) do
      if string.lower(diag.severity) == string.lower(severity_filter) then
        table.insert(filtered, diag)
      end
    end
    all_diagnostics = filtered
  end
  
  -- Limit results
  all_diagnostics = limit_results(all_diagnostics, max_results)
  
  -- Create summary
  local summary = create_summary(all_diagnostics)
  
  local result = {
    diagnostics = all_diagnostics,
    summary = summary,
  }
  
  local json_str = vim.json.encode(result)
  on_complete(json_str, nil)
end

return M