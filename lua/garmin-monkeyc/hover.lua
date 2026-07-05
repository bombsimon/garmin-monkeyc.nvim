-- Cleaned hover for Monkey C buffers.
--
-- Hover contents come back as HTML/Markdown aimed at VS Code: the signature is
-- wrapped in `### <code>`, symbols are `command:monkeyc.viewApiDocumentation`
-- links (both HTML anchors and Markdown links) that only work inside VS Code,
-- and a few HTML entities leak through. vim.lsp.buf.hover() renders that
-- verbatim and offers no transform hook, so request and render it ourselves.

local M = {}

local server_name = require("garmin-monkeyc.constants").server_name

function M.clean(value)
  -- Drop HTML anchor links and Markdown command links, keeping visible text.
  value = value:gsub("<a%s+href=[^>]->", ""):gsub("</a>", "")
  value = value:gsub("%[([^%]]-)%]%(command:[^%)]*%)", "%1")

  -- Render the `### <code>signature</code>` heading as a fenced code block, and
  -- any remaining inline <code> as inline code. Avoid a generic tag stripper so
  -- literal `<...>` inside example code blocks (e.g. resources.xml) survives.
  value = value:gsub("###%s*<code>(.-)</code>", "```monkeyc\n%1\n```")
  value = value:gsub("<code>(.-)</code>", "`%1`")
  value = value:gsub("<br%s*/?>", "\n")

  -- Remove the `$.` global-scope prefix.
  value = value:gsub("%$%.", "")

  -- Decode the HTML entities the server emits.
  value = value:gsub("&nbsp;", " "):gsub("&mdash;", "—"):gsub("&gt;", ">"):gsub("&lt;", "<"):gsub("&amp;", "&")

  -- Symbols without a doc body still end in a `---` separator; drop that
  -- trailing rule so the float doesn't show a dangling divider.
  value = value:gsub("%s*\n%-%-%-%s*$", "")

  return value
end

-- Cleaned hover. Falls back to the builtin hover when no Monkey C client is
-- attached, so it is safe to map unconditionally.
function M.hover()
  local clients = vim.lsp.get_clients({ bufnr = 0, name = server_name })

  if #clients == 0 then
    return vim.lsp.buf.hover()
  end

  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

  client:request("textDocument/hover", params, function(_, result)
    vim.schedule(function()
      if not (result and result.contents) then
        return
      end

      local value = type(result.contents) == "table" and result.contents.value or result.contents
      local lines = vim.lsp.util.convert_input_to_markdown_lines(M.clean(value))

      if vim.tbl_isempty(lines) then
        return
      end

      -- No explicit border: open_floating_preview falls back to vim.o.winborder,
      -- so the float inherits the user's global border setting.
      vim.lsp.util.open_floating_preview(lines, "markdown", {
        focus_id = "textDocument/hover",
      })
    end)
  end)
end

return M
