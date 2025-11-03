local Base = require("avante.llm_tools.base")
local Helpers = require("avante.llm_tools.helpers")
local Utils = require("avante.utils")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "get_project_diagnostics_summary"

M.description = "Get a summary of LSP diagnostics across the entire project. This provides an overview of code health, showing counts of errors, warnings, and other issues by file and type. Useful for understanding the overall state of the codebase."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "include_files",
      description = "Include per-file breakdown of diagnostics. Default: true",
      type = "boolean",
      optional = true,
    },
    {
      name = "min_severity",
      description = "Minimum severity to include: 'error', 'warn', 'info', 'hint' (default: 'hint')",
      type = "string",
      optional = true,
    },
    {
      name = "max_files",
      description = "Maximum number of files to scan. Default: 50",
      type = "number",
      optional = true,
    },
  },
  usage = {
    include_files = "Include detailed per-file breakdown",
    min_severity = "Minimum severity level to include",
    max_files = "Maximum number of files to scan",
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "summary",
    description = "Overall project diagnostics summary with counts by severity",
    type = "string",
  },
  {
    name = "files",
    description = "Per-file diagnostics breakdown (if requested)",
    type = "string",
    optional = true,
  },
  {
    name = "error",
    description = "Error message if the operation failed",
    type = "string",
    optional = true,
  },
}

---@param severity string
---@return number
local function get_severity_level(severity)
  local levels = {
    error = 1,
    warn = 2,
    info = 3,
    hint = 4,
  }
  return levels[string.lower(severity)] or 4
end

---@param severity string
---@param min_level number
---@return boolean
local function should_include_severity(severity, min_level)
  local current_level = get_severity_level(severity)
  return current_level <= min_level
end

---@type AvanteLLMToolFunc<{ include_files?: boolean, min_severity?: string, max_files?: number }>
function M.func(input, opts)
  local on_log = opts.on_log
  local on_complete = opts.on_complete
  
  if not on_complete then 
    return false, "on_complete is required" 
  end
  
  local include_files = input.include_files ~= false -- default true
  local min_severity = input.min_severity or "hint"
  local max_files = input.max_files or 50
  local min_severity_level = get_severity_level(min_severity)
  
  if on_log then 
    on_log("include_files: " .. tostring(include_files) .. ", min_severity: " .. min_severity .. ", max_files: " .. max_files)
  end
  
  -- Get project root
  local project_root = Utils.get_project_root()
  if not project_root then
    return false, "Not in a project directory"
  end
  
  if on_log then on_log("Scanning project: " .. project_root) end
  
  local Path = require("plenary.path")
  local root_path = Path:new(project_root)
  
  -- Get all code files in the project
  local files = {}
  root_path:walk(function(file_path, file_type)
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
        -- Skip common ignore patterns
        local rel_path = vim.fn.fnamemodify(file_path, ":~:.")
        if not rel_path:match("node_modules") and 
           not rel_path:match("%.git/") and
           not rel_path:match("target/") and
           not rel_path:match("build/") and
           not rel_path:match("dist/") and
           not rel_path:match("%.min%.") then
          table.insert(files, file_path)
        end
      end
    end
  end)
  
  -- Limit number of files
  if #files > max_files then
    if on_log then on_log("Found " .. #files .. " files, limiting to " .. max_files) end
    files = vim.list_slice(files, 1, max_files)
  end
  
  local total_summary = {
    total_files_scanned = #files,
    files_with_issues = 0,
    total_diagnostics = 0,
    errors = 0,
    warnings = 0,
    info = 0,
    hints = 0,
  }
  
  local file_details = {}
  
  for _, file_path in ipairs(files) do
    local diagnostics = Utils.lsp.get_diagnostics_from_filepath(file_path)
    
    -- Filter by minimum severity
    local filtered_diagnostics = {}
    for _, diag in ipairs(diagnostics) do
      if should_include_severity(diag.severity, min_severity_level) then
        table.insert(filtered_diagnostics, diag)
      end
    end
    
    if #filtered_diagnostics > 0 then
      total_summary.files_with_issues = total_summary.files_with_issues + 1
      total_summary.total_diagnostics = total_summary.total_diagnostics + #filtered_diagnostics
      
      local file_summary = {
        path = vim.fn.fnamemodify(file_path, ":~:."),
        total = #filtered_diagnostics,
        errors = 0,
        warnings = 0,
        info = 0,
        hints = 0,
      }
      
      for _, diag in ipairs(filtered_diagnostics) do
        if diag.severity == "ERROR" then
          total_summary.errors = total_summary.errors + 1
          file_summary.errors = file_summary.errors + 1
        elseif diag.severity == "WARN" then
          total_summary.warnings = total_summary.warnings + 1
          file_summary.warnings = file_summary.warnings + 1
        elseif diag.severity == "INFO" then
          total_summary.info = total_summary.info + 1
          file_summary.info = file_summary.info + 1
        elseif diag.severity == "HINT" then
          total_summary.hints = total_summary.hints + 1
          file_summary.hints = file_summary.hints + 1
        end
      end
      
      if include_files then
        table.insert(file_details, file_summary)
      end
    end
  end
  
  -- Sort files by total diagnostics (most problematic first)
  if include_files then
    table.sort(file_details, function(a, b) return a.total > b.total end)
  end
  
  local result = {
    summary = total_summary,
  }
  
  if include_files then
    result.files = file_details
  end
  
  local json_str = vim.json.encode(result)
  on_complete(json_str, nil)
end

return M