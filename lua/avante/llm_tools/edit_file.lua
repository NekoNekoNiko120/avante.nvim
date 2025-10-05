local Base = require("avante.llm_tools.base")
local Providers = require("avante.providers")
local Utils = require("avante.utils")
local curl = require("plenary.curl")

---@class AvanteLLMTool
local M = setmetatable({}, Base)

M.name = "edit_file"

M.enabled = function()
  return require("avante.config").mode == "agentic" and require("avante.config").behaviour.enable_fastapply
end

M.description =
  "Use this tool to propose an edit to an existing file.\n\nThis will be read by a less intelligent model, which will quickly apply the edit. You should make it clear what the edit is, while also minimizing the unchanged code you write.\nWhen writing the edit, you should specify each edit in sequence, with the special comment // ... existing code ... to represent unchanged code in between edited lines.\n\nFor example:\n\n// ... existing code ...\nFIRST_EDIT\n// ... existing code ...\nSECOND_EDIT\n// ... existing code ...\nTHIRD_EDIT\n// ... existing code ...\n\nYou should still bias towards repeating as few lines of the original file as possible to convey the change.\nBut, each edit should contain sufficient context of unchanged lines around the code you're editing to resolve ambiguity.\nDO NOT omit spans of pre-existing code (or comments) without using the // ... existing code ... comment to indicate its absence. If you omit the existing code comment, the model may inadvertently delete these lines.\nIf you plan on deleting a section, you must provide context before and after to delete it. If the initial code is ```code \\n Block 1 \\n Block 2 \\n Block 3 \\n code```, and you want to remove Block 2, you would output ```// ... existing code ... \\n Block 1 \\n  Block 3 \\n // ... existing code ...```.\nMake sure it is clear what the edit should be, and where it should be applied.\nALWAYS make all edits to a file in a single edit_file instead of multiple edit_file calls to the same file. The apply model can handle many distinct edits at once."

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

---@type AvanteLLMToolFunc<{ path: string, instructions: string, code_edit: string }>
M.func = function(input, opts)
  if opts.streaming then return false, "streaming not supported" end
  if not input.path then return false, "path not provided" end
  if not input.instructions then input.instructions = "" end
  if not input.code_edit then return false, "code_edit not provided" end
  local on_complete = opts.on_complete
  if not on_complete then return false, "on_complete not provided" end
  
  local provider = Providers["morph"]
  if not provider then return false, "morph provider not found" end
  if not provider.is_env_set() then return false, "morph provider not set" end

  --- if input.path is a directory, return false
  if vim.fn.isdirectory(input.path) == 1 then return false, "path is a directory" end

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
      
      on_complete(true, nil)
    end)
  })
end

return M
