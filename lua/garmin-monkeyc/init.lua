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
	require("garmin-monkeyc.lsp").setup(opts)
end

function M.hover()
	return require("garmin-monkeyc.hover").hover()
end

function M.signature_help()
	return require("garmin-monkeyc.signature").signature_help()
end

return M
