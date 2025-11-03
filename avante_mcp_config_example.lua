-- Avante.nvim配置示例 - 启用MCP工具集成
-- 将此配置添加到你的init.lua或avante配置文件中

require("avante").setup({
  -- 其他avante配置...
  
  -- 禁用内置工具，优先使用MCP工具
  disabled_tools = {
    "edit_file",      -- 使用MCP的文件编辑工具
    "create",         -- 使用MCP的文件创建工具
    "write_to_file",  -- 使用MCP的文件写入工具
  },
  
  -- 添加MCP工具作为自定义工具
  custom_tools = function()
    -- 检查MCP集成是否可用
    local ok, mcp_integration = pcall(require, "avante.mcp_integration")
    if ok then
      local config = mcp_integration.get_recommended_config()
      return config.custom_tools()
    else
      -- 如果MCP集成不可用，返回空表
      return {}
    end
  end,
  
  -- 其他配置选项...
  provider = "claude", -- 或你喜欢的提供商
  auto_suggestions = true,
  -- ...
})

-- 可选：显示MCP集成状态
vim.defer_fn(function()
  local ok, mcp_integration = pcall(require, "avante.mcp_integration")
  if ok then
    local status = mcp_integration.status()
    if status.mcphub_available then
      print("✅ Avante MCP Integration: " .. status.mcp_tools_count .. " tools available")
    else
      print("⚠️  Avante MCP Integration: mcphub.nvim not available")
    end
  end
end, 1000)