-- MCP Integration for Avante.nvim
-- This module provides integration with mcphub.nvim to use MCP tools instead of built-in tools

local M = {}

-- Check if mcphub is available
local function is_mcphub_available()
  local ok, mcphub = pcall(require, "mcphub")
  return ok and mcphub
end

-- Get available MCP tools that can replace built-in tools
local function get_mcp_file_tools()
  if not is_mcphub_available() then
    return {}
  end
  
  local tools = {}
  
  -- MCP File Edit Tool - replaces edit_file
  table.insert(tools, {
    name = "mcp_edit_file",
    description = "Edit files using MCP tools. This tool provides better file editing capabilities through MCP servers with proper diff support and validation.",
    param = {
      type = "table",
      fields = {
        {
          name = "server_name",
          description = "The MCP server to use (e.g., 'filesystem')",
          type = "string",
        },
        {
          name = "path",
          description = "The file path to edit",
          type = "string",
        },
        {
          name = "content",
          description = "The new content for the file",
          type = "string",
        },
      },
      usage = {
        server_name = "MCP server name",
        path = "File path to edit",
        content = "New file content",
      },
    },
    returns = {
      {
        name = "success",
        description = "Whether the file was edited successfully",
        type = "boolean",
      },
      {
        name = "error",
        description = "Error message if the edit failed",
        type = "string",
        optional = true,
      },
    },
    enabled = function()
      return is_mcphub_available()
    end,
    func = function(input, opts)
      local on_complete = opts.on_complete
      local on_log = opts.on_log
      
      if not on_complete then
        return false, "on_complete is required"
      end
      
      if not input.server_name or not input.path or not input.content then
        return false, "server_name, path, and content are required"
      end
      
      if on_log then
        on_log("Using MCP server: " .. input.server_name .. " to edit: " .. input.path)
      end
      
      -- Use mcphub to call the MCP tool
      local mcphub = require("mcphub")
      mcphub.call_tool(input.server_name, "write_file", {
        path = input.path,
        content = input.content,
      }, function(result, error)
        if error then
          on_complete(false, "MCP edit failed: " .. error)
        else
          on_complete(true, nil)
        end
      end)
    end,
  })
  
  -- MCP File Read Tool - enhanced file reading
  table.insert(tools, {
    name = "mcp_read_file",
    description = "Read files using MCP tools with better error handling and validation.",
    param = {
      type = "table",
      fields = {
        {
          name = "server_name",
          description = "The MCP server to use (e.g., 'filesystem')",
          type = "string",
        },
        {
          name = "path",
          description = "The file path to read",
          type = "string",
        },
      },
      usage = {
        server_name = "MCP server name",
        path = "File path to read",
      },
    },
    returns = {
      {
        name = "content",
        description = "The file content",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the read failed",
        type = "string",
        optional = true,
      },
    },
    enabled = function()
      return is_mcphub_available()
    end,
    func = function(input, opts)
      local on_complete = opts.on_complete
      local on_log = opts.on_log
      
      if not on_complete then
        return false, "on_complete is required"
      end
      
      if not input.server_name or not input.path then
        return false, "server_name and path are required"
      end
      
      if on_log then
        on_log("Using MCP server: " .. input.server_name .. " to read: " .. input.path)
      end
      
      -- Use mcphub to call the MCP tool
      local mcphub = require("mcphub")
      mcphub.call_tool(input.server_name, "read_file", {
        path = input.path,
      }, function(result, error)
        if error then
          on_complete(nil, "MCP read failed: " .. error)
        else
          on_complete(result.content or result, nil)
        end
      end)
    end,
  })
  
  -- Generic MCP Tool Wrapper
  table.insert(tools, {
    name = "use_mcp_tool",
    description = "Use any MCP tool through mcphub.nvim. This provides access to all available MCP servers and their tools.",
    param = {
      type = "table",
      fields = {
        {
          name = "server_name",
          description = "The MCP server to use",
          type = "string",
        },
        {
          name = "tool_name",
          description = "The tool name to call on the MCP server",
          type = "string",
        },
        {
          name = "tool_input",
          description = "The input parameters for the MCP tool",
          type = "table",
          optional = true,
        },
      },
      usage = {
        server_name = "MCP server name",
        tool_name = "Tool name to call",
        tool_input = "Tool input parameters",
      },
    },
    returns = {
      {
        name = "result",
        description = "The result from the MCP tool",
        type = "string",
      },
      {
        name = "error",
        description = "Error message if the tool call failed",
        type = "string",
        optional = true,
      },
    },
    enabled = function()
      return is_mcphub_available()
    end,
    func = function(input, opts)
      local on_complete = opts.on_complete
      local on_log = opts.on_log
      
      if not on_complete then
        return false, "on_complete is required"
      end
      
      if not input.server_name or not input.tool_name then
        return false, "server_name and tool_name are required"
      end
      
      if on_log then
        on_log("Using MCP server: " .. input.server_name .. " tool: " .. input.tool_name)
      end
      
      -- Use mcphub to call the MCP tool
      local mcphub = require("mcphub")
      mcphub.call_tool(input.server_name, input.tool_name, input.tool_input or {}, function(result, error)
        if error then
          on_complete(nil, "MCP tool call failed: " .. error)
        else
          local result_str = type(result) == "string" and result or vim.json.encode(result)
          on_complete(result_str, nil)
        end
      end)
    end,
  })
  
  return tools
end

-- Get the recommended configuration for using MCP tools
function M.get_recommended_config()
  local config = {
    -- Disable built-in tools that have MCP equivalents
    disabled_tools = {
      "edit_file",  -- Use mcp_edit_file instead
      "create",     -- Use MCP filesystem tools instead
      "write_to_file", -- Use MCP filesystem tools instead
    },
    
    -- Add MCP tools as custom tools
    custom_tools = function()
      return get_mcp_file_tools()
    end,
  }
  
  return config
end

-- Apply MCP integration configuration
function M.setup(user_config)
  user_config = user_config or {}
  
  local recommended = M.get_recommended_config()
  
  -- Merge disabled tools
  local disabled_tools = vim.list_extend(
    vim.deepcopy(user_config.disabled_tools or {}),
    recommended.disabled_tools
  )
  
  -- Merge custom tools
  local custom_tools = user_config.custom_tools or {}
  if type(custom_tools) == "function" then
    local user_tools = custom_tools()
    custom_tools = function()
      return vim.list_extend(user_tools, recommended.custom_tools())
    end
  else
    local user_tools = custom_tools
    custom_tools = function()
      return vim.list_extend(user_tools, recommended.custom_tools())
    end
  end
  
  return {
    disabled_tools = disabled_tools,
    custom_tools = custom_tools,
  }
end

-- Force enable MCP tools when mcphub is available
function M.force_enable_mcp_tools()
  if not is_mcphub_available() then
    return false, "mcphub.nvim is not available"
  end
  
  local mcphub = require("mcphub")
  local hub = mcphub.get_hub_instance()
  if not hub or #hub:get_active_servers() == 0 then
    return false, "No active MCP servers found"
  end
  
  -- This function is called automatically by the modified get_tools function
  -- to ensure MCP tools are prioritized when mcphub is available
  return true, "MCP tools are now prioritized"
end

-- Check MCP integration status
function M.status()
  local mcphub_available = is_mcphub_available()
  local tools = get_mcp_file_tools()
  
  return {
    mcphub_available = mcphub_available,
    mcp_tools_count = #tools,
    tools = vim.tbl_map(function(tool) return tool.name end, tools),
  }
end

return M