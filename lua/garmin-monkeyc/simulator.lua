-- Launch the ConnectIQ simulator and wait for it to actually be ready:
-- "already running" isn't "ready" (e.g. still switching profile). See DAP.md.

local constants = require("garmin-monkeyc.constants")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

M.host = constants.simulator_host
M.ports = constants.simulator_ports

-- Total time to wait for the simulator to come up, and how often to rescan.
local WAIT_MS = 40000
local POLL_INTERVAL_MS = 250
local PROBE_TIMEOUT_MS = 400

-- Launch the simulator GUI (a no-op if it is already running). Returns false
-- if connectiq isn't found under sdk_path.
function M.start(sdk_path)
  local connectiq = sdk.tool(sdk_path, "connectiq")

  if not connectiq then
    return false
  end

  vim.system({ connectiq })

  return true
end

-- Report whether the simulator greeted this port with its banner within the
-- probe timeout; a wrong/closed port or no banner counts as not-ready.
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

  client:connect(M.host, port, function(err)
    if err then
      return finish(false)
    end

    client:read_start(function(read_err, data)
      if read_err or not data then
        return finish(false)
      end

      finish(data:find(constants.simulator_banner, 1, true) ~= nil)
    end)
  end)

  timer:start(PROBE_TIMEOUT_MS, 0, function()
    finish(false)
  end)
end

-- Scan the simulator ports for the banner until one answers, then call
-- on_ready(true); on_ready(false) if none come up within WAIT_MS.
function M.wait_ready(on_ready)
  local rounds = math.max(1, math.floor(WAIT_MS / POLL_INTERVAL_MS))

  local function scan(remaining)
    local index = 0

    local function try_next()
      index = index + 1
      local port = M.ports[index]

      if not port then
        if remaining <= 0 then
          return vim.schedule(function()
            on_ready(false)
          end)
        end

        return vim.defer_fn(function()
          scan(remaining - 1)
        end, POLL_INTERVAL_MS)
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

return M
