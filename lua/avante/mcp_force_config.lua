-- Avante.nvim MCP Force Configuration
-- This module provides automatic MCP tool prioritization when mcphub is available

local M = {}

-- Check if mcphub is available
local function is_mcphub_available()
  local compat = require("avante.mcphub_compat")
  return compat.is_available() and compat.has_active_servers()
end

-- Get automatic MCP configuration
function M.get_auto_mcp_config()
  if not is_mcphub_available() then
    return {}
  end
  
  -- When mcphub is available, automatically configure avante to use MCP tools
  return {
    -- System prompt that includes MCP tool usage instructions
    system_prompt = function()
      local mcphub = require("mcphub")
      local compat = require("avante.mcphub_compat")
      local base_prompt = compat.get_servers_prompt()
        local mcp_instructions = [[

IMPORTANT: You have access to MCP (Model Context Protocol) tools through the 'use_mcp_tool' function. 
When performing file operations, code editing, or system commands, you MUST use MCP tools instead of built-in tools.

Available MCP tool patterns:
- File operations: use server 'filesystem' with tools like 'read_file', 'write_file', 'list_directory'
- Shell commands: use server 'shell' with tool 'run_command' (if available)
- Always specify the correct server_name and tool_name when using 'use_mcp_tool'

Example usage:
```json
{
  "name": "use_mcp_tool",
  "input": {
    "server_name": "filesystem",
    "tool_name": "write_file",
    "tool_input": {
      "path": "example.txt",
      "content": "file content here"
    }
  }
}
```
]]
        return base_prompt .. mcp_instructions
      end
      return ""
    end,
    
    -- Custom tools that include MCP integration
    custom_tools = function()
      local tools = {}
      
      -- Add mcphub extension tool if available
      local mcp_ext_ok, mcp_ext = pcall(require, "mcphub.extensions.avante")
      if mcp_ext_ok and mcp_ext.mcp_tool then
        local mcp_tool = mcp_ext.mcp_tool()
        if mcp_tool then
          table.insert(tools, mcp_tool)
        end
      end
      
      return tools
    end,
    
    -- Behavior settings optimized for MCP usage
    behaviour = {
      auto_suggestions = false, -- Disable to avoid conflicts with MCP tools
      auto_apply_diff_after_generation = false,
      support_paste_from_clipboard = true,
      minimize_diff = true,
      auto_approve_tool_permissions = function(tool_name, tool_input)
        -- Auto-approve MCP tools for current project files
        if tool_name == "use_mcp_tool" then
          local server_name = tool_input.server_name
          local tool_name_mcp = tool_input.tool_name
          local tool_input_mcp = tool_input.tool_input or {}
          
          -- Auto-approve filesystem operations in current project
          if server_name == "filesystem" and tool_input_mcp.path then
            local path = tool_input_mcp.path
            local cwd = vim.fn.getcwd()
            if path:match("^" .. vim.pesc(cwd)) then
              return true
            end
          end
        end
        return false -- Show permission prompts for other operations
      end,
    },
  }
end

-- Setup function that automatically applies MCP configuration
function M.setup(user_config)
  user_config = user_config or {}
  
  if is_mcphub_available() then
    local auto_config = M.get_auto_mcp_config()
    
    -- Merge configurations with user config taking precedence
    local merged_config = vim.tbl_deep_extend("force", auto_config, user_config)
    
    -- Ensure system_prompt is properly merged
    if user_config.system_prompt then
      local auto_system_prompt = auto_config.system_prompt
      local user_system_prompt = user_config.system_prompt
      
      merged_config.system_prompt = function()
        local auto_prompt = type(auto_system_prompt) == "function" and auto_system_prompt() or auto_system_prompt or ""
        local user_prompt = type(user_system_prompt) == "function" and user_system_prompt() or user_system_prompt or ""
        return user_prompt .. "\n\n" .. auto_prompt
      end
    end
    
    -- Ensure custom_tools are properly merged
    if user_config.custom_tools then
      local auto_custom_tools = auto_config.custom_tools
      local user_custom_tools = user_config.custom_tools
      
      merged_config.custom_tools = function()
        local auto_tools = type(auto_custom_tools) == "function" and auto_custom_tools() or auto_custom_tools or {}
        local user_tools = type(user_custom_tools) == "function" and user_custom_tools() or user_custom_tools or {}
        
        -- Ensure both are arrays
        if type(auto_tools) ~= "table" then auto_tools = {} end
        if type(user_tools) ~= "table" then user_tools = {} end
        
        local merged_tools = {}
        for _, tool in ipairs(user_tools) do
          table.insert(merged_tools, tool)
        end
        for _, tool in ipairs(auto_tools) do
          table.insert(merged_tools, tool)
        end
        
        return merged_tools
      end
    end
    
    return merged_config
  else
    -- Return user config as-is when mcphub is not available
    return user_config
  end
end

-- Status check function
function M.status()
  local mcphub_available = is_mcphub_available()
  local status = {
    mcphub_available = mcphub_available,
    auto_mcp_enabled = mcphub_available,
    message = mcphub_available and "MCP tools are automatically prioritized" or "mcphub.nvim not available or no active servers"
  }
  
  if mcphub_available then
    local compat = require("avante.mcphub_compat")
    local servers = compat.get_active_servers()
    status.active_servers = vim.tbl_map(function(server) return server.name or server.id or "unknown" end, servers)
    status.server_count = compat.get_server_count()
  end
  
  return status
end

return M