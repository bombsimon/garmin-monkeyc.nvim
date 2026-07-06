-- `:checkhealth garmin-monkeyc`, the equivalent of the VS Code extension's
-- "Verify Installation": reports the SDK, toolchain, java, developer key, and
-- live language-server status.

local config = require("garmin-monkeyc.config")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

-- First line of `java -version` (which java writes to stderr), or nil.
local function java_version()
  local ok, result = pcall(function()
    return vim.system({ "java", "-version" }, { text = true }):wait()
  end)

  if ok and result and result.code == 0 then
    return vim.split((result.stderr or "") .. (result.stdout or ""), "\n")[1]
  end

  return nil
end

local function installed_device_count(sdk_path)
  return #vim.fn.glob(vim.fs.joinpath(sdk.devices_path(sdk_path), "*", "compiler.json"), false, true)
end

function M.check()
  local health = vim.health

  health.start("garmin-monkeyc")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11+ required (uses vim.lsp.config / vim.lsp.enable)")
  end

  if vim.fn.executable("java") == 1 then
    health.ok("java: " .. (java_version() or "found"))
  else
    health.error("java not found on PATH", { "Install a JRE (17+) and ensure `java` is on PATH" })
  end

  -- openssl is only needed for :MonkeyC generate-key.
  if vim.fn.executable("openssl") == 1 then
    health.ok("openssl (for :MonkeyC generate-key)")
  else
    health.warn("openssl not found; :MonkeyC generate-key will not work", {
      "Install openssl to generate a developer key, or provide your own",
    })
  end

  -- SDK path (falls back to the per-OS default when setup() hasn't run).
  local sdk_path = config.options.sdk_path or sdk.default_sdk_path()

  if not vim.uv.fs_stat(sdk_path) then
    health.error("SDK path not found: " .. sdk_path, {
      "Install the Connect IQ SDK via the SDK Manager, or set the `sdk_path` option",
    })

    return
  end

  health.ok("SDK path: " .. sdk_path)

  local sdk_dir = sdk.newest_sdk(sdk_path)
  if sdk_dir then
    health.ok("SDK version: " .. vim.fs.basename(sdk_dir))
  else
    health.error("no SDK installed under " .. sdk_path, { "Download an SDK in the SDK Manager" })
    return
  end

  -- Tools all live in the SDK's bin, so report just presence (name only).
  if sdk.language_server_jar(sdk_path) then
    health.ok("language server")
  else
    health.error("LanguageServer.jar not found in " .. sdk_dir)
  end

  for _, tool in ipairs({ "monkeyc", "monkeydo", "connectiq" }) do
    if sdk.tool(sdk_path, tool) then
      health.ok(tool)
    else
      health.warn(tool .. " not found in " .. sdk_dir)
    end
  end

  local devices = installed_device_count(sdk_path)
  if devices > 0 then
    health.ok(("%d installed device(s)"):format(devices))
  else
    health.warn("no installed devices found", { "Download at least one device in the SDK Manager" })
  end

  -- Developer key is only needed for building.
  local key = config.options.developer_key
  if not key then
    health.warn("developer_key not set, :MonkeyC build/run is disabled", {
      "Set the `developer_key` option to a .der to enable building",
    })
  elseif vim.uv.fs_stat(key) then
    health.ok("developer_key: " .. key)
  else
    health.error("developer_key set but not found: " .. key)
  end

  -- DAP debugging is optional: it needs nvim-dap plus the adapter jars
  -- (monkeybrains.jar for the debug classes, LanguageServer.jar for gson).
  local has_dap = pcall(require, "dap")
  if not has_dap then
    health.info("nvim-dap not installed; :MonkeyC debug is unavailable")
  elseif sdk.tool(sdk_path, "monkeybrains.jar") and sdk.language_server_jar(sdk_path) then
    health.ok("DAP debug adapter (nvim-dap + SDK jars)")
  else
    health.warn("DAP debug adapter unavailable: monkeybrains.jar not found in " .. sdk_dir)
  end

  local clients = vim.lsp.get_clients({ name = "monkeyc-lsp" })
  if #clients > 0 then
    health.ok(("language server running (%d client(s) attached)"):format(#clients))
  else
    health.info("language server not attached (open a .mc file in a project to start it)")
  end
end

return M
