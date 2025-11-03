# Avante.nvim MCP工具重定向 - 完整解决方案

## 问题描述

AI有时候仍然会调用avante自带的`edit_file`工具，而不是使用MCP工具。

## 解决方案

我们实现了一个多层次的解决方案来确保AI优先使用MCP工具：

### 1. 工具优先级调整

修改了`lua/avante/llm_tools/init.lua`中的工具加载顺序：
- 自定义工具（包括MCP工具）现在有更高优先级
- 添加了重复工具名称的去重逻辑
- 确保MCP工具会覆盖同名的内置工具

### 2. 强制工具重定向

在`lua/avante/llm_tools/init.lua`的`process_tool_use`函数中添加了强制重定向逻辑：
- 检查工具是否在`disabled_tools`列表中
- 如果是，自动重定向到对应的MCP工具
- 支持多种工具类型的智能重定向

### 3. 工具重定向器模块

创建了`lua/avante/tool_redirector.lua`模块：
- 定义了完整的工具重定向映射
- 支持输入参数的智能转换
- 自动检测可用的MCP服务器
- 提供灵活的重定向配置

## 支持的工具重定向

| 内置工具 | MCP服务器 | MCP工具 | 说明 |
|---------|----------|---------|------|
| `edit_file` | filesystem | write_file | 文件编辑 |
| `create_file` | filesystem | write_file | 文件创建 |
| `write_to_file` | filesystem | write_file | 文件写入 |
| `read_file` | filesystem | read_file | 文件读取 |
| `list_files` | filesystem | list_directory | 目录列表 |
| `search_files` | filesystem | search_files | 文件搜索 |
| `delete_file` | filesystem | delete_file | 文件删除 |
| `rename_file` | filesystem | move_file | 文件重命名 |
| `create_dir` | filesystem | create_directory | 目录创建 |
| `bash` | shell | run_command | 命令执行 |

## 配置方法

### 推荐配置（使用mcphub扩展）

```lua
require("avante").setup {
  -- 系统提示包含MCP服务器状态
  system_prompt = function()
    local hub = require("mcphub").get_hub_instance()
    return hub and hub:get_active_servers_prompt() or ""
  end,
  
  -- 使用mcphub扩展
  custom_tools = function()
    return {
      require("mcphub.extensions.avante").mcp_tool(),
    }
  end,
  
  -- 禁用内置工具（将自动重定向到MCP）
  disabled_tools = {
    "edit_file", "create_file", "read_file", "write_to_file",
    "list_files", "search_files", "delete_file", "rename_file",
    "create_dir", "bash"
  },
}
```

## 工作原理

### 1. 工具过滤阶段
- `get_tools()` 函数过滤掉被禁用的工具
- 只有MCP工具和其他启用的工具会出现在工具列表中

### 2. 工具调用阶段
- 如果AI仍然尝试调用被禁用的工具，`process_tool_use()` 会拦截
- 自动查找对应的MCP重定向
- 转换输入参数格式
- 重新调用MCP工具

### 3. 参数转换
- 智能转换不同工具的参数格式
- 处理常见的参数名称变化
- 确保MCP工具能正确接收参数

## 调试和测试

### 运行调试脚本
```lua
:luafile debug_tools.lua
```

### 测试工具重定向
```lua
:luafile test_tool_redirection.lua
```

### 检查配置状态
```lua
:lua print(vim.inspect(require("avante.tool_redirector").get_redirectable_tools()))
```

## 故障排除

### 1. AI仍然使用内置工具
- 检查`disabled_tools`配置是否正确
- 确认工具重定向器模块已加载
- 查看Avante日志中的重定向消息

### 2. MCP工具不可用
- 确认mcphub.nvim已正确安装和配置
- 检查MCP服务器是否正在运行
- 验证MCP服务器支持所需的工具

### 3. 参数转换错误
- 检查工具重定向器中的参数映射
- 确认MCP工具的参数格式
- 查看错误日志获取详细信息

## 优势

1. **完全透明**：AI无需知道重定向的存在
2. **自动回退**：如果MCP不可用，会显示清晰的错误信息
3. **灵活配置**：可以选择性地启用/禁用特定工具的重定向
4. **智能转换**：自动处理不同工具间的参数差异
5. **调试友好**：提供详细的日志和调试工具

## 注意事项

1. 确保MCP服务器支持所需的工具
2. 某些工具可能需要特定的权限配置
3. 重定向可能会增加轻微的延迟
4. 建议在生产环境前充分测试重定向功能

这个解决方案确保了AI始终使用MCP工具，即使它尝试调用被禁用的内置工具也会被自动重定向。