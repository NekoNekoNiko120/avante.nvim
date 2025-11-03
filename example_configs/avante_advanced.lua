-- ~/.config/nvim/lua/plugins/avante.lua
-- 高级 MCP 配置示例

return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  opts = {
    provider = "claude",
    
    -- 高级 MCP 配置
    mcp = {
      enabled = true,
      auto_detect = true,
      force_mcp_tools = true,
      auto_disable_builtin = true,
      auto_approve_project_files = true,
      enhance_system_prompt = true,
      debug = true, -- 启用调试日志
      log_redirections = true,
      
      -- 自定义可替代的工具列表
      replaceable_tools = {
        "str_replace_based_edit_tool",
        "create",
        "read_file",
        "write_to_file",
        "edit_file",
        "list_files",
        "bash"
        -- 移除了一些工具，保留部分内置功能
      },
      
      -- 自定义系统提示模板
      system_prompt_template = [[

🤖 MCP TOOLS ENABLED: You MUST use MCP tools for all file operations!

Available MCP patterns:
- File ops: use_mcp_tool with server "filesystem" 
- Shell: use_mcp_tool with server "shell"

Example:
{
  "name": "use_mcp_tool",
  "input": {
    "server_name": "filesystem",
    "tool_name": "write_file",
    "tool_input": {"path": "file.txt", "content": "..."}
  }
}
]],
    },
    
    behaviour = {
      auto_suggestions = false,
      auto_apply_diff_after_generation = false,
      minimize_diff = true,
      -- 自定义工具权限批准逻辑
      auto_approve_tool_permissions = function(tool_name, tool_input)
        -- 自动批准 MCP 工具
        if tool_name == "use_mcp_tool" then
          local server_name = tool_input.server_name
          local mcp_tool_name = tool_input.tool_name
          
          -- 批准文件系统操作
          if server_name == "filesystem" then
            return true
          end
          
          -- 批准安全的 shell 命令
          if server_name == "shell" and mcp_tool_name == "run_command" then
            local command = tool_input.tool_input and tool_input.tool_input.command
            if command and not command:match("rm|sudo|chmod") then
              return true
            end
          end
        end
        
        return false -- 其他情况需要确认
      end,
    },
  },
  
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-tree/nvim-web-devicons",
    "HakonHarnes/img-clip.nvim",
    {
      "MeanderingProgrammer/render-markdown.nvim",
      opts = { file_types = { "markdown", "Avante" } },
      ft = { "markdown", "Avante" },
    },
    {
      "ravitemer/mcphub.nvim",
      config = function()
        require("mcphub").setup({
          servers = {
            filesystem = {
              command = "npx",
              args = { "@modelcontextprotocol/server-filesystem", vim.fn.getcwd() }
            },
            shell = {
              command = "npx",
              args = { "@modelcontextprotocol/server-shell" }
            },
          },
          auto_approve = function(params)
            -- 更严格的权限控制
            if params.tool_name == "read_file" then
              return true -- 总是允许读取
            end
            
            if params.tool_name == "write_file" then
              local path = params.arguments.path or ""
              -- 只允许在当前项目目录下写入
              if path:match("^" .. vim.fn.getcwd()) and not path:match("%.git/") then
                return true
              end
            end
            
            return false -- 其他操作需要确认
          end,
        })
      end,
    },
  },
}