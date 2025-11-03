-- Avante.nvim配置示例 - 启用MCP工具集成（推荐方法）
-- 将此配置添加到你的init.lua或avante配置文件中

-- Avante配置
require("avante").setup {
  behaviour = {
    enable_fastapply = true, -- 启用快速应用功能
    auto_apply_diff_after_generation = false,
  },
  
  -- 系统提示作为函数确保LLM始终有最新的MCP服务器状态
  system_prompt = function()
    local hub = require("mcphub").get_hub_instance()
    return hub and hub:get_active_servers_prompt() or ""
  end,
  
  -- 使用mcphub扩展提供MCP工具
  custom_tools = function()
    return {
      require("mcphub.extensions.avante").mcp_tool(),
    }
  end,
  
  -- 禁用内置工具，让AI使用MCP工具
  -- 重要：只有在此列表中的工具才会被重定向到MCP
  disabled_tools = {
    "edit_file",      -- 重定向到 MCP filesystem/write_file
    "create_file",    -- 重定向到 MCP filesystem/write_file
    "write_to_file",  -- 重定向到 MCP filesystem/write_file
    "read_file",      -- 重定向到 MCP filesystem/read_file
    "list_files",     -- 重定向到 MCP filesystem/list_directory
    "search_files",   -- 重定向到 MCP filesystem/search_files
    "delete_file",    -- 重定向到 MCP filesystem/delete_file
    "rename_file",    -- 重定向到 MCP filesystem/move_file
    "create_dir",     -- 重定向到 MCP filesystem/create_directory
    "rename_dir",     -- 重定向到 MCP filesystem/move_file
    "delete_dir",     -- 重定向到 MCP filesystem/delete_file
    "bash",           -- 重定向到 MCP shell/run_command (如果可用)
  },
  
  -- 其他配置选项...
  provider = "claude", -- 或你喜欢的提供商
  auto_suggestions = true,
}

-- mcphub配置
require("mcphub").setup {
  auto_approve = function(params)
    -- 自动批准当前项目中的安全文件操作
    if params.tool_name == "read_file" or params.tool_name == "write_file" then
      local path = params.arguments.path or ""
      if path:match("^" .. vim.fn.getcwd()) then
        return true -- 自动批准当前项目内的文件操作
      end
    end
    
    -- 检查工具是否在servers.json中配置为自动批准
    if params.is_auto_approved_in_server then
      return true -- 遵循servers.json配置
    end
    
    return false -- 显示确认提示
  end,
  
  extensions = {
    avante = {
      make_slash_commands = true, -- 从MCP服务器提示创建/斜杠命令
    },
  },
}

-- 可选：显示MCP集成状态
vim.defer_fn(function()
  local ok, mcphub = pcall(require, "mcphub")
  if ok then
    local hub = mcphub.get_hub_instance()
    if hub then
      local servers = hub:get_active_servers()
      print("✅ Avante MCP Integration: " .. #servers .. " MCP servers active")
      
      -- 显示工具重定向状态
      local redirector_ok, redirector = pcall(require, "avante.tool_redirector")
      if redirector_ok then
        local redirectable = redirector.get_redirectable_tools()
        print("🔄 Tool redirection enabled for: " .. table.concat(redirectable, ", "))
      end
    else
      print("⚠️  Avante MCP Integration: No active MCP servers")
    end
  else
    print("❌ Avante MCP Integration: mcphub.nvim not available")
  end
end, 1000)