-- MCP Hub Compatibility Layer
-- This module provides a consistent API for different versions of mcphub.nvim

local M = {}

-- Check if mcphub is available
function M.is_available()
  local ok, mcphub = pcall(require, "mcphub")
  return ok and mcphub
end

-- Get mcphub instance
function M.get_mcphub()
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then
    return nil
  end
  return mcphub
end

-- Get hub instance with fallback methods
function M.get_hub_instance()
  local mcphub = M.get_mcphub()
  if not mcphub then
    return nil
  end
  
  -- Try different methods to get hub instance
  if mcphub.get_hub_instance then
    return mcphub.get_hub_instance()
  elseif mcphub.hub then
    return mcphub.hub
  elseif mcphub.get_instance then
    return mcphub.get_instance()
  end
  
  return nil
end

-- Get active servers with fallback methods
function M.get_active_servers()
  local mcphub = M.get_mcphub()
  if not mcphub then
    return {}
  end
  
  local servers = {}
  
  -- Method 1: Through hub instance
  local hub = M.get_hub_instance()
  if hub then
    if hub.get_active_servers then
      servers = hub:get_active_servers() or {}
    elseif hub.get_servers then
      servers = hub:get_servers() or {}
    elseif hub.list_servers then
      servers = hub:list_servers() or {}
    elseif hub.servers then
      servers = hub.servers or {}
    end
  end
  
  -- Method 2: Direct access to mcphub
  if #servers == 0 then
    if mcphub.get_active_servers then
      servers = mcphub.get_active_servers() or {}
    elseif mcphub.get_servers then
      servers = mcphub.get_servers() or {}
    elseif mcphub.list_servers then
      servers = mcphub.list_servers() or {}
    elseif mcphub.servers then
      servers = mcphub.servers or {}
    end
  end
  
  -- Ensure servers is an array
  if type(servers) == "table" and not vim.islist(servers) then
    local server_list = {}
    for name, server in pairs(servers) do
      if type(server) == "table" then
        server.name = server.name or name
        table.insert(server_list, server)
      else
        table.insert(server_list, { name = name, id = name })
      end
    end
    servers = server_list
  end
  
  return servers or {}
end

-- Get server count
function M.get_server_count()
  local servers = M.get_active_servers()
  return #servers
end

-- Check if any servers are active
function M.has_active_servers()
  return M.get_server_count() > 0
end

-- Get servers prompt with fallback
function M.get_servers_prompt()
  local mcphub = M.get_mcphub()
  if not mcphub then
    return ""
  end
  
  local hub = M.get_hub_instance()
  if hub then
    if hub.get_active_servers_prompt then
      return hub:get_active_servers_prompt() or ""
    elseif hub.get_servers_prompt then
      return hub:get_servers_prompt() or ""
    elseif hub.get_prompt then
      return hub:get_prompt() or ""
    end
  end
  
  -- Fallback: generate basic prompt from server list
  local servers = M.get_active_servers()
  if #servers > 0 then
    local server_names = {}
    for _, server in ipairs(servers) do
      table.insert(server_names, server.name or server.id or "unknown")
    end
    return "Available MCP servers: " .. table.concat(server_names, ", ")
  end
  
  return ""
end

-- Call MCP tool with compatibility layer
function M.call_tool(server_name, tool_name, tool_input, callback)
  local mcphub = M.get_mcphub()
  if not mcphub then
    if callback then
      callback(nil, "mcphub.nvim not available")
    end
    return
  end
  
  -- Try different call methods
  if mcphub.call_tool then
    return mcphub.call_tool(server_name, tool_name, tool_input, callback)
  elseif mcphub.invoke_tool then
    return mcphub.invoke_tool(server_name, tool_name, tool_input, callback)
  elseif mcphub.execute_tool then
    return mcphub.execute_tool(server_name, tool_name, tool_input, callback)
  end
  
  -- Fallback through hub
  local hub = M.get_hub_instance()
  if hub then
    if hub.call_tool then
      return hub:call_tool(server_name, tool_name, tool_input, callback)
    elseif hub.invoke_tool then
      return hub:invoke_tool(server_name, tool_name, tool_input, callback)
    elseif hub.execute_tool then
      return hub:execute_tool(server_name, tool_name, tool_input, callback)
    end
  end
  
  if callback then
    callback(nil, "No compatible tool calling method found")
  end
end

-- Get server by name
function M.get_server(server_name)
  local servers = M.get_active_servers()
  for _, server in ipairs(servers) do
    if server.name == server_name or server.id == server_name then
      return server
    end
  end
  return nil
end

-- Check if specific server is available
function M.has_server(server_name)
  return M.get_server(server_name) ~= nil
end

-- Get debug information
function M.get_debug_info()
  local mcphub = M.get_mcphub()
  if not mcphub then
    return {
      available = false,
      error = "mcphub.nvim not found"
    }
  end
  
  local hub = M.get_hub_instance()
  local servers = M.get_active_servers()
  
  return {
    available = true,
    mcphub_methods = vim.tbl_keys(mcphub),
    hub_available = hub ~= nil,
    hub_methods = hub and vim.tbl_keys(hub) or {},
    server_count = #servers,
    servers = vim.tbl_map(function(s) 
      return { 
        name = s.name or s.id or "unknown", 
        type = type(s),
        keys = type(s) == "table" and vim.tbl_keys(s) or {}
      } 
    end, servers)
  }
end

return M