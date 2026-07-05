-- Build and run Monkey C projects with the SDK's monkeyc compiler and monkeydo
-- simulator runner, mirroring the VS Code extension's "Build for Device" and
-- run flows.

local config = require("garmin-monkeyc.config")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

-- Map our type_check_level to the compiler's -l value. "Default" omits -l so the
-- compiler uses its own default.
local typecheck_flag = {
  Off = "0",
  Gradual = "1",
  Informative = "2",
  Strict = "3",
}

local function notify(message, level)
  vim.notify("garmin-monkeyc: " .. message, level or vim.log.levels.INFO)
end

-- Project directory for the current buffer (the dir holding manifest.xml).
local function project_directory()
  local root = vim.fs.root(0, { "manifest.xml", ".git" }) or vim.uv.cwd()

  return sdk.project_directory(root)
end

local function output_prg(directory)
  return vim.fs.joinpath(directory, "bin", vim.fs.basename(directory) .. ".prg")
end

-- Compile the project for device, calling on_success(prg) when the build
-- succeeds. Errors go to the quickfix list.
local function compile(device, on_success)
  local options = config.options

  if not (options.developer_key and vim.uv.fs_stat(options.developer_key)) then
    return notify("set developer_key to a valid .der to build (see :MonkeyC or the README)", vim.log.levels.ERROR)
  end

  local monkeyc = sdk.tool(options.sdk_path, "monkeyc")

  if not monkeyc then
    return notify("monkeyc not found under " .. options.sdk_path, vim.log.levels.ERROR)
  end

  local directory = project_directory()
  local prg = output_prg(directory)

  vim.fn.mkdir(vim.fs.dirname(prg), "p")

  local args = {
    monkeyc,
    "-f",
    table.concat(sdk.jungle_files(directory), ";"),
    "-o",
    prg,
    "-d",
    device,
    "-y",
    options.developer_key,
    "-w",
  }

  local flag = typecheck_flag[options.type_check_level]
  if flag then
    vim.list_extend(args, { "-l", flag })
  end

  notify(("building for %s…"):format(device))

  vim.system(args, { text = true, cwd = directory }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        notify(("built %s"):format(prg))

        if on_success then
          on_success(prg)
        end
      else
        notify("build failed", vim.log.levels.ERROR)

        vim.fn.setqflist({}, " ", {
          title = "MonkeyC build",
          lines = vim.split((result.stdout or "") .. (result.stderr or ""), "\n", { trimempty = true }),
        })
        vim.cmd("botright copen")
      end
    end)
  end)
end

-- Launch the simulator (if needed) and push the built .prg to it.
local function run_in_simulator(device, prg)
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

  vim.defer_fn(function()
    vim.system({ monkeydo, prg, device }, { text = true }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          notify(("running on %s simulator"):format(device))
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
    return compile(device)
  end

  M.pick_device(function(chosen)
    compile(chosen)
  end)
end

function M.run_for_device(device)
  local function build_and_run(chosen)
    compile(chosen, function(prg)
      run_in_simulator(chosen, prg)
    end)
  end

  if device and device ~= "" then
    return build_and_run(device)
  end

  M.pick_device(build_and_run)
end

local subcommands = {
  ["build-for-device"] = M.build_for_device,
  ["run-for-device"] = M.run_for_device,
}

function M.setup()
  vim.api.nvim_create_user_command("MonkeyC", function(cmd)
    local handler = subcommands[cmd.fargs[1]]

    if not handler then
      return notify("unknown command; try build-for-device / run-for-device", vim.log.levels.ERROR)
    end

    handler(cmd.fargs[2])
  end, {
    nargs = "*",
    desc = "Build/run Monkey C projects",
    complete = function(arglead, cmdline)
      -- Completing the subcommand.
      if not cmdline:match("MonkeyC%s+%S+%s") then
        return vim.tbl_filter(function(name)
          return name:find(arglead, 1, true) == 1
        end, vim.tbl_keys(subcommands))
      end

      -- Completing the device argument.
      return vim.tbl_filter(function(id)
        return id:find(arglead, 1, true) == 1
      end, sdk.manifest_devices(project_directory()))
    end,
  })
end

return M
