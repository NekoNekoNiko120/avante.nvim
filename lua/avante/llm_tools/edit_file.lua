local Base = require("avante.llm_tools.base")
local Providers = require("avante.providers")
local Utils = require("avante.utils")
local curl = require("plenary.curl")
local Highlights = require("avante.highlights")

local PRIORITY = (vim.hl or vim.highlight).priorities.user
local NAMESPACE = vim.api.nvim_create_namespace("avante-edit-preview")

-- Store original content for preview reversion
local preview_state = {}

-- LCS-based diff algorithm for better change detection
local function compute_lcs(original_lines, new_lines)
  local m, n = #original_lines, #new_lines
  local lcs = {}
  
  -- Initialize LCS table
  for i = 0, m do
    lcs[i] = {}
    for j = 0, n do
      lcs[i][j] = 0
    end
  end
  
  -- Fill LCS table
  for i = 1, m do
    for j = 1, n do
      if original_lines[i] == new_lines[j] then
        lcs[i][j] = lcs[i-1][j-1] + 1
      else
        lcs[i][j] = math.max(lcs[i-1][j], lcs[i][j-1])
      end
    end
  end
  
  return lcs
end

-- Generate diff operations from LCS
local function generate_diff_ops(original_lines, new_lines, lcs)
  local ops = {}
  local i, j = #original_lines, #new_lines
  
  while i > 0 or j > 0 do
    if i > 0 and j > 0 and original_lines[i] == new_lines[j] then
      -- Lines are equal
      table.insert(ops, 1, {type = "equal", orig_idx = i, new_idx = j})
      i = i - 1
      j = j - 1
    elseif j > 0 and (i == 0 or lcs[i][j-1] >= lcs[i-1][j]) then
      -- Line added
      table.insert(ops, 1, {type = "add", new_idx = j, content = new_lines[j]})
      j = j - 1
    else
      -- Line deleted
      table.insert(ops, 1, {type = "delete", orig_idx = i, content = original_lines[i]})
      i = i - 1
    end
  end
  
  return ops
end

-- Function to highlight the edit preview with proper diff display
local function highlight_edit_preview(bufnr, original_lines, new_lines)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  
  -- Ensure we have valid line arrays
  original_lines = original_lines or {}
  new_lines = new_lines or {}
  
  -- If no original content, highlight everything as new
  if #original_lines == 0 then
    for i, line in ipairs(new_lines) do
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, i - 1, 0, {
        hl_group = Highlights.INCOMING,
        hl_eol = true,
        end_col = #line,
        priority = PRIORITY,
        hl_mode = "combine",
      })
    end
    return
  end
  
  -- Compute LCS and generate diff operations
  local lcs = compute_lcs(original_lines, new_lines)
  local diff_ops = generate_diff_ops(original_lines, new_lines, lcs)
  
  local deleted_lines = {}
  
  -- Process diff operations
  for _, op in ipairs(diff_ops) do
    if op.type == "add" then
      -- Highlight added lines
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, op.new_idx - 1, 0, {
        hl_group = Highlights.INCOMING,
        hl_eol = true,
        end_col = #op.content,
        priority = PRIORITY,
        hl_mode = "combine",
      })
    elseif op.type == "delete" then
      -- Collect deleted lines
      table.insert(deleted_lines, { { "- " .. op.content, Highlights.TO_BE_DELETED_WITHOUT_STRIKETHROUGH } })
    end
    -- Equal lines are not highlighted (they remain unchanged)
  end
  
  -- Show deleted lines as virtual text at the end
  if #deleted_lines > 0 then
    local insert_line = math.max(0, #new_lines)
    vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, insert_line, 0, {
      virt_lines = deleted_lines,
      priority = PRIORITY,
      hl_eol = true,
      hl_mode = "combine",
    })
  end
end

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "edit_file"

M.enabled = function()
  return require("avante.config").mode == "agentic" and require("avante.config").behaviour.enable_fastapply
end

M.description =
  "Use this tool to edit an EXISTING file. This tool can ONLY modify files that already exist. For creating new files, use the 'create' tool instead.\n\nIMPORTANT: This tool requires the target file to exist. If you get a 'No such file or directory' error, the file doesn't exist - use the 'create' tool to create it first.\n\nThis will show a preview of changes before applying them. You should make it clear what the edit is, while minimizing unchanged code.\nWhen writing the edit, specify each edit in sequence, with the special comment // ... existing code ... to represent unchanged code in between edited lines.\n\nFor example:\n\n// ... existing code ...\nFIRST_EDIT\n// ... existing code ...\nSECOND_EDIT\n// ... existing code ...\nTHIRD_EDIT\n// ... existing code ...\n\nYou should bias towards repeating as few lines of the original file as possible to convey the change.\nBut, each edit should contain sufficient context of unchanged lines around the code you're editing to resolve ambiguity.\nDO NOT omit spans of pre-existing code (or comments) without using the // ... existing code ... comment to indicate its absence.\nIf you plan on deleting a section, you must provide context before and after to delete it.\nALWAYS make all edits to a file in a single edit_file call instead of multiple calls to the same file."

---@type AvanteLLMToolParam
M.param = {
  type = "table",
  fields = {
    {
      name = "path",
      description = "The target file path to modify.",
      type = "string",
    },
    {
      name = "instructions",
      type = "string",
      description = "A single sentence instruction describing what you are going to do for the sketched edit. This is used to assist the less intelligent model in applying the edit. Use the first person to describe what you are going to do. Use it to disambiguate uncertainty in the edit.",
    },
    {
      name = "code_edit",
      type = "string",
      description = "Specify ONLY the precise lines of code that you wish to edit. NEVER specify or write out unchanged code. Instead, represent all unchanged code using the comment of the language you're editing in - example: // ... existing code ...",
    },
  },
}

---@type AvanteLLMToolReturn[]
M.returns = {
  {
    name = "success",
    description = "Whether the file was edited successfully",
    type = "boolean",
  },
  {
    name = "error",
    description = "Error message if the file could not be edited",
    type = "string",
    optional = true,
  },
}

-- Function to show edit preview using Morph API
local function show_edit_preview(input, opts, callback)
  local Helpers = require("avante.llm_tools.helpers")
  local abs_path = Helpers.get_abs_path(input.path)
  
  -- Check if file exists first
  local Path = require("plenary.path")
  if not Path:new(abs_path):exists() then
    callback(false, string.format(
      "File '%s' does not exist. Use 'create' tool to create new files, not 'edit_file'.\nFull path: %s",
      input.path,
      abs_path
    ))
    return
  end
  
  -- Check if it's a directory
  if vim.fn.isdirectory(abs_path) == 1 then
    callback(false, string.format("'%s' is a directory, not a file", input.path))
    return
  end
  
  -- Get original content
  local lines, read_error = Utils.read_file_from_buf_or_disk(input.path)
  if read_error then
    callback(false, "Failed to read file: " .. input.path .. " - " .. read_error)
    return
  end
  
  if lines and #lines > 0 then
    if lines[#lines] == "" then lines = vim.list_slice(lines, 0, #lines - 1) end
  end
  local original_code = table.concat(lines or {}, "\n")
  
  -- Store original content for reversion
  preview_state[input.path] = {
    original_lines = lines or {},
    bufnr = nil
  }
  
  -- Get buffer
  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then
    callback(false, err)
    return
  end
  preview_state[input.path].bufnr = bufnr
  
  -- Call Morph API to get preview
  local provider = Providers["morph"]
  if not provider or not provider.is_env_set() then
    callback(false, "Morph provider not available for preview")
    return
  end
  
  local provider_conf = Providers.parse_config(provider)
  local body = {
    model = provider_conf.model,
    messages = {
      {
        role = "user",
        content = "<instructions>"
          .. input.instructions
          .. "</instructions>\n<code>"
          .. original_code
          .. "</code>\n<update>"
          .. input.code_edit
          .. "</update>",
      },
    },
  }
  
  local headers = {
    ["Content-Type"] = "application/json",
  }
  
  if Providers.env.require_api_key(provider_conf) then
    local api_key = provider.parse_api_key()
    if not api_key or api_key == "" then
      callback(false, "API key not found or empty")
      return
    end
    headers["Authorization"] = "Bearer " .. api_key
  end
  
  local url = Utils.url_join(provider_conf.endpoint, "/chat/completions")
  
  curl.post(url, {
    headers = headers,
    body = vim.json.encode(body),
    timeout = 120000,
    callback = vim.schedule_wrap(function(response)
      if response.status >= 400 then
        callback(false, "Preview generation failed: " .. (response.body or "Unknown error"))
        return
      end
      
      local ok_, jsn = pcall(vim.json.decode, response.body or "")
      if not ok_ or not jsn.choices or not jsn.choices[1] or not jsn.choices[1].message then
        callback(false, "Invalid preview response")
        return
      end
      
      local merged_code = jsn.choices[1].message.content
      if not merged_code or merged_code == "" then
        callback(false, "Empty preview content")
        return
      end
      
      -- Apply preview to buffer with diff highlighting
      local new_lines = vim.split(merged_code, "\n")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
      
      -- Add diff highlighting
      highlight_edit_preview(bufnr, lines or {}, new_lines)
      
      callback(true, nil)
    end)
  })
end

-- Function to revert preview changes
local function revert_preview(file_path)
  local state = preview_state[file_path]
  if not state or not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end
  
  -- Restore original content
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, state.original_lines)
  
  -- Clear highlighting
  vim.api.nvim_buf_clear_namespace(state.bufnr, NAMESPACE, 0, -1)
  
  -- Clean up state
  preview_state[file_path] = nil
end

-- Extract the actual edit logic into a separate function
local function perform_edit(input, opts, on_complete)
  local provider = Providers["morph"]
  if not provider then 
    on_complete(false, "morph provider not found")
    return
  end
  if not provider.is_env_set() then 
    on_complete(false, "morph provider not set")
    return
  end

  -- Double-check file existence (in case preview was skipped)
  local Helpers = require("avante.llm_tools.helpers")
  local abs_path = Helpers.get_abs_path(input.path)
  local Path = require("plenary.path")
  
  if not Path:new(abs_path):exists() then
    on_complete(false, string.format(
      "File '%s' does not exist. Use 'create' tool to create new files, not 'edit_file'.\nFull path: %s",
      input.path,
      abs_path
    ))
    return
  end

  --- if input.path is a directory, return false
  if vim.fn.isdirectory(abs_path) == 1 then 
    on_complete(false, "path is a directory")
    return
  end

  -- Pre-compute absolute path and other values outside of callback
  local Helpers = require("avante.llm_tools.helpers")
  local abs_path = Helpers.get_abs_path(input.path)
  if not Helpers.has_permission_to_access(abs_path) then 
    on_complete(false, "No permission to access path: " .. abs_path)
    return
  end
  
  local bufnr, err = Helpers.get_bufnr(abs_path)
  if err then 
    on_complete(false, err)
    return
  end

  local lines, read_error = Utils.read_file_from_buf_or_disk(input.path)
  if read_error then
    on_complete(false, "Failed to read file: " .. input.path .. " - " .. read_error)
    return
  end

  if lines and #lines > 0 then
    if lines[#lines] == "" then lines = vim.list_slice(lines, 0, #lines - 1) end
  end
  local original_code = table.concat(lines or {}, "\n")

  local provider_conf = Providers.parse_config(provider)

  local body = {
    model = provider_conf.model,
    messages = {
      {
        role = "user",
        content = "<instructions>"
          .. input.instructions
          .. "</instructions>\n<code>"
          .. original_code
          .. "</code>\n<update>"
          .. input.code_edit
          .. "</update>",
      },
    },
  }

  -- Prepare headers
  local headers = {
    ["Content-Type"] = "application/json",
  }
  
  -- Add authorization header if available
  if Providers.env.require_api_key(provider_conf) then
    local api_key = provider.parse_api_key()
    if not api_key or api_key == "" then
      on_complete(false, "API key not found or empty")
      return
    end
    headers["Authorization"] = "Bearer " .. api_key
  end

  local url = Utils.url_join(provider_conf.endpoint, "/chat/completions")
  
  curl.post(url, {
    headers = headers,
    body = vim.json.encode(body),
    timeout = 120000, -- 120 seconds
    callback = vim.schedule_wrap(function(response)
      
      if response.status >= 400 then
        -- 检查curl常见的错误码
        local full_error = "HTTP request failed: "
          .. "Status: " .. response.status
          .. "\nEndpoint: " .. url
          .. "\nModel: " .. provider_conf.model

        if response.body and response.body ~= "" then 
          full_error = full_error .. "\nResponse: " .. response.body 
        end

        on_complete(false, full_error)
        return
      end

      local response_body = response.body or ""
      if response_body == "" then
        on_complete(false, "Empty response from server")
        return
      end

      local ok_, jsn = pcall(vim.json.decode, response_body)
      if not ok_ then
        on_complete(false, "Failed to parse JSON response: " .. response_body)
        return
      end

      if jsn.error then
        if type(jsn.error) == "table" and jsn.error.message then
          on_complete(false, jsn.error.message or vim.inspect(jsn.error))
        else
          on_complete(false, vim.inspect(jsn.error))
        end
        return
      end

      if not jsn.choices or not jsn.choices[1] or not jsn.choices[1].message then
        on_complete(false, "Invalid response format")
        return
      end

      -- Morph API returns the complete merged code, so we write it directly to the file
      local merged_code = jsn.choices[1].message.content
      
      if not merged_code or merged_code == "" then
        on_complete(false, "Morph API returned empty content")
        return
      end
      
      -- Split the merged code into lines
      local new_lines = vim.split(merged_code, "\n")
      
      -- Replace the entire buffer content
      local success, set_lines_err = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, new_lines)
      if not success then
        on_complete(false, "Failed to update buffer: " .. (set_lines_err or "unknown error"))
        return
      end
      
      -- Mark the buffer as modified and save it
      local save_success, save_err = pcall(function()
        vim.api.nvim_buf_call(bufnr, function() 
          vim.cmd("noautocmd write!") 
        end)
      end)
      
      if not save_success then
        on_complete(false, "Failed to save file: " .. (save_err or "unknown error"))
        return
      end
      
      -- Clean up preview state on successful completion
      if preview_state[input.path] then
        vim.api.nvim_buf_clear_namespace(preview_state[input.path].bufnr, NAMESPACE, 0, -1)
        preview_state[input.path] = nil
      end
      
      on_complete(true, nil)
    end)
  })
end

---@type AvanteLLMToolFunc<{ path: string, instructions: string, code_edit: string }>
M.func = function(input, opts)
  if opts.streaming then return false, "streaming not supported" end
  if not input.path then return false, "path not provided" end
  if not input.instructions then input.instructions = "" end
  if not input.code_edit then return false, "code_edit not provided" end
  local on_complete = opts.on_complete
  if not on_complete then return false, "on_complete not provided" end
  
  -- Early file existence check
  local Helpers = require("avante.llm_tools.helpers")
  local abs_path = Helpers.get_abs_path(input.path)
  local Path = require("plenary.path")
  
  if not Path:new(abs_path):exists() then
    return false, string.format(
      "File '%s' does not exist. Use 'create' tool to create new files, not 'edit_file'.\nFull path: %s",
      input.path,
      abs_path
    )
  end
  
  if vim.fn.isdirectory(abs_path) == 1 then
    return false, string.format("'%s' is a directory, not a file", input.path)
  end
  
  -- Show diff preview before confirmation
  local Config = require("avante.config")
  
  -- First, show a preview of the changes
  show_edit_preview(input, opts, function(preview_success, preview_error)
    if not preview_success then
      on_complete(false, preview_error or "Failed to generate preview")
      return
    end
    
    -- Create confirmation message with preview info
    local confirmation_message = string.format(
      "Apply edit to '%s'?\n\nInstructions: %s\n\nPreview is shown in the editor. Use diff navigation keys to review changes.",
      input.path,
      input.instructions
    )
    
    -- Force confirmation for edit_file regardless of global auto_approve setting
    local original_auto_approve = Config.behaviour.auto_approve_tool_permissions
    Config.behaviour.auto_approve_tool_permissions = false
    
    Helpers.confirm(confirmation_message, function(confirmed)
      -- Restore original auto_approve setting
      Config.behaviour.auto_approve_tool_permissions = original_auto_approve
      
      if confirmed then
        -- Apply the actual edit
        perform_edit(input, opts, on_complete)
      else
        -- Revert preview changes
        revert_preview(input.path)
        on_complete(false, "File edit cancelled by user")
      end
    end, nil, opts.session_ctx, "edit_file")
  end)
end

return M
