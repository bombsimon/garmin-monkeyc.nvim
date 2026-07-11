-- Build and run Monkey C projects with the SDK's monkeyc compiler and monkeydo
-- simulator runner, mirroring the VS Code extension's "Build for Device" and
-- run flows.

local config = require("garmin-monkeyc.config")
local sdk = require("garmin-monkeyc.sdk")
local tools = require("garmin-monkeyc.tools")
local manifest = require("garmin-monkeyc.manifest")

local M = {}

-- Map our type_check_level to the compiler's -l value. "Default" omits -l so the
-- compiler uses its own default.
local typecheck_flag = {
  Off = "0",
  Gradual = "1",
  Informative = "2",
  Strict = "3",
}

-- Map our optimization_level to the compiler's -O value, matching the VS Code
-- extension's monkeyC.optimizationLevel setting. "Default" omits -O so the
-- compiler uses its own default (level 1).
local optimization_flag = {
  None = "0",
  Basic = "1",
  Fast = "2",
  Slow = "3",
}

local function notify(message, level)
  vim.notify("garmin-monkeyc: " .. message, level or vim.log.levels.INFO)
end

-- Transient progress on the command line (does not spam :messages).
local function echo(message)
  vim.api.nvim_echo({ { "garmin-monkeyc: " .. message } }, false, {})
end

-- Output of the most recent build, shown by :MonkeyC logs (see M.logs).
local log_lines = {}
local log_bufnr

-- The running build process (vim.system handle) and whether it was cancelled,
-- so :MonkeyC cancel can stop it and we can tell cancel from failure.
local current_build
local cancelled = false

-- Refresh the log buffer if it is open, keeping any window scrolled to the end.
local function render_log()
  if not (log_bufnr and vim.api.nvim_buf_is_loaded(log_bufnr)) then
    return
  end

  vim.bo[log_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(log_bufnr, 0, -1, false, log_lines)
  vim.bo[log_bufnr].modifiable = false

  for _, win in ipairs(vim.fn.win_findbuf(log_bufnr)) do
    vim.api.nvim_win_set_cursor(win, { #log_lines, 0 })
  end
end

-- Project directory for the current buffer (the dir holding manifest.xml).
local function project_directory()
  local root = vim.fs.root(0, { "manifest.xml", ".git" }) or vim.uv.cwd()

  return sdk.project_directory(root)
end

-- Test builds go to a separate prg (matching the VS Code extension) so they
-- don't clobber the regular build.
local function output_prg(directory, device, unit_test)
  local name = vim.fs.basename(directory)
  local file = unit_test and ("test_%s_%s.prg"):format(device, name) or (name .. ".prg")

  return vim.fs.joinpath(directory, "bin", file)
end

-- Compile the project. opts:
--   device     - target device (-d); omit to package all products (export)
--   unit_test  - build with -t (unit tests) to a separate prg
--   package    - build a distributable application package (-e -r, .iq)
--   output     - override the output path
--   directory  - project directory to build (defaults to the current project)
--   label      - progress message ("building for X" by default)
--   on_success - called with the output path
-- Errors go to the quickfix list.
local function compile(opts)
  opts = opts or {}

  if current_build then
    return notify("a build is already running (:MonkeyC cancel to stop it)", vim.log.levels.WARN)
  end

  local options = config.options

  if not (options.developer_key and vim.uv.fs_stat(options.developer_key)) then
    return notify("set developer_key to a valid .der to build (see :MonkeyC or the README)", vim.log.levels.ERROR)
  end

  local jar = sdk.tool(options.sdk_path, "monkeybrains.jar")

  if not jar then
    return notify("monkeybrains.jar not found under " .. options.sdk_path, vim.log.levels.ERROR)
  end

  local directory = opts.directory or project_directory()
  local output = opts.output or output_prg(directory, opts.device, opts.unit_test)

  vim.fn.mkdir(vim.fs.dirname(output), "p")

  -- Invoke the compiler jar directly (like the VS Code extension) rather than
  -- the monkeyc shell wrapper, so the process we spawn is the JVM itself and
  -- :MonkeyC cancel can kill it. -Dapple.awt.UIElement=true keeps it off the
  -- macOS Dock.
  local args = {
    "java",
    "-Xms1g",
    "-Dfile.encoding=UTF-8",
    "-Dapple.awt.UIElement=true",
    "-jar",
    jar,
    "-f",
    table.concat(sdk.jungle_files(directory), ";"),
    "-o",
    output,
    "-y",
    options.developer_key,
    "-w",
  }

  if opts.device then
    vim.list_extend(args, { "-d", opts.device })
  end

  if opts.unit_test then
    table.insert(args, "-t")
  end

  if opts.package then
    vim.list_extend(args, { "-e", "-r" })
  end

  local flag = typecheck_flag[options.type_check_level]
  if flag then
    vim.list_extend(args, { "-l", flag })
  end

  local optimization = optimization_flag[options.optimization_level]
  if optimization then
    vim.list_extend(args, { "-O", optimization })
  end

  local label = opts.label or ("building for " .. opts.device)
  notify(label .. "…")

  -- Stream output so we can show per-device progress and keep a full log.
  -- monkeyc prints "N OUT OF M DEVICES BUILT" as it packages each product.
  local header = table.concat(args, " ")
  local chunks = {}

  local function on_output(_, data)
    if not data then
      return
    end

    chunks[#chunks + 1] = data

    vim.schedule(function()
      local text = table.concat(chunks)
      log_lines = vim.split(header .. "\n\n" .. text, "\n", { trimempty = false })
      render_log()

      local built, total
      for n, m in text:gmatch("(%d+) OUT OF (%d+) DEVICES BUILT") do
        built, total = n, m
      end

      if built then
        echo(("%s (%s/%s devices)"):format(label, built, total))
      end
    end)
  end

  current_build = vim.system(
    args,
    { text = true, cwd = directory, stdout = on_output, stderr = on_output },
    function(result)
      vim.schedule(function()
        current_build = nil

        if cancelled then
          cancelled = false

          return notify("build cancelled")
        end

        if result.code == 0 then
          notify(("built %s"):format(output))

          if opts.on_success then
            opts.on_success(output)
          end
        else
          notify("build failed (see :MonkeyC logs)", vim.log.levels.ERROR)

          vim.fn.setqflist({}, " ", { title = "MonkeyC build", lines = log_lines })
          vim.cmd("botright copen")
        end
      end)
    end
  )
end

-- Launch the simulator (if needed) and push the built prg to it. opts.unit_test
-- runs the app's unit tests (monkeydo -t).
local function run_in_simulator(device, prg, opts)
  opts = opts or {}

  local options = config.options
  local connectiq = sdk.tool(options.sdk_path, "connectiq")
  local monkeydo = sdk.tool(options.sdk_path, "monkeydo")

  if not (connectiq and monkeydo) then
    return notify("connectiq/monkeydo not found under " .. options.sdk_path, vim.log.levels.ERROR)
  end

  -- Launch the simulator; it's a no-op if already running. monkeydo needs it
  -- up, so give it a moment before pushing the executable.
  vim.system({ connectiq })

  notify("starting simulator…")

  local monkeydo_args = { monkeydo, prg, device }
  if opts.unit_test then
    table.insert(monkeydo_args, "-t")
  end

  vim.defer_fn(function()
    vim.system(monkeydo_args, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          notify(("%s on %s simulator"):format(opts.unit_test and "running tests" or "running", device))
        else
          notify("run failed (is the simulator running?)", vim.log.levels.ERROR)
        end
      end)
    end)
  end, 3000)
end

-- Prompt for a device from the manifest via vim.ui.select. With
-- telescope-ui-select (or dressing.nvim) installed this becomes a fuzzy picker
-- automatically; otherwise the builtin select is used.
function M.pick_device(callback)
  local devices = sdk.manifest_devices(project_directory())

  if #devices == 0 then
    return notify("no <iq:product> devices found in manifest.xml", vim.log.levels.WARN)
  end

  vim.ui.select(devices, {
    prompt = "Monkey C: build for device",
    format_item = function(id)
      local name = sdk.friendly_name(config.options.sdk_path, id)

      return name and ("%s  (%s)"):format(name, id) or id
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

function M.build_for_device(device)
  if device and device ~= "" then
    return compile({ device = device })
  end

  M.pick_device(function(chosen)
    compile({ device = chosen })
  end)
end

-- Build a debuggable (non-release) prg for the device and call on_success(prg).
-- The compiler emits <prg>.debug.xml alongside it. opts.directory builds another
-- project, opts.label overrides the progress message. Exposed for the DAP module.
function M.build_debug(device, on_success, opts)
  opts = opts or {}

  compile({
    device = device,
    directory = opts.directory,
    label = opts.label or ("building for debug on " .. device),
    on_success = on_success,
  })
end

-- Build and run in the simulator.
function M.run(device)
  local function build_and_run(chosen)
    compile({
      device = chosen,
      on_success = function(prg)
        run_in_simulator(chosen, prg)
      end,
    })
  end

  if device and device ~= "" then
    return build_and_run(device)
  end

  M.pick_device(build_and_run)
end

-- Build the project's unit tests and run them in the simulator (monkeyc -t +
-- monkeydo -t).
function M.test(device)
  local function build_and_test(chosen)
    compile({
      device = chosen,
      unit_test = true,
      on_success = function(prg)
        run_in_simulator(chosen, prg, { unit_test = true })
      end,
    })
  end

  if device and device ~= "" then
    return build_and_test(device)
  end

  M.pick_device(build_and_test)
end

-- Build a distributable application package (.iq) for the Connect IQ Store:
-- all products, release build. {output} may be a file or directory; defaults to
-- bin/<project>.iq.
function M.export(output)
  local directory = project_directory()
  local name = vim.fs.basename(directory)

  if output and output ~= "" then
    output = vim.fn.expand(output)

    if vim.fn.isdirectory(output) == 1 then
      output = vim.fs.joinpath(output, name .. ".iq")
    end
  else
    output = vim.fs.joinpath(directory, "bin", name .. ".iq")
  end

  compile({
    package = true,
    output = output,
    label = "exporting " .. vim.fs.basename(output),
  })
end

-- Build the current project without prompting, using a default device: the
-- `device` option if set, else the first product in the manifest.
function M.build()
  local device = config.options.device or sdk.manifest_devices(project_directory())[1]

  if not device then
    return notify("no default device; set the `device` option or add products to manifest.xml", vim.log.levels.ERROR)
  end

  compile({ device = device })
end

-- Remove the build output directory (bin/), like VS Code's "Clean Project".
function M.clean()
  local bin = vim.fs.joinpath(project_directory(), "bin")

  if not vim.uv.fs_stat(bin) then
    return notify("nothing to clean (no bin/)")
  end

  vim.fn.delete(bin, "rf")
  notify("removed " .. bin)
end

-- Open all diagnostics in the quickfix (e.g. the errors that block rename), for
-- users without a dedicated diagnostics UI.
function M.diagnostics()
  vim.diagnostic.setqflist({ open = true })
end

-- Generate a developer key (RSA 4096, PKCS8 DER, like the VS Code extension)
-- via openssl. {path} defaults to the developer_key option, else
-- ~/.ciq/developer_key.der. Refuses to overwrite an existing key.
function M.generate_key(path)
  if vim.fn.executable("openssl") == 0 then
    return notify("openssl not found on PATH (needed to generate a key)", vim.log.levels.ERROR)
  end

  local output = (path and path ~= "" and vim.fn.expand(path))
    or config.options.developer_key
    or vim.fn.expand("~/.ciq/developer_key.der")

  if vim.uv.fs_stat(output) then
    return notify("a key already exists at " .. output .. " (delete it first to regenerate)", vim.log.levels.WARN)
  end

  vim.fn.mkdir(vim.fs.dirname(output), "p")

  notify("generating developer key…")

  local function fail(stderr)
    notify("key generation failed: " .. (stderr or ""), vim.log.levels.ERROR)
  end

  -- monkeyc wants a PKCS#8 DER RSA key (the same as Node's crypto pkcs8/der
  -- output that the VS Code extension produces). genrsa emits a PKCS#1 key, so
  -- pipe it through pkcs8 to wrap and DER-encode it. openssl genpkey's encoding
  -- is rejected by the compiler ("Unable to decode key"), so avoid it.
  vim.system({ "openssl", "genrsa", "4096" }, { text = true }, function(generated)
    vim.schedule(function()
      if generated.code ~= 0 then
        return fail(generated.stderr)
      end

      local convert = { "openssl", "pkcs8", "-topk8", "-inform", "PEM", "-outform", "DER", "-nocrypt", "-out", output }

      vim.system(convert, { text = true, stdin = generated.stdout }, function(converted)
        vim.schedule(function()
          if converted.code ~= 0 then
            return fail(converted.stderr)
          end

          -- Use it for the rest of this session; suggest persisting it.
          local persist = config.options.developer_key ~= output
          config.options.developer_key = output

          notify(
            ("developer key written to %s%s"):format(
              output,
              persist and (' (set developer_key = "' .. output .. '")') or ""
            )
          )
        end)
      end)
    end)
  end)
end

-- Literal (non-pattern) find/replace, escaping magic in the pattern and % in
-- the replacement so user-supplied names are safe.
local function replace_all(text, find, repl)
  local pattern = find:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")

  return (text:gsub(pattern, (repl:gsub("%%", "%%%%"))))
end

-- Random v4 UUID (for the manifest application id).
local function uuid()
  math.randomseed(vim.uv.hrtime())

  return (
    ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
      return ("%x"):format(c == "x" and math.random(0, 15) or math.random(8, 11))
    end)
  )
end

-- App types we scaffold (each has an SDK template with the standard
-- app/view/delegate placeholder set).
local new_project_types = { "watch-app", "watchface", "datafield", "widget" }

local function scaffold(name, app_type, dir)
  local template = sdk.template_dir(config.options.sdk_path, app_type)

  if not template then
    return notify("no template found for " .. app_type, vim.log.levels.ERROR)
  end

  if vim.uv.fs_stat(dir) then
    return notify(dir .. " already exists", vim.log.levels.ERROR)
  end

  vim.fn.mkdir(vim.fs.dirname(dir), "p")

  local copied = vim.fn.system({ "cp", "-R", template, dir })
  if vim.v.shell_error ~= 0 then
    return notify("failed to copy template: " .. copied, vim.log.levels.ERROR)
  end

  -- Class names derive from a PascalCase base of the project name.
  local base = name:gsub("[^%w]", "")
  base = base:sub(1, 1):upper() .. base:sub(2)
  if base == "" or base:match("^%d") then
    base = "App" .. base
  end

  local subs = {
    ["${appName}"] = name,
    ["${appClassName}"] = base .. "App",
    ["${viewClassName}"] = base .. "View",
    ["${delegateClassName}"] = base .. "Delegate",
    ["${menuDelegateClassName}"] = base .. "MenuDelegate",
  }

  for _, file in
    ipairs(vim.fs.find(function()
      return true
    end, { path = dir, type = "file", limit = math.huge }))
  do
    if file:match("%.mc$") or file:match("%.xml$") or file:match("%.jungle$") then
      local content = table.concat(vim.fn.readfile(file), "\n")

      for find, repl in pairs(subs) do
        content = replace_all(content, find, repl)
      end

      vim.fn.writefile(vim.split(content, "\n"), file)
    end
  end

  -- Fill the empty manifest attributes the template leaves for us.
  local manifest_file = vim.fs.joinpath(dir, "manifest.xml")
  local m = table.concat(vim.fn.readfile(manifest_file), "\n")
  m = m:gsub('id=""', 'id="' .. uuid() .. '"')
    :gsub('type=""', 'type="' .. app_type .. '"')
    :gsub('name=""', 'name="@Strings.AppName"')
    :gsub('entry=""', 'entry="' .. base .. 'App"')
    :gsub('launcherIcon=""', 'launcherIcon="@Drawables.LauncherIcon"')
    :gsub('minApiLevel=""', 'minApiLevel="1.0.0"')
  vim.fn.writefile(vim.split(m, "\n"), manifest_file)

  notify(("created %s (add products to manifest.xml before building)"):format(dir))

  local app = vim.fs.joinpath(dir, "source", "App.mc")
  if vim.uv.fs_stat(app) then
    vim.cmd.edit(app)
  end
end

-- Scaffold a new project from an SDK template. Prompts for a name and type;
-- {dir} defaults to <cwd>/<name>.
function M.new_project(dir)
  vim.ui.input({ prompt = "New Monkey C project name: " }, function(name)
    if not name or name == "" then
      return
    end

    vim.ui.select(new_project_types, { prompt = "App type" }, function(app_type)
      if not app_type then
        return
      end

      local target = (dir and dir ~= "" and vim.fn.expand(dir))
        or vim.fs.joinpath(vim.uv.cwd(), (name:gsub("%s+", "-")))

      scaffold(name, app_type, target)
    end)
  end)
end

-- Replace the manifest's application id with a fresh UUID (leaves product ids
-- untouched). Use after copying a project so it gets its own identity.
function M.regenerate_uuid()
  local manifest_file = vim.fs.joinpath(project_directory(), "manifest.xml")

  if not vim.uv.fs_stat(manifest_file) then
    return notify("no manifest.xml found", vim.log.levels.ERROR)
  end

  local id = uuid()
  local content, replaced = table
    .concat(vim.fn.readfile(manifest_file), "\n")
    :gsub('(<iq:application[^>]-)id="[^"]*"', '%1id="' .. id .. '"', 1)

  if replaced == 0 then
    return notify("no <iq:application id> found in manifest.xml", vim.log.levels.ERROR)
  end

  vim.fn.writefile(vim.split(content, "\n"), manifest_file)
  vim.cmd("checktime") -- reload the manifest buffer if it is open

  notify("regenerated application id: " .. id)
end

-- Stop the running build.
function M.cancel()
  if not current_build then
    return notify("no build is running")
  end

  cancelled = true
  current_build:kill("sigterm")
end

-- Open the most recent build's full output in a split. Updates live while a
-- build is running.
function M.logs()
  if not (log_bufnr and vim.api.nvim_buf_is_valid(log_bufnr)) then
    log_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[log_bufnr].filetype = "log"
    pcall(vim.api.nvim_buf_set_name, log_bufnr, "MonkeyC build log")
  end

  if #log_lines == 0 then
    log_lines = { "No build has run yet." }
  end

  if #vim.fn.win_findbuf(log_bufnr) == 0 then
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, log_bufnr)
  end

  render_log()
end

local subcommands = {
  ["build"] = M.build,
  ["build-for-device"] = M.build_for_device,
  ["run"] = M.run,
  ["test"] = M.test,
  ["debug"] = function(device)
    require("garmin-monkeyc.dap").debug(device)
  end,
  ["debug-native-pairing"] = function(device)
    require("garmin-monkeyc.dap").debug(device, { native_pairing = true })
  end,
  ["debug-complication"] = function(device)
    require("garmin-monkeyc.dap").debug_complication(device)
  end,
  ["export"] = M.export,
  ["generate-key"] = M.generate_key,
  ["new-project"] = M.new_project,
  ["regenerate-uuid"] = M.regenerate_uuid,
  ["edit-products"] = manifest.edit_products,
  ["edit-permissions"] = manifest.edit_permissions,
  ["edit-languages"] = manifest.edit_languages,
  ["edit-annotations"] = manifest.edit_annotations,
  ["edit-application"] = manifest.edit_application,
  ["configure-barrel"] = function(path)
    local barrel = require("garmin-monkeyc.barrel")

    if path and path ~= "" then
      barrel.add_barrel(path)
    else
      barrel.configure_barrel()
    end
  end,
  ["clean"] = M.clean,
  ["diagnostics"] = M.diagnostics,
  ["logs"] = M.logs,
  ["cancel"] = M.cancel,
  ["sdk-manager"] = tools.sdk_manager,
  ["docs"] = tools.docs,
  ["samples"] = tools.samples,
  ["monkey-graph"] = tools.monkey_graph,
  ["monkey-motion"] = tools.monkey_motion,
  ["era"] = tools.era,
}

-- Subcommands whose argument is a device id (used to scope completion).
local device_subcommands = {
  ["build-for-device"] = true,
  ["run"] = true,
  ["test"] = true,
  ["debug"] = true,
  ["debug-native-pairing"] = true,
  ["debug-complication"] = true,
}

-- Subcommands whose argument is a filesystem path.
local path_subcommands = {
  ["export"] = true,
  ["generate-key"] = true,
  ["new-project"] = true,
  ["configure-barrel"] = true,
}

function M.setup()
  vim.api.nvim_create_user_command("MonkeyC", function(cmd)
    local handler = subcommands[cmd.fargs[1]]

    if not handler then
      return notify(
        "unknown command; try " .. table.concat(vim.fn.sort(vim.tbl_keys(subcommands)), ", "),
        vim.log.levels.ERROR
      )
    end

    handler(cmd.fargs[2])
  end, {
    nargs = "*",
    desc = "Build/run Monkey C projects",
    complete = function(arglead, cmdline)
      local subcommand = cmdline:match("MonkeyC%s+(%S+)%s")

      -- Completing the subcommand.
      if not subcommand then
        return vim.tbl_filter(function(name)
          return name:find(arglead, 1, true) == 1
        end, vim.fn.sort(vim.tbl_keys(subcommands)))
      end

      -- Completing a device argument, only for subcommands that take one.
      if device_subcommands[subcommand] then
        return vim.tbl_filter(function(id)
          return id:find(arglead, 1, true) == 1
        end, sdk.manifest_devices(project_directory()))
      end

      -- export / generate-key take a filesystem path.
      if path_subcommands[subcommand] then
        return vim.fn.getcompletion(arglead, "file")
      end

      return {}
    end,
  })
end

return M
