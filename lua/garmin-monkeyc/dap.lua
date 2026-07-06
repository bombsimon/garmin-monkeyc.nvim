-- Debug Adapter Protocol integration.
--
-- The Connect IQ SDK ships a standard DAP server as a Java main class
-- (com.garmin.monkeybrains.monkeydodo.DebugAdapterProtocol) inside
-- monkeybrains.jar. It speaks DAP over stdio and connects to a running
-- simulator to install breakpoints, step, and read the stack/variables, using
-- the compiler-emitted <app>.prg.debug.xml to map source lines to program
-- addresses. See DAP.md for the reverse-engineering behind this.
--
-- This module registers that adapter with nvim-dap (an optional dependency)
-- and orchestrates a debug session: build a debuggable prg, start the
-- simulator, wait for its debug port, then launch.

local config = require("garmin-monkeyc.config")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

-- The simulator's debug shell listens on one of these ports and greets a new
-- connection with a banner containing SIMULATOR_BANNER. The adapter connects to
-- it; we probe the same range to know the simulator is up, matching the VS Code
-- extension (which scans 1234..1238 for the banner).
local SIMULATOR_HOST = "127.0.0.1"
local SIMULATOR_PORTS = { 1234, 1235, 1236, 1237, 1238 }
local SIMULATOR_BANNER = "A garmin device"

-- Total time to wait for the simulator to come up, and how often to rescan.
local SIMULATOR_WAIT_MS = 40000
local SIMULATOR_POLL_INTERVAL_MS = 250
local SIMULATOR_PROBE_TIMEOUT_MS = 400

local function notify(message, level)
  vim.notify("garmin-monkeyc: " .. message, level or vim.log.levels.INFO)
end

-- nvim-dap is optional; return the module or nil.
local function get_dap()
  local ok, dap = pcall(require, "dap")

  return ok and dap or nil
end

-- The adapter's java classpath: the compiler jar carries the monkeydodo debug
-- classes and lsp4j.debug, but not gson (which the adapter needs to parse the
-- DAP JSON); the language server jar bundles gson, so both are required.
local function classpath()
  local sdk_path = config.options.sdk_path
  local monkeybrains = sdk.tool(sdk_path, "monkeybrains.jar")
  local language_server = sdk.language_server_jar(sdk_path)

  if not (monkeybrains and language_server) then
    return nil
  end

  local separator = vim.fn.has("win32") == 1 and ";" or ":"

  return monkeybrains .. separator .. language_server
end

-- Register the DAP adapter with nvim-dap. Returns true when nvim-dap is present
-- and the SDK jars were found; safe to call more than once.
function M.setup()
  local dap = get_dap()

  if not dap then
    return false
  end

  local cp = classpath()

  if not cp then
    return false
  end

  dap.adapters.monkeyc = {
    type = "executable",
    command = "java",
    args = {
      "-Dfile.encoding=UTF-8",
      "-classpath",
      cp,
      "com.garmin.monkeybrains.monkeydodo.DebugAdapterProtocol",
    },
  }

  return true
end

-- Launch the simulator GUI (a no-op if it is already running). The adapter,
-- not monkeydo, loads the prg into the simulator over the debug port.
local function start_simulator()
  local connectiq = sdk.tool(config.options.sdk_path, "connectiq")

  if not connectiq then
    notify("connectiq not found under " .. tostring(config.options.sdk_path), vim.log.levels.ERROR)

    return false
  end

  vim.system({ connectiq })

  return true
end

-- Connect to one port and report whether the simulator greeted us with its
-- banner. A connection to a wrong/closed port, or no banner within the probe
-- timeout, counts as not-ready.
local function probe_port(port, on_result)
  local client = vim.uv.new_tcp()
  local timer = vim.uv.new_timer()
  local settled = false

  local function finish(ready)
    if settled then
      return
    end

    settled = true

    pcall(function()
      timer:stop()
      timer:close()
    end)
    pcall(function()
      client:read_stop()
    end)
    pcall(function()
      if not client:is_closing() then
        client:close()
      end
    end)

    on_result(ready)
  end

  client:connect(SIMULATOR_HOST, port, function(err)
    if err then
      return finish(false)
    end

    client:read_start(function(read_err, data)
      if read_err or not data then
        return finish(false)
      end

      finish(data:find(SIMULATOR_BANNER, 1, true) ~= nil)
    end)
  end)

  timer:start(SIMULATOR_PROBE_TIMEOUT_MS, 0, function()
    finish(false)
  end)
end

-- Scan the simulator ports for the banner until one answers, then call
-- on_ready(true); on_ready(false) if none come up within SIMULATOR_WAIT_MS.
local function wait_for_simulator(on_ready)
  local rounds = math.max(1, math.floor(SIMULATOR_WAIT_MS / SIMULATOR_POLL_INTERVAL_MS))

  local function scan(remaining)
    local index = 0

    local function try_next()
      index = index + 1
      local port = SIMULATOR_PORTS[index]

      if not port then
        if remaining <= 0 then
          return vim.schedule(function()
            on_ready(false)
          end)
        end

        return vim.defer_fn(function()
          scan(remaining - 1)
        end, SIMULATOR_POLL_INTERVAL_MS)
      end

      probe_port(port, function(ready)
        if ready then
          vim.schedule(function()
            on_ready(true)
          end)
        else
          vim.schedule(try_next)
        end
      end)
    end

    try_next()
  end

  scan(rounds)
end

-- Build a debuggable prg for the device, start the simulator, wait for its
-- debug port, then start a DAP session. device is optional; when omitted the
-- manifest device picker is used.
function M.debug(device)
  local dap = get_dap()

  if not dap then
    return notify("nvim-dap is not installed; DAP debugging is unavailable", vim.log.levels.ERROR)
  end

  if not dap.adapters.monkeyc and not M.setup() then
    return notify("could not register the Monkey C debug adapter (SDK jars not found)", vim.log.levels.ERROR)
  end

  local build = require("garmin-monkeyc.build")

  local function launch(chosen)
    -- A debuggable (non-release) build emits <prg>.debug.xml next to the prg.
    build.build_debug(chosen, function(prg)
      if not start_simulator() then
        return
      end

      notify("waiting for the simulator…")

      wait_for_simulator(function(ready)
        if not ready then
          return notify(
            ("simulator did not open its debug port (%s:%d-%d); is it running?"):format(
              SIMULATOR_HOST,
              SIMULATOR_PORTS[1],
              SIMULATOR_PORTS[#SIMULATOR_PORTS]
            ),
            vim.log.levels.ERROR
          )
        end

        dap.run({
          type = "monkeyc",
          request = "launch",
          name = "Monkey C: " .. chosen,
          device = chosen,
          prg = prg,
          prgDebugXml = prg .. ".debug.xml",
          stopAtLaunch = false,
        })
      end)
    end)
  end

  if device and device ~= "" then
    return launch(device)
  end

  build.pick_device(launch)
end

return M
