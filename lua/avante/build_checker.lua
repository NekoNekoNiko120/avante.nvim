---@class avante.BuildChecker
local M = {}

local Utils = require("avante.utils")

-- Detect platform and get library extension
local function get_platform_info()
  local uname = vim.uv.os_uname()
  local sysname = uname.sysname
  
  if sysname == "Linux" then
    return "Linux", "so"
  elseif sysname == "Darwin" then
    return "macOS", "dylib"
  elseif sysname:match("Windows") or sysname:match("MINGW") or sysname:match("CYGWIN") then
    return "Windows", "dll"
  else
    return "Unknown", "so" -- fallback
  end
end

-- Check if all required build files exist
local function check_build_files()
  local platform, lib_ext = get_platform_info()
  local project_root = Utils.root.get()
  
  local required_files = {
    "build/avante_templates." .. lib_ext,
    "build/avante_tokenizers." .. lib_ext,
    "build/avante_repo_map." .. lib_ext,
    "build/avante_html2md." .. lib_ext,
  }
  
  local missing_files = {}
  local build_dir = project_root .. "/build"
  
  -- Check if build directory exists
  if vim.fn.isdirectory(build_dir) == 0 then
    return false, missing_files, platform
  end
  
  -- Check each required file
  for _, file in ipairs(required_files) do
    local full_path = project_root .. "/" .. file
    if vim.fn.filereadable(full_path) == 0 then
      table.insert(missing_files, file)
    end
  end
  
  return #missing_files == 0, missing_files, platform
end

-- Get appropriate build command for the platform
local function get_build_command()
  local project_root = Utils.root.get()
  local platform, _ = get_platform_info()
  
  -- Check for main build scripts
  if platform == "Windows" and vim.fn.filereadable(project_root .. "/Build.ps1") == 1 then
    if vim.fn.executable("powershell") == 1 then
      return "powershell -ExecutionPolicy Bypass -File Build.ps1"
    end
  end
  
  if vim.fn.filereadable(project_root .. "/build.sh") == 1 then
    if vim.fn.executable("bash") == 1 then
      return "bash build.sh"
    elseif vim.fn.executable("sh") == 1 then
      return "sh build.sh"
    end
  end
  
  -- Last resort: try make
  if vim.fn.filereadable(project_root .. "/Makefile") == 1 and vim.fn.executable("make") == 1 then
    return "make"
  end
  
  return nil
end

-- Show build instructions to user
local function show_build_instructions()
  local build_cmd = get_build_command()
  local platform, _ = get_platform_info()
  
  local message = {
    "🔧 Avante.nvim requires building native libraries.",
    "",
    "Platform detected: " .. platform,
    "",
  }
  
  if build_cmd then
    table.insert(message, "Run this command in your avante.nvim directory:")
    table.insert(message, "  " .. build_cmd)
    table.insert(message, "")
    table.insert(message, "Or run: :AvanteAutoBuild")
  else
    table.insert(message, "Please run one of these commands in your avante.nvim directory:")
    table.insert(message, "  bash build.sh")
    table.insert(message, "  make")
    if platform == "Windows" then
      table.insert(message, "  powershell -ExecutionPolicy Bypass -File Build.ps1")
    end
  end
  
  table.insert(message, "")
  table.insert(message, "For more information, see: https://github.com/yetone/avante.nvim#installation")
  
  Utils.warn(table.concat(message, "\n"), { title = "Avante Build Required" })
end

-- Progress bar animation
local function show_progress_bar(message, duration_ms)
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame_index = 1
  local start_time = vim.uv.hrtime()
  local timer = vim.uv.new_timer()
  
  local function update_progress()
    local elapsed = (vim.uv.hrtime() - start_time) / 1000000 -- Convert to milliseconds
    local progress = math.min(elapsed / duration_ms, 1.0)
    local bar_length = 30
    local filled = math.floor(progress * bar_length)
    local bar = string.rep("█", filled) .. string.rep("░", bar_length - filled)
    local percentage = math.floor(progress * 100)
    
    local spinner = frames[frame_index]
    frame_index = frame_index % #frames + 1
    
    local status_line = string.format("%s %s [%s] %d%%", spinner, message, bar, percentage)
    
    -- Clear the line and print new status
    vim.api.nvim_echo({ { "\r" .. status_line, "Normal" } }, false, {})
    
    if progress >= 1.0 then
      timer:stop()
      timer:close()
      vim.api.nvim_echo({ { "\r" .. string.rep(" ", #status_line) .. "\r", "Normal" } }, false, {})
    end
  end
  
  timer:start(0, 100, vim.schedule_wrap(update_progress))
  return timer
end

-- Attempt automatic build with progress bar
function M.auto_build()
  local build_cmd = get_build_command()
  if not build_cmd then
    Utils.error("No suitable build command found. Please build manually.")
    show_build_instructions()
    return false
  end
  
  local project_root = Utils.root.get()
  
  -- Show initial message
  Utils.info("🚀 Starting Avante library build process...")
  
  -- Start progress bar (estimated 30 seconds for build)
  local progress_timer = show_progress_bar("Building Avante libraries", 30000)
  
  -- Run build command asynchronously
  local full_cmd = "cd " .. vim.fn.shellescape(project_root) .. " && " .. build_cmd
  
  -- Use vim.fn.jobstart for async execution with better control
  local job_id = vim.fn.jobstart(full_cmd, {
    on_exit = function(_, exit_code, _)
      -- Stop progress bar
      if progress_timer then
        progress_timer:stop()
        progress_timer:close()
      end
      
      -- Clear progress line
      vim.schedule(function()
        vim.api.nvim_echo({ { "\r" .. string.rep(" ", 80) .. "\r", "Normal" } }, false, {})
        
        if exit_code == 0 then
          Utils.info("✅ Avante libraries built successfully!")
          
          -- Verify build files exist
          vim.defer_fn(function()
            local files_exist, _, _ = check_build_files()
            if files_exist then
              Utils.info("🎉 All required library files are now present!")
            else
              Utils.warn("⚠️  Build completed but some files may be missing. Please check manually.")
            end
          end, 500)
        else
          Utils.error("❌ Build failed with exit code " .. exit_code)
          show_build_instructions()
        end
      end)
    end,
    on_stdout = function(_, data, _)
      -- Optionally show build output in debug mode
      if vim.g.avante_debug then
        for _, line in ipairs(data) do
          if line ~= "" then
            Utils.debug("Build: " .. line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      -- Show errors
      for _, line in ipairs(data) do
        if line ~= "" then
          Utils.debug("Build Error: " .. line)
        end
      end
    end,
  })
  
  if job_id <= 0 then
    -- Stop progress bar on job start failure
    if progress_timer then
      progress_timer:stop()
      progress_timer:close()
    end
    Utils.error("❌ Failed to start build process")
    show_build_instructions()
    return false
  end
  
  Utils.info("📦 Build process started (Job ID: " .. job_id .. ")")
  Utils.info("💡 You can continue using Neovim while the build runs in the background")
  
  return true
end

-- Main check function
function M.check_and_prompt()
  local files_exist, missing_files, platform = check_build_files()
  
  if not files_exist then
    Utils.debug("Missing build files: " .. vim.inspect(missing_files))
    show_build_instructions()
    return false
  end
  
  return true
end

-- Synchronous build with progress (blocks until completion)
function M.auto_build_sync()
  local build_cmd = get_build_command()
  if not build_cmd then
    Utils.error("No suitable build command found. Please build manually.")
    show_build_instructions()
    return false
  end
  
  local project_root = Utils.root.get()
  Utils.info("🚀 Building Avante libraries synchronously...")
  
  -- Start progress bar (estimated 30 seconds)
  local progress_timer = show_progress_bar("Building Avante libraries", 30000)
  
  -- Run build command synchronously
  local full_cmd = "cd " .. vim.fn.shellescape(project_root) .. " && " .. build_cmd
  local result = vim.fn.system(full_cmd)
  local exit_code = vim.v.shell_error
  
  -- Stop progress bar
  if progress_timer then
    progress_timer:stop()
    progress_timer:close()
  end
  
  -- Clear progress line
  vim.api.nvim_echo({ { "\r" .. string.rep(" ", 80) .. "\r", "Normal" } }, false, {})
  
  if exit_code == 0 then
    Utils.info("✅ Avante libraries built successfully!")
    
    -- Verify build files exist
    local files_exist, _, _ = check_build_files()
    if files_exist then
      Utils.info("🎉 All required library files are now present!")
    else
      Utils.warn("⚠️  Build completed but some files may be missing. Please check manually.")
    end
    return true
  else
    Utils.error("❌ Build failed with exit code " .. exit_code .. ":\n" .. result)
    show_build_instructions()
    return false
  end
end

-- Check if build is needed (silent)
function M.is_build_needed()
  local files_exist, _, _ = check_build_files()
  return not files_exist
end

return M