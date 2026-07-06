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

function M.run(device)
  return require("garmin-monkeyc.build").run(device)
end

function M.test(device)
  return require("garmin-monkeyc.build").test(device)
end

function M.export(output)
  return require("garmin-monkeyc.build").export(output)
end

function M.logs()
  return require("garmin-monkeyc.build").logs()
end

function M.cancel()
  return require("garmin-monkeyc.build").cancel()
end

function M.generate_key(path)
  return require("garmin-monkeyc.build").generate_key(path)
end

function M.new_project(dir)
  return require("garmin-monkeyc.build").new_project(dir)
end

function M.regenerate_uuid()
  return require("garmin-monkeyc.build").regenerate_uuid()
end

-- SDK tool / documentation launchers.
function M.docs()
  return require("garmin-monkeyc.tools").docs()
end

function M.samples()
  return require("garmin-monkeyc.tools").samples()
end

function M.sdk_manager()
  return require("garmin-monkeyc.tools").sdk_manager()
end

function M.monkey_graph()
  return require("garmin-monkeyc.tools").monkey_graph()
end

function M.monkey_motion()
  return require("garmin-monkeyc.tools").monkey_motion()
end

function M.era()
  return require("garmin-monkeyc.tools").era()
end

function M.clean()
  return require("garmin-monkeyc.build").clean()
end

return M
