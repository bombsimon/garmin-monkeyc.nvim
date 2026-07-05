-- Signature help for Monkey C buffers.
--
-- The server NPEs on textDocument/signatureHelp unless the request carries a
-- non-null `context` (it calls SignatureHelpContext.getTriggerCharacter() on
-- it).

local hover = require("garmin-monkeyc.hover")

local M = {}

local server_name = require("garmin-monkeyc.constants").server_name

function M.signature_help()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = server_name })

  if #clients == 0 then
    return vim.lsp.buf.signature_help()
  end

  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.context = { triggerKind = 1, isRetrigger = false } -- 1 = Invoked

  client:request("textDocument/signatureHelp", params, function(err, result)
    if err or not result or not result.signatures or vim.tbl_isempty(result.signatures) then
      return
    end

    local lines = vim.lsp.util.convert_signature_help_to_markdown_lines(result, "monkeyc", { "(", "," })

    if not lines or vim.tbl_isempty(lines) then
      return
    end

    -- Parameter docs carry the same VS Code HTML/command-links as hover; clean
    -- them. (This shifts columns, so we skip active-parameter highlighting.)
    lines = vim.split(hover.clean(table.concat(lines, "\n")), "\n")

    vim.schedule(function()
      vim.lsp.util.open_floating_preview(lines, "markdown", {
        focus_id = "textDocument/signatureHelp",
        -- Signature help is usually invoked while a completion menu is
        -- open (cursor inside a call's args). open_floating_preview
        -- defaults to zindex ~50, so it renders behind nvim-cmp's menu
        -- (zindex 1001); raise it above so it stays visible.
        -- No explicit border: inherits vim.o.winborder, like our hover.
        zindex = 1100,
      })
    end)
  end)
end

return M
