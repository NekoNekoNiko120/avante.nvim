-- ~/.config/nvim/lua/plugins/avante.lua
-- 最简单的 MCP 强制模式配置

return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  opts = {
    provider = "claude",
    
    -- 启用 MCP 强制模式（一行配置）
    mcp = { enabled = true },
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
          },
        })
      end,
    },
  },
}