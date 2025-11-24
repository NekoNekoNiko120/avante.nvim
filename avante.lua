-- Set environment variables
vim.env.DEEPSEEK_API_KEY = "sk-3263b29eaa0447c89fe05043ba808788"
vim.env.AIHUBMIX_API_KEY = "sk-H43n3zPmfkpAldxj189a10FfA7B94097BaB67c5bC32347Ef"
vim.env.TAVILY_API_KEY = "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"
vim.env.MORPH_API_KEY = "sk-W3N7koWtLBHVpJlRNMTUicW5r2xdnSEejhtZ3zUdJCAFRZKA"
vim.env.MOONSHOT_CN_API_KEY = "sk-k4X2Vc5tOAepJtgBfh3jVMEBgoLQLmkvp9QgofDIQLxqOsBu"
vim.env.INCEPTION_API_KEY = "sk_a2a6ad9484afef66dc6f7ebc1e99f271"

-- Neovim settings
vim.opt.laststatus = 3

return {
  {
    "NekoNekoNiko120/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false,
    opts = {
      provider = "inception",
      providers = {
        deepseek = {
          __inherited_from = "openai",
          api_key_name = "DEEPSEEK_API_KEY",
          endpoint = "https://api.deepseek.com",
          model = "deepseek-coder",
          extra_request_body = {
            max_tokens = 8192,
          },
        },
        aihubmix = {
          __inherited_from = "openai",
          endpoint = "https://aihubmix.com/v1",
          model = "grok-code-fast-1",
          api_key_name = "AIHUBMIX_API_KEY",
        },
        inception = {
          __inherited_from = "openai",
          api_key_name = "INCEPTION_API_KEY",
          endpoint = "https://api.inceptionlabs.ai/v1",
          model = "mercury-coder",
        },
      },
      mode = "agentic",
      use_ReAct_prompt = true,
      web_search_engine = {
        provider = "tavily",
        proxy = nil,
      },
    },
    -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
    build = "make BUILD_FROM_SOURCE=true",
    -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      --- The below dependencies are optional,
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      "zbirenbaum/copilot.lua", -- for providers='copilot'
      {
        -- support for image pasting
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          -- recommended settings
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
            -- required for Windows users
            use_absolute_path = true,
          },
        },
      },
      {
        -- Make sure to set this up properly if you have lazy=true
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
}
