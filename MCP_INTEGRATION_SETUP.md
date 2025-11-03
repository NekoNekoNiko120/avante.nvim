# Avante.nvim MCP Integration Setup

这个文档说明如何配置Avante.nvim使用MCP工具而不是内置工具。

## 前提条件

1. 安装并配置 `mcphub.nvim`
2. 配置至少一个MCP服务器（如filesystem服务器）

## 配置方法

### 方法1：使用集成模块（推荐）

在你的Avante配置中添加以下内容：

```lua
-- 在你的init.lua或avante配置文件中
local mcp_integration = require("avante.mcp_integration")

require("avante").setup({
  -- 其他配置...
  
  -- 使用MCP集成的推荐配置
  disabled_tools = {
    "edit_file",      -- 禁用内置的edit_file工具
    "create",         -- 禁用内置的create工具  
    "write_to_file",  -- 禁用内置的write_to_file工具
  },
  
  -- 添加MCP工具作为自定义工具
  custom_tools = function()
    return require("avante.mcp_integration").get_recommended_config().custom_tools()
  end,
})
```

### 方法2：手动配置

如果你想更精细地控制配置：

```lua
require("avante").setup({
  -- 其他配置...
  
  disabled_tools = {
    "edit_file",      -- 禁用内置编辑工具
    "create",         -- 禁用内置创建工具
    "write_to_file",  -- 禁用内置写入工具
  },
  
  custom_tools = {
    -- MCP文件编辑工具
    {
      name = "mcp_edit_file",
      description = "Edit files using MCP filesystem server",
      param = {
        type = "table",
        fields = {
          {
            name = "path",
            description = "File path to edit",
            type = "string",
          },
          {
            name = "content", 
            description = "New file content",
            type = "string",
          },
        },
      },
      returns = {
        {
          name = "success",
          description = "Whether the edit was successful",
          type = "boolean",
        },
      },
      func = function(input, opts)
        local mcphub = require("mcphub")
        local on_complete = opts.on_complete
        
        mcphub.call_tool("filesystem", "write_file", {
          path = input.path,
          content = input.content,
        }, function(result, error)
          if error then
            on_complete(false, "Edit failed: " .. error)
          else
            on_complete(true, nil)
          end
        end)
      end,
    },
    
    -- 通用MCP工具包装器
    {
      name = "use_mcp_tool",
      description = "Use any MCP tool",
      param = {
        type = "table", 
        fields = {
          {
            name = "server_name",
            description = "MCP server name",
            type = "string",
          },
          {
            name = "tool_name", 
            description = "Tool name to call",
            type = "string",
          },
          {
            name = "tool_input",
            description = "Tool input parameters",
            type = "table",
            optional = true,
          },
        },
      },
      returns = {
        {
          name = "result",
          description = "Tool result",
          type = "string", 
        },
      },
      func = function(input, opts)
        local mcphub = require("mcphub")
        local on_complete = opts.on_complete
        
        mcphub.call_tool(
          input.server_name,
          input.tool_name, 
          input.tool_input or {},
          function(result, error)
            if error then
              on_complete(nil, error)
            else
              on_complete(vim.json.encode(result), nil)
            end
          end
        )
      end,
    },
  },
})
```

## MCP服务器配置示例

确保你的MCP配置包含文件系统服务器：

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "uvx",
      "args": ["mcp-server-filesystem", "/path/to/your/project"],
      "env": {}
    }
  }
}
```

## 验证配置

你可以使用以下命令检查MCP集成状态：

```lua
:lua print(vim.inspect(require("avante.mcp_integration").status()))
```

## 使用示例

配置完成后，AI将能够使用以下工具：

### 1. 使用MCP编辑文件
```
AI可以使用mcp_edit_file工具来编辑文件，这比内置的edit_file工具提供更好的错误处理和验证。
```

### 2. 使用通用MCP工具
```
AI可以使用use_mcp_tool来调用任何可用的MCP工具，例如：
- 文件系统操作
- 代码分析工具
- 外部API调用
- 等等
```

## 工具优先级

配置后的工具优先级：
1. **MCP工具** - 优先使用MCP服务器提供的工具
2. **自定义工具** - 用户定义的其他工具
3. **内置工具** - 未被禁用的Avante内置工具

## 故障排除

### 1. MCP工具不可用
- 检查mcphub.nvim是否正确安装
- 验证MCP服务器配置
- 确保MCP服务器正在运行

### 2. 工具冲突
- 检查disabled_tools配置
- 确保没有重复的工具名称
- 查看Avante日志获取详细错误信息

### 3. 性能问题
- 考虑只禁用真正需要替换的工具
- 监控MCP服务器的响应时间
- 根据需要调整超时设置

## 高级配置

### 条件性启用MCP工具

```lua
custom_tools = function()
  -- 只在MCP可用时添加MCP工具
  local mcp_integration = require("avante.mcp_integration")
  local status = mcp_integration.status()
  
  if status.mcphub_available then
    return mcp_integration.get_recommended_config().custom_tools()
  else
    return {} -- 回退到内置工具
  end
end,
```

### 特定项目的MCP配置

```lua
-- 根据项目类型使用不同的MCP服务器
custom_tools = function()
  local cwd = vim.fn.getcwd()
  local server_name = "filesystem" -- 默认
  
  if string.match(cwd, "python") then
    server_name = "python-tools"
  elseif string.match(cwd, "node") then
    server_name = "nodejs-tools"
  end
  
  -- 返回配置了特定服务器的工具
  return {
    {
      name = "project_edit_file",
      -- ... 使用project-specific server_name
    }
  }
end,
```