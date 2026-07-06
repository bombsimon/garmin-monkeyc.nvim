-- Resolved plugin options.
--
-- setup() populates this once; feature modules that run long after setup
-- (build/run commands) read from it instead of threading opts around.

local sdk = require("garmin-monkeyc.sdk")

local M = {}

-- Defaults live here so both the code and the README reference one list.
M.options = {
  on_attach = nil,
  capabilities = nil,
  -- one of require("garmin-monkeyc").type_check_levels
  type_check_level = "Default",
  -- compiler optimization level for builds/exports; one of
  -- require("garmin-monkeyc").optimization_levels. "Default" omits -O so the
  -- compiler uses its own default (matching VS Code's default setting).
  optimization_level = "Default",
  -- "snippet" (name() with cursor inside) | "strip" (just name)
  function_completion = "snippet",
  -- "Sdks" directory; defaults per-OS via sdk.default_sdk_path()
  sdk_path = nil,
  -- device id to type-check against; nil = none (like VS Code before a build)
  device = nil,
  -- absolute path to the developer key (.der) used to sign builds (-y);
  -- required by :MonkeyC build / build-for-device / run / test
  developer_key = nil,
}

function M.setup(opts)
  M.options = vim.tbl_extend("force", M.options, opts or {})

  M.options.sdk_path = M.options.sdk_path or sdk.default_sdk_path()

  if M.options.developer_key then
    M.options.developer_key = vim.fn.expand(M.options.developer_key)
  end

  return M.options
end

return M
