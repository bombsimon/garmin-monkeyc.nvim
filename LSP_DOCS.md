# LSP documentation

## How it works (server quirks)

Everything below was reverse-engineered from three sources, see
[Appendix](#appendix-how-this-was-figured-out).

### 1. `initialize` crashes on missing client capabilities

During `initialize` the server calls `.booleanValue()` on 16 client
`dynamicRegistration` capabilities **without null-checking them**, throwing a
`NullPointerException` on any the client leaves unset. The plugin forces all 16
present (`false` = static registration, which Neovim handles).

### 2. Nothing resolves without `workspaceSettings`

Even after `initialize`, hover/definition/etc. return empty until the server can
build the workspace from `initializationOptions.workspaceSettings`:

```jsonc
{
  "publishWarnings": true,
  "typeCheckMsgDisplayed": true,
  "compilerOptions": "",
  "workspaceSettings": [
    {
      "path": "/abs/path/to/project", // dir containing manifest.xml
      "jungleFiles": ["monkey.jungle"],
      // options is POSITIONAL: [typeCheckLevel, debugLogLevel, targetDevice]
      "options": ["Default", "Default", "fenix7"],
    },
  ],
}
```

- **`options[0]` (type check level)** must be one of `Default`, `Off`,
  `Gradual`, `Informative`, `Strict`. An empty/invalid value logs
  `Invalid type check level ''` and aborts the workspace build.
- **`options[1]` (debug log level)**: `Default`, `None`, `Errors Only`, `Basic`,
  `Intermediate`, `Verbose`.
- **`options[2]` (target device)** is optional (JSON `null`). The server
  resolves against a default when it's absent, so the plugin sends no device by
  default - matching the VS Code extension, which only sets a device
  (`lastBuildDevice`) after you run a build/run. Set the `device` option to pin
  an **installed** device id for device-accurate diagnostics.

### 3. macOS Dock icon

The JVM shows a Dock icon by default. Launching with
`-Dapple.awt.UIElement=true` (as the VS Code extension does) makes it a
background agent.

### 4. Hover is VS-Code-flavored HTML

Hover returns `### <code>…</code>` signatures,
`command:monkeyc.viewApiDocumentation` links (HTML `<a>` and Markdown), a `$.`
global-scope prefix, and HTML entities. `require("garmin-monkeyc").hover()`
strips these to clean Markdown. (A generic tag stripper would eat literal
`<...>` inside example code blocks, so `<code>` and `<br>` are handled
specifically.)

### 5. Function completions insert `name()` + a VS Code command

Function items carry `textEditText = "name()"` plus a client-side
`monkeyc.functionCompletion` command that, in VS Code, drops the cursor inside
the parens. The server has no `executeCommandProvider`, so Neovim can't run it,
and inserting `name()` is inconsistent across accept paths. The plugin
transforms the completion response (wrapping `client.request`, since completion
engines bypass `vim.lsp` handlers) and removes the command. By default
(`function_completion = "snippet"`) it rewrites `name()` into a `name($0)`
snippet, so confirming inserts the parens with the cursor between them, only on
confirm just like `rust-analyzer` et al. (needs a snippet engine). Set
`function_completion = "strip"` to insert just `name` instead.

### Also worth knowing

- **No completion docs / no resolve.** `completionProvider.resolveProvider` is
  `false` and items carry no `documentation`; `completionItem/resolve` throws.
  Docs are only available via `textDocument/hover`.
- **`signatureHelp` needs a `context`.** It NPEs (`-32603: Internal error.`)
  unless the request includes a non-null `context`; plain
  `vim.lsp.buf.signature_help()` sends none, so it errors on this server. Use
  `require("garmin-monkeyc").signature_help()` instead, which sends a context,
  cleans the same VS Code markup as hover, and raises the float above the
  completion menu (it's usually invoked mid-argument, where the default float
  zindex would hide it behind nvim-cmp's menu).
- **`rename` needs no prepare.** The server advertises
  `renameProvider.prepareProvider`, but `textDocument/prepareRename` NPEs
  (`-32603`) at every position; plain `textDocument/rename` works. The plugin
  drops `prepareProvider` on attach so `vim.lsp.buf.rename()` skips the broken
  prepare step.
- **First-open delay.** The first `.mc` buffer triggers a full workspace build
  (a few seconds); requests during that window return empty.

---

## Troubleshooting

The server logs its own diagnostics. Enable and view them with:

```vim
:lua vim.lsp.set_log_level("debug")
:LspLog
```

Key `window/logMessage` lines and what they mean:

| Log message                                          | Meaning / fix                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------------ |
| `Invalid type check level '' specified for root ...` | `options[0]` empty/invalid, use a valid `type_check_level`.        |
| `Unable to initialize workspace for root folder ...` | Follows the above; the workspace never built, so nothing resolves. |
| `Unable to determine workspace for file ...`         | The open file's path isn't inside any `workspaceSettings.path`.    |
| `Found workspace with root folder ... for file ...`  | Good, the file is mapped to a workspace and will be analyzed.      |
| `Building full workspace for root folder ...`        | Analysis started; wait for it to finish before expecting results.  |
| `NullPointerException ... getDynamicRegistration()`  | A probed capability is missing (see quirk 1).                      |

Quick checks on goto-definition:

- Returns `nil` → the server got no/broken `initializationOptions`.
- Returns `{}` (empty list) → the workspace didn't build (usually an invalid
  type check level or a `path` that doesn't contain the file).
- Returns a location → working.

If nothing attaches at all, check the notify warning, it prints the `sdk_path`
that was searched for `LanguageServer.jar`. Confirm `java` is on `PATH`.

---

## Appendix: how this was figured out

Three complementary sources.

**1. The jar** (`unzip` + `javap` on `LanguageServer.jar`); the protocol and
schema:

```sh
# transport + entry point
unzip -p LanguageServer.jar META-INF/MANIFEST.MF          # Main-Class: ...LSLauncher; org.eclipse.lsp4j on classpath
javap -p -c .../LSLauncher.class                          # LSPLauncher.createServerLauncher(server, System.in, System.out) = stdio

# the initializationOptions schema + the initialize NPE
javap -p    '.../LSClientUtils$InitializationOptions.class'  # fields: workspaceSettings, publishWarnings, typeCheckMsgDisplayed, compilerOptions
javap -p -c '.../LSClientUtils.class'                        # the 16 isDynamic*Supported() probes
javap -p -c '.../WorkspaceSettingsParams.class'              # options is positional: 0/1/2 = typeCheck/debugLog/device
javap -p -c '.../MonkeyCLanguageServer.class'                # which probes initialize() calls
```

**2. The VS Code extension bundle** (`dist/extension.js`, `package.json`); the
concrete values and launch details:

```sh
grep -oE "initializationOptions:\{[^}]*" dist/extension.js    # {publishWarnings, compilerOptions, workspaceSettings, typeCheckMsgDisplayed}
grep -oE "getWorkspace\(.{0,600}" dist/extension.js           # how workspaceSettings entries are built (jungle, typecheck, lastBuildDevice)
grep -oE '\["-Dapple.awt.UIElement=true".*' dist/extension.js # the Dock-hiding JVM flag
grep -oE '"custom/[A-Za-z]+"' dist/extension.js               # the custom/* notifications
# package.json contributes.configuration -> typeCheckLevel / debugLogLevel enum values, and the per-OS SDK paths
```

**3. Live probing** from Neovim, runtime behavior that isn't in either:
`client.server_capabilities` (e.g. `resolveProvider = false`,
`executeCommandProvider = nil`), a `window/logMessage` handler (the
`Invalid type check level ''` message), and raw `textDocument/hover`,
`textDocument/completion`, and `textDocument/signatureHelp` responses.
