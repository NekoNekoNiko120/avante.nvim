-- Tool Redirector for Avante.nvim
-- This module handles redirection of disabled built-in tools to MCP equivalents

local M = {}

-- Mapping of disabled tools to MCP equivalents
local TOOL_REDIRECTIONS = {
  edit_file = {
    mcp_server = "filesystem",
    mcp_tool = "write_file",
    transform_input = function(input)
      return {
        path = input.path,
        content = input.file_text or input.content or input.new_str or "",
      }
    end,
  },
  
  create_file = {
    mcp_server = "filesystem", 
    mcp_tool = "write_file",
    transform_input = function(input)
      return {
        path = input.path,
        content = input.content or input.file_text or "",
      }
    end,
  },
  
  write_to_file = {
    mcp_server = "filesystem",
    mcp_tool = "write_file", 
    transform_input = function(input)
      return {
        path = input.path,
        content = input.content or input.file_text or "",
      }
    end,
  },
  
  read_file = {
    mcp_server = "filesystem",
    mcp_tool = "read_file",
    transform_input = function(input)
      return {
        path = input.path,
      }
    end,
  },
  
  list_files = {
    mcp_server = "filesystem",
    mcp_tool = "list_directory",
    transform_input = function(input)
      return {
        path = input.path or ".",
      }
    end,
  },
  
  search_files = {
    mcp_server = "filesystem", 
    mcp_tool = "search_files",
    transform_input = function(input)
      return {
        pattern = input.pattern or input.query,
        path = input.path or ".",
      }
    end,
  },
  
  delete_file = {
    mcp_server = "filesystem",
    mcp_tool = "delete_file",
    transform_input = function(input)
      return {
        path = input.path,
      }
    end,
  },
  
  rename_file = {
    mcp_server = "filesystem",
    mcp_tool = "move_file", 
    transform_input = function(input)
      return {
        source = input.old_path or input.source_path,
        destination = input.new_path or input.destination_path,
      }
    end,
  },
  
  create_dir = {
    mcp_server = "filesystem",
    mcp_tool = "create_directory",
    transform_input = function(input)
      return {
        path = input.path,
      }
    end,
  },
  
  bash = {
    mcp_server = "shell",
    mcp_tool = "run_command",
    transform_input = function(input)
      return {
        command = input.command,
        working_directory = input.path or input.cwd,
      }
    end,
  },
}

-- Check if mcphub is available
local function is_mcphub_available()
  local ok, _ = pcall(require, "mcphub")
  return ok
end

-- Get the default MCP server for a tool type
local function get_default_server(tool_name)
  local redirection = TOOL_REDIRECTIONS[tool_name]
  if not redirection then
    return nil
  end
  
  -- Check if the specified server is available
  if is_mcphub_available() then
    local mcphub = require("mcphub")
    local hub = mcphub.get_hub_instance()
    if hub then
      local servers = hub:get_active_servers()
      for _, server in ipairs(servers) do
        if server.name == redirection.mcp_server then
          return redirection.mcp_server
        end
      end
      
      -- Fallback to first available server that might support the tool
      if #servers > 0 then
        return servers[1].name
      end
    end
  end
  
  return nil
end

-- Redirect a tool use to MCP equivalent
function M.redirect_tool_use(tool_use)
  local redirection = TOOL_REDIRECTIONS[tool_use.name]
  if not redirection then
    return nil, "No redirection available for tool: " .. tool_use.name
  end
  
  if not is_mcphub_available() then
    return nil, "mcphub.nvim is not available for redirection"
  end
  
  local server_name = get_default_server(tool_use.name)
  if not server_name then
    return nil, "No suitable MCP server available for tool: " .. tool_use.name
  end
  
  local transformed_input = redirection.transform_input(tool_use.input or {})
  
  local redirected_tool_use = {
    name = "use_mcp_tool",
    input = {
      server_name = server_name,
      tool_name = redirection.mcp_tool,
      tool_input = transformed_input,
    }
  }
  
  return redirected_tool_use, nil
end

-- Check if a tool should be redirected
function M.should_redirect(tool_name)
  local Config = require("avante.config")
  return vim.tbl_contains(Config.disabled_tools, tool_name) and TOOL_REDIRECTIONS[tool_name] ~= nil
end

-- Get list of tools that can be redirected
function M.get_redirectable_tools()
  return vim.tbl_keys(TOOL_REDIRECTIONS)
end

-- Get redirection info for a tool
function M.get_redirection_info(tool_name)
  return TOOL_REDIRECTIONS[tool_name]
end

return M