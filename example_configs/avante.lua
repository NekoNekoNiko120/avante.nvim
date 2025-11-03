-- ~/.config/nvim/lua/plugins/avante.lua
-- Avante.nvim 配置文件 - 支持 MCP 强制模式

return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  version = false,
  opts = {
    -- 基本配置
    provider = "claude",
    
    -- ===== MCP 强制模式配置 =====
    -- 当 mcphub.nvim 可用时，自动强制使用 MCP 工具替代内置工具
    mcp = {
      enabled = true,                    -- 启用 MCP 强制模式
      auto_detect = true,                -- 自动检测 mcphub 可用性
      force_mcp_tools = true,            -- 强制使用 MCP 工具
      auto_disable_builtin = true,       -- 自动禁用冲突的内置工具
      auto_approve_project_files = true, -- 自动批准项目文件操作
      enhance_system_prompt = true,      -- 增强系统提示
      debug = false,                     -- 调试模式
    },
    
    -- 其他配置
    behaviour = {
      auto_suggestions = false,
      auto_apply_diff_after_generation = false,
      minimize_diff = true,
    },
    
    providers = {
      claude = {
        endpoint = "https://api.anthropic.com",
        model = "claude-3-5-sonnet-20241022",
        timeout = 30000,
        extra_request_body = {
          temperature = 0.75,
          max_tokens = 4096,
        },
      },
    },
    
    windows = {
      position = "right",
      width = 30,
    },
  },
  
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
    "HakonHarnes/img-clip.nvim",
    {
      "MeanderingProgrammer/render-markdown.nvim",
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
    -- MCP 支持（必需）
    {
      "ravitemer/mcphub.nvim",
      config = function()
        require("mcphub").setup({
          servers = {
            filesystem = {
              command = "npx",
              args = { "@modelcontextprotocol/server-filesystem", vim.fn.getcwd() }
            },
          },
          auto_approve = function(params)
            -- 自动批准当前项目中的文件操作
            if params.tool_name == "read_file" or params.tool_name == "write_file" then
              local path = params.arguments.path or ""
              if path:match("^" .. vim.fn.getcwd()) then
                return true
              end
            end
            return false
          end,
        })
      end,
    },
  },
}

--[[
MCP 配置选项说明：

mcp = {
  enabled = true,                    -- 启用/禁用 MCP 强制模式
  auto_detect = true,                -- 自动检测 mcphub 可用性
  force_mcp_tools = true,            -- 强制使用 MCP 工具替代内置工具
  auto_disable_builtin = true,       -- 当 MCP 可用时自动禁用冲突的内置工具
  auto_approve_project_files = true, -- 自动批准当前项目内的文件操作
  enhance_system_prompt = true,      -- 在系统提示中包含 MCP 使用指南
  debug = false,                     -- 启用调试日志
  log_redirections = true,           -- 记录工具重定向日志
  
  -- 高级选项（通常不需要修改）
  replaceable_tools = { ... },       -- 可被 MCP 替代的内置工具列表
  system_prompt_template = "...",    -- 自定义系统提示模板
}

使用说明：
1. 确保安装了 mcphub.nvim 并配置了至少一个 MCP 服务器
2. 设置 mcp.enabled = true 启用强制模式
3. 重启 Neovim
4. 运行 :AvanteMCPStatus 检查状态
5. AI 将自动使用 MCP 工具而不是内置工具

快速禁用：设置 mcp.enabled = false 即可回到标准模式
--]]