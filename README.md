# garmin-monkeyc.nvim

Neovim port of the [official Monkey C VS Code extension][vscode], with LSP
support for the language server shipped as `LanguageServer.jar` inside the
[Connect IQ SDK][ciq].

For more details around LSP documentation, see [LSP_DOCS.md][lsp-docs].

## Feature parity

Tracking parity with the [official VS Code extension][vscode].

- [x] Language server - hover, completion, goto-definition, references, rename,
      document/workspace symbols, folding, call/type hierarchy (see
      [LSP capabilities](#lsp-capabilities))
- [x] Build for device - `:MonkeyC build-for-device [device]`
- [x] Run in simulator - `:MonkeyC run [device]`
- [x] Build current project - `:MonkeyC build`
- [x] Clean project - `:MonkeyC clean`
- [x] Run unit tests - `:MonkeyC test [device]`
- [x] Export project (`.iq` for the Connect IQ Store) - `:MonkeyC export [path]`
- [x] New project - `:MonkeyC new-project [dir]`
- [x] Generate a developer key - `:MonkeyC generate-key [path]`
- [x] Verify installation - `:checkhealth garmin-monkeyc`
- [ ] Edit manifest (products, permissions, languages, application, annotations)
- [x] Regenerate UUID - `:MonkeyC regenerate-uuid`
- [ ] Debugger (DAP)
- [ ] Open SDK Manager
- [ ] View documentation / open samples
- [ ] External tools (Monkey Graph, Monkey Motion, ERA Viewer)
- [ ] Configure barrel
- [ ] Native pairing / complication launch

## Requirements

- Neovim 0.11+ (uses `vim.lsp.config` / `vim.lsp.enable`).
- A Garmin [Connect IQ SDK][ciq] installed via the SDK Manager, with at least
  one device downloaded.
- `java` on `PATH`.

The SDK location is detected per OS (matching where the Connect IQ SDK Manager
installs):

| OS          | default `Sdks` directory                                  |
| ----------- | --------------------------------------------------------- |
| macOS       | `$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks` |
| Windows     | `$APPDATA/Garmin/ConnectIQ/Sdks`                          |
| Linux/other | `$HOME/.Garmin/ConnectIQ/Sdks` (no official SDK Manager)  |

Override it with the `sdk_path` option if your install differs.

## Installation

With [lazy.nvim]:

```lua
{
  "bombsimon/garmin-monkeyc.nvim",
  ft = "monkeyc",
  config = function()
    require("garmin-monkeyc").setup({
      capabilities = require("cmp_nvim_lsp").default_capabilities(),
      on_attach = my_on_attach,
      type_check_level = "Default", -- Default | Off | Gradual | Informative | Strict
      function_completion = "snippet", -- "snippet" (cursor inside ()) | "strip"
      sdk_path = nil, -- path to SDK installation, use if not in OS default path
      device = nil, -- device id for type-checking (leave blank unless needed)
      developer_key = "~/.garmin/developer_key.der", -- your developer key
    })
  end,
}
```

The plugin registers `.mc` as filetype `monkeyc` itself (via `ftdetect/`,
sourced at startup). Neovim's builtin runtime otherwise detects `.mc` as `m4`.

### Cleaned hover

`vim.lsp.buf.hover()` renders the server's HTML verbatim. Map the plugin's hover
instead for cleaned Markdown:

```lua
vim.keymap.set("n", "K", require("garmin-monkeyc").hover)
```

It falls back to the builtin hover when no Monkey C client is attached, so it's
safe to map globally.

### Signature help

`vim.lsp.buf.signature_help()` errors on this server (it sends no `context`).
Map the plugin's instead:

```lua
vim.keymap.set({ "n", "i" }, "<C-k>", require("garmin-monkeyc").signature_help)
```

Also falls back to the builtin when no Monkey C client is attached.

## Configuration

| option                | default            | meaning                                                                                                     |
| --------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `capabilities`        | `nil`              | base client capabilities; merged with the required overrides                                                |
| `on_attach`           | `nil`              | called on attach (after the plugin's own setup)                                                             |
| `type_check_level`    | `"Default"`        | one of `require("garmin-monkeyc").type_check_levels`                                                        |
| `function_completion` | `"snippet"`        | `"snippet"` inserts `name()` with the cursor inside (needs a snippet engine); `"strip"` inserts just `name` |
| `sdk_path`            | per-OS (see above) | the `Sdks` directory to search for `LanguageServer.jar`                                                     |
| `device`              | none               | device id to type-check against; default matches VS Code (no device until you pick one)                     |
| `developer_key`       | `nil`              | path to the developer key (`.der`) used to sign builds                                                      |

---

## Building and running

Requires a **developer key** to pass to the compiler when building, set
`developer_key`. No key yet? Run `:MonkeyC generate-key` (needs `openssl`).

| command                              | action                                                       |
| ------------------------------------ | ------------------------------------------------------------ |
| `:MonkeyC build`                     | build `bin/<project>.prg` for the default device (no prompt) |
| `:MonkeyC build-for-device [device]` | compile `bin/<project>.prg` for `device`                     |
| `:MonkeyC run [device]`              | build, launch the simulator, and push the app to it          |
| `:MonkeyC test [device]`             | build unit tests (`-t`) and run them in the simulator        |
| `:MonkeyC export [path]`             | package a `.iq` for the store (all products, release)        |
| `:MonkeyC generate-key [path]`       | generate a developer key (RSA 4096, PKCS8 DER) via openssl   |
| `:MonkeyC new-project [dir]`         | scaffold a new project from an SDK template (prompts)        |
| `:MonkeyC regenerate-uuid`           | give the manifest a fresh application id                     |
| `:MonkeyC clean`                     | remove the `bin/` build output directory                     |
| `:MonkeyC logs`                      | open the last build's full output in a split                 |
| `:MonkeyC cancel`                    | stop the running build                                       |

Builds stream progress (e.g. `export` packages every product, so you get
`exporting (42/234 devices)` on the command line). The full compiler output,
including all warnings, is kept for `:MonkeyC logs`; on failure the errors also
go to the quickfix list.

`:MonkeyC build` uses the `device` option as the default device, falling back to
the first product in `manifest.xml`.

### Health check

Run `:checkhealth garmin-monkeyc` to verify the setup. It reports the detected
SDK, `LanguageServer.jar`, the `monkeyc`/`monkeydo`/`connectiq` tools, `java`, the
installed device count, the developer key, and whether the language server is
attached.

If `[device]` is omitted you get a picker of the devices declared in
`manifest.xml`, showing friendly names (e.g. `fēnix® 7 / quatix® 7`). The picker
uses `vim.ui.select`, so with [telescope-ui-select] / [dressing.nvim] /
[snacks.nvim] it becomes a fuzzy Telescope picker automatically. Device ids also
tab-complete on the command line. Build errors (including type-check errors) go
to the quickfix list.

The type-check level for builds follows the `type_check_level` option (`Strict`
maps to the compiler's `-l 3`, so a `Strict` build fails on type errors.

---

## LSP capabilities

The bundled `LanguageServer.jar` doesn't work with a stock LSP client. To get it
usable, the plugin:

- Auto-discovers the newest installed SDK's `LanguageServer.jar`.
- Works around the server's `initialize` NPE (it calls `.booleanValue()` on
  client capabilities it never null-checks).
- Builds the per-project `workspaceSettings` the server needs before it resolves
  anything (project path, jungle files, type check level, device).
- Cleans the server's VS Code-flavored HTML hover into plain Markdown.
- Rewrites `name()` function completions into `name($0)` snippets so confirming
  drops the cursor between the parens (matching the VS Code extension).

With that in place, this is what the server implements (from its `initialize`
capabilities and the jar's service methods) and how it behaves in Neovim:

| Feature                                                                     | Status    | Notes                                                                                                             |
| --------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------- |
| definition / declaration / typeDefinition / implementation                  | ✅ native | `Ctrl-]` or your goto-definition binding                                                                          |
| references                                                                  | ✅ native | `grr`                                                                                                             |
| documentHighlight                                                           | ✅ native |                                                                                                                   |
| documentSymbol / workspaceSymbol                                            | ✅ native | `gO`, `:lua vim.lsp.buf.workspace_symbol()`                                                                       |
| foldingRange                                                                | ✅ native |                                                                                                                   |
| callHierarchy (incoming/outgoing)                                           | ✅ native |                                                                                                                   |
| typeHierarchy (super/sub)                                                   | ✅ native |                                                                                                                   |
| hover                                                                       | ⚙️ plugin | server returns VS Code HTML; use `require("garmin-monkeyc").hover()`                                              |
| signatureHelp                                                               | ⚙️ plugin | NPEs without a `context`; use `require("garmin-monkeyc").signature_help()`. Only shows **inside** a call's parens |
| completion                                                                  | ⚙️ plugin | no `resolveProvider`, no item docs; parens rewritten                                                              |
| rename                                                                      | ⚙️ plugin | `prepareRename` NPEs; the plugin drops `prepareProvider` so `grn` renames directly                                |
| codeAction, formatting, semanticTokens, inlayHint, codeLens, executeCommand | ❌ absent | the server doesn't implement these                                                                                |

"native" features need nothing from this plugin beyond the client being
attached, your normal LSP keymaps just work.

[ciq]: https://developer.garmin.com/connect-iq/overview/
[dressing.nvim]: https://github.com/stevearc/dressing.nvim
[lazy.nvim]: https://github.com/folke/lazy.nvim
[lsp-docs]: ./LSP_DOCS.md
[snacks.nvim]: https://github.com/folke/snacks.nvim
[telescope-ui-select]: https://github.com/nvim-telescope/telescope-ui-select.nvim
[vscode]: https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c
