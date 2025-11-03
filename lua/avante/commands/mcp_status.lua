-- MCP Status Command for Avante.nvim
-- Provides commands to check MCP integration status

local M = {}

-- Check MCP integration status
function M.check_status()
  local status_lines = {}
  local compat = require("avante.mcphub_compat")
  
  -- Check mcphub availability
  if not compat.is_available() then
    table.insert(status_lines, "❌ mcphub.nvim: Not installed")
    table.insert(status_lines, "   Install mcphub.nvim to enable MCP integration")
    vim.notify(table.concat(status_lines, "\n"), vim.log.levels.WARN, { title = "Avante MCP Status" })
    return
  end
  
  local servers = compat.get_active_servers()
  local server_count = compat.get_server_count()
  
  if server_count == 0 then
    table.insert(status_lines, "⚠️  mcphub.nvim: No active MCP servers")
    table.insert(status_lines, "   Configure MCP servers in mcphub to enable integration")
    
    -- Show debug info if available
    local debug_info = compat.get_debug_info()
    if debug_info.hub_available then
      table.insert(status_lines, "   Hub is available but no servers configured")
    else
      table.insert(status_lines, "   Hub not initialized - check mcphub setup")
    end
    vim.notify(table.concat(status_lines, "\n"), vim.log.levels.WARN, { title = "Avante MCP Status" })
    return
  end
  
  if #servers == 0 then
    table.insert(status_lines, "⚠️  mcphub.nvim: No active MCP servers")
    table.insert(status_lines, "   Configure MCP servers in mcphub to enable integration")
    vim.notify(table.concat(status_lines, "\n"), vim.log.levels.WARN, { title = "Avante MCP Status" })
    return
  end
  
    vim.notify(table.concat(status_lines, "\n"), vim.log.levels.WARN, { title = "Avante MCP Status" })
    return
  end
  
  -- MCP is available and active
  table.insert(status_lines, "✅ mcphub.nvim: Active with " .. server_count .. " server(s)")
  
  -- List active servers
  for _, server in ipairs(servers) do
    local server_name = server.name or server.id or tostring(server)
    table.insert(status_lines, "   📡 " .. server_name)
  end
  
  -- Check tool redirection status
  local redirector_ok, redirector = pcall(require, "avante.tool_redirector")
  if redirector_ok then
    local redirectable = redirector.get_redirectable_tools()
    table.insert(status_lines, "")
    table.insert(status_lines, "🔄 Tool Redirection: Enabled")
    table.insert(status_lines, "   Redirectable tools: " .. table.concat(redirectable, ", "))
  end
  
  -- Check MCP force config status
  local force_config_ok, force_config = pcall(require, "avante.mcp_force_config")
  if force_config_ok then
    local force_status = force_config.status()
    table.insert(status_lines, "")
    if force_status.auto_mcp_enabled then
      table.insert(status_lines, "🚀 MCP Force Mode: Enabled")
      table.insert(status_lines, "   Built-in tools are automatically replaced with MCP tools")
    else
      table.insert(status_lines, "⚠️  MCP Force Mode: Disabled")
    end
  end
  
  -- Check available MCP tools
  local mcp_ext_ok, mcp_ext = pcall(require, "mcphub.extensions.avante")
  if mcp_ext_ok and mcp_ext.mcp_tool then
    table.insert(status_lines, "")
    table.insert(status_lines, "🛠️  MCP Tools: Available")
    table.insert(status_lines, "   use_mcp_tool is ready for AI usage")
  end
  
  vim.notify(table.concat(status_lines, "\n"), vim.log.levels.INFO, { title = "Avante MCP Status" })
end

-- Show detailed MCP configuration
function M.show_config()
  local config_lines = {}
  
  -- Show current avante configuration relevant to MCP
  local Config = require("avante.config")
  
  table.insert(config_lines, "📋 Current Avante MCP Configuration:")
  table.insert(config_lines, "")
  
  -- Show disabled tools
  if Config.disabled_tools and #Config.disabled_tools > 0 then
    table.insert(config_lines, "🚫 Disabled Tools:")
    for _, tool in ipairs(Config.disabled_tools) do
      table.insert(config_lines, "   - " .. tool)
    end
  else
    table.insert(config_lines, "🚫 Disabled Tools: None")
  end
  
  table.insert(config_lines, "")
  
  -- Show custom tools
  local custom_tools = Config.custom_tools
  if type(custom_tools) == "function" then
    custom_tools = custom_tools()
  end
  
  if custom_tools and #custom_tools > 0 then
    table.insert(config_lines, "🔧 Custom Tools:")
    for _, tool in ipairs(custom_tools) do
      table.insert(config_lines, "   - " .. (tool.name or "unnamed"))
    end
  else
    table.insert(config_lines, "🔧 Custom Tools: None")
  end
  
  -- Show in a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, config_lines)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = math.min(80, vim.o.columns - 4),
    height = math.min(#config_lines + 2, vim.o.lines - 4),
    col = math.floor((vim.o.columns - 80) / 2),
    row = math.floor((vim.o.lines - #config_lines) / 2),
    border = 'rounded',
    title = ' Avante MCP Configuration ',
    title_pos = 'center',
  })
  
  -- Set up keymaps for the window
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<cr>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })
end

-- Test MCP tool functionality
function M.test_mcp_tools()
  local compat = require("avante.mcphub_compat")
  
  if not compat.is_available() then
    vim.notify("❌ mcphub.nvim not available", vim.log.levels.ERROR, { title = "MCP Test" })
    return
  end
  
  if not compat.has_active_servers() then
    vim.notify("❌ No active MCP servers", vim.log.levels.ERROR, { title = "MCP Test" })
    return
  end
  
  -- Test basic MCP tool call
  vim.notify("🧪 Testing MCP tool functionality...", vim.log.levels.INFO, { title = "MCP Test" })
  
  -- Try to call a simple MCP tool (list_directory on current directory)
  compat.call_tool("filesystem", "list_directory", { path = "." }, function(result, error)
    if error then
      vim.notify("❌ MCP test failed: " .. error, vim.log.levels.ERROR, { title = "MCP Test" })
    else
      vim.notify("✅ MCP test successful! Filesystem tools are working.", vim.log.levels.INFO, { title = "MCP Test" })
    end
  end)
end

-- Setup commands
function M.setup_commands()
  vim.api.nvim_create_user_command('AvanteMCPStatus', M.check_status, {
    desc = 'Check Avante MCP integration status'
  })
  
  vim.api.nvim_create_user_command('AvanteMCPConfig', M.show_config, {
    desc = 'Show Avante MCP configuration'
  })
  
  vim.api.nvim_create_user_command('AvanteMCPTest', M.test_mcp_tools, {
    desc = 'Test MCP tool functionality'
  })
end

return M