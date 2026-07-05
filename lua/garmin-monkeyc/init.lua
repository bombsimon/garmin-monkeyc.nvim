-- garmin-monkeyc.nvim: Neovim integration for Garmin's Connect IQ (Monkey C)
-- language server.
--
-- Usage:
--   require("garmin-monkeyc").setup({
--     on_attach = ...,          -- optional
--     capabilities = ...,       -- optional (e.g. cmp_nvim_lsp.default_capabilities())
--     type_check_level = "Default",
--   })
--   -- map require("garmin-monkeyc").hover to your hover key for cleaned docs.

local M = {}

-- Re-exported so callers can validate/offer the values (see lsp.lua).
M.type_check_levels = require("garmin-monkeyc.lsp").type_check_levels

function M.setup(opts)
  -- Resolve options once; feature modules read them from config.
  local options = require("garmin-monkeyc.config").setup(opts)

  require("garmin-monkeyc.lsp").setup(options)
  require("garmin-monkeyc.build").setup()
end

function M.hover()
  return require("garmin-monkeyc.hover").hover()
end

function M.signature_help()
  return require("garmin-monkeyc.signature").signature_help()
end

-- Exposed for keymaps; the :MonkeyC command is the usual entry point. A nil
-- device prompts for one (from the manifest).
function M.build()
  return require("garmin-monkeyc.build").build()
end

function M.build_for_device(device)
  return require("garmin-monkeyc.build").build_for_device(device)
end

function M.run_for_device(device)
  return require("garmin-monkeyc.build").run_for_device(device)
end

return M
