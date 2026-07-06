-- Language server wiring for Garmin's Connect IQ (Monkey C) LanguageServer.jar.
--
-- The jar is a plain stdio LSP4J server, but several quirks stop it working out
-- of the box; each workaround below notes the quirk it addresses.

local sdk = require("garmin-monkeyc.sdk")

local M = {}

local server_name = require("garmin-monkeyc.constants").server_name

-- Quirk: during initialize the server calls .booleanValue() on these client
-- dynamicRegistration capabilities without null-checking them, so it throws a
-- NullPointerException on any Neovim leaves unset. Forcing each present (false =
-- static registration, which Neovim handles) avoids it.
local dynamic_registration_capabilities = {
  textDocument = {
    "synchronization",
    "foldingRange",
    "hover",
    "declaration",
    "definition",
    "implementation",
    "typeDefinition",
    "references",
    "typeHierarchy",
    "documentHighlight",
    "documentSymbol",
    "completion",
    "signatureHelp",
    "rename",
    "callHierarchy",
  },
  workspace = { "symbol" },
}

local function with_dynamic_registration(capabilities)
  local overrides = {}

  for scope, names in pairs(dynamic_registration_capabilities) do
    overrides[scope] = {}

    for _, name in ipairs(names) do
      overrides[scope][name] = { dynamicRegistration = false }
    end
  end

  return vim.tbl_deep_extend("force", capabilities or {}, overrides)
end

-- Valid type check levels the server accepts. An empty or unknown value makes
-- it reject the workspace, after which nothing resolves.
--
--   "Default"     - the SDK default type checking behaviour
--   "Off"         - disable type checking
--   "Gradual"     - type match failures are errors, ambiguity is ignored
--   "Informative" - type match failures are errors, ambiguity is a warning
--   "Strict"      - type match failures and ambiguity are both errors
M.type_check_levels = { "Default", "Off", "Gradual", "Informative", "Strict" }

-- Quirk: the server refuses to build a workspace (then resolves nothing) unless
-- it gets a project path, jungle files, a valid type check level and a target
-- device. These are per-project, so build them from the resolved root.
local function build_workspace_settings(root, type_check_level, device)
  local directory = sdk.project_directory(root)

  return {
    {
      path = directory,
      jungleFiles = sdk.jungle_files(directory),
      -- options is positional: { typeCheckLevel, debugLogLevel, targetDevice }.
      -- Like the VS Code extension, send no device by default (vim.NIL = JSON
      -- null), the server still resolves against a default. Set opts.device to
      -- pin a specific device (e.g. for device-accurate Strict diagnostics).
      options = { type_check_level, "Default", device or vim.NIL },
    },
  }
end

-- Quirk: function completions come back as `name()` plus a client-side
-- `monkeyc.functionCompletion` command that (only in VS Code) drops the cursor
-- inside the parens. Neovim can't run that command, and inserting `name()`
-- unconditionally is inconsistent across accept paths. Rewrite each item:
--
--   "snippet" (default) - turn `name()` into a `name($0)` snippet so confirming
--                         inserts the parens with the cursor between them (like
--                         rust-analyzer et al.); requires a snippet engine.
--   "strip"             - drop the parens, inserting just `name`.
--
-- Either way the VS Code-only command is removed so it isn't sent to a server
-- with no executeCommandProvider.
local snippet_insert_text_format = 2 -- lsp.InsertTextFormat.Snippet

local function transform_function_calls(result, mode)
  local items = result and (result.items or result)

  if type(items) ~= "table" then
    return
  end

  for _, item in ipairs(items) do
    item.command = nil

    local rewrote = false

    local function convert(text)
      if type(text) ~= "string" or text:sub(-2) ~= "()" then
        return text
      end

      rewrote = true

      if mode == "strip" then
        return text:sub(1, -3)
      end

      return text:sub(1, -3) .. "($0)"
    end

    item.textEditText = convert(item.textEditText)
    item.insertText = convert(item.insertText)

    if item.textEdit and type(item.textEdit.newText) == "string" then
      item.textEdit.newText = convert(item.textEdit.newText)
    end

    if rewrote and mode ~= "strip" then
      item.insertTextFormat = snippet_insert_text_format
    end
  end
end

-- There is no official response-middleware hook, and vim.lsp.buf/handlers are
-- bypassed by most completion engines (nvim-cmp, blink), so transform the
-- completion response by wrapping the client's request method directly. Guarded
-- so it wraps once per client even though on_attach fires per buffer.
local function install_completion_transform(client, mode)
  if client._garmin_completion_wrapped then
    return
  end

  client._garmin_completion_wrapped = true

  local request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if method == "textDocument/completion" and type(handler) == "function" then
      local inner = handler
      handler = function(err, result, ctx, config)
        if not err then
          transform_function_calls(result, mode)
        end

        return inner(err, result, ctx, config)
      end
    end

    return request(self, method, params, handler, bufnr)
  end
end

-- opts:
--   on_attach            - LSP on_attach callback (optional)
--   capabilities         - base client capabilities (optional)
--   type_check_level     - one of M.type_check_levels; defaults to "Default"
--   function_completion  - "snippet" (default) inserts name() with the cursor
--                          between the parens; "strip" inserts just name
--   sdk_path             - the "Sdks" directory to search for the language
--                          server; defaults to sdk.default_sdk_path()
--   device               - target device id to type-check against; defaults to
--                          none (like VS Code before its first build)
function M.setup(opts)
  opts = opts or {}

  local type_check_level = opts.type_check_level or "Default"
  local function_completion = opts.function_completion or "snippet"
  local sdk_path = opts.sdk_path or sdk.default_sdk_path()
  local device = opts.device

  if not vim.tbl_contains(M.type_check_levels, type_check_level) then
    vim.notify(
      ('garmin-monkeyc: invalid type_check_level %q, falling back to "Default"'):format(type_check_level),
      vim.log.levels.WARN
    )

    type_check_level = "Default"
  end

  local jar = sdk.language_server_jar(sdk_path)

  if not jar then
    vim.notify(("garmin-monkeyc: no LanguageServer.jar found under %s"):format(sdk_path), vim.log.levels.WARN)

    return
  end

  vim.lsp.config(server_name, {
    -- -Dapple.awt.UIElement=true marks the JVM as a background agent on macOS
    -- so it never shows a Dock icon or menu bar (matches how the VS Code
    -- extension launches it).
    cmd = { "java", "-Dapple.awt.UIElement=true", "-jar", jar },
    filetypes = { "monkeyc" },
    root_markers = { "manifest.xml", ".git" },
    capabilities = with_dynamic_registration(opts.capabilities),
    on_attach = function(client, bufnr)
      install_completion_transform(client, function_completion)

      -- Quirk: the server advertises rename prepareProvider, but its
      -- prepareRename NPEs (-32603) at every position, while plain
      -- textDocument/rename works. Drop prepareProvider so vim.lsp.buf.rename()
      -- skips the broken prepare step and renames directly.
      if type(client.server_capabilities.renameProvider) == "table" then
        client.server_capabilities.renameProvider.prepareProvider = nil
      end

      if opts.on_attach then
        opts.on_attach(client, bufnr)
      end
    end,
    before_init = function(params, config)
      params.initializationOptions = {
        publishWarnings = true,
        typeCheckMsgDisplayed = true,
        compilerOptions = "",
        workspaceSettings = build_workspace_settings(config.root_dir, type_check_level, device),
      }
    end,
  })

  vim.lsp.enable(server_name)
end

return M
