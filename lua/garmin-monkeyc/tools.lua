-- Launchers for the Connect IQ SDK's bundled tools and docs. GUI tools are
-- launched via java (cross-platform); apps/URLs/folders open with the OS
-- handler via vim.ui.open.

local config = require("garmin-monkeyc.config")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

local docs_url = "https://developer.garmin.com/connect-iq/api-docs/"
local sdk_url = "https://developer.garmin.com/connect-iq/sdk/"

local function notify(message, level)
  vim.notify("garmin-monkeyc: " .. message, level or vim.log.levels.INFO)
end

-- Launch a bundled Java GUI tool, detached so it outlives Neovim.
local function launch_java(jar_or_args, name)
  if vim.fn.executable("java") == 0 then
    return notify("java not found on PATH", vim.log.levels.ERROR)
  end

  vim.system(jar_or_args, { detach = true })
  notify("launched " .. name)
end

-- Pick from the SDK's bundled documentation (doc/index.html plus each topic
-- folder under doc/docs/) and open it in the browser. Falls back to the online
-- docs when the SDK has no bundled doc/ directory.
function M.docs()
  local base = sdk.newest_sdk(config.options.sdk_path)
  local doc = base and vim.fs.joinpath(base, "doc")

  if not (doc and vim.uv.fs_stat(doc)) then
    return vim.ui.open(docs_url)
  end

  -- Landing page to prefer within a topic folder, in order.
  local landing = { "Overview.html", "Getting_Started.html", "Welcome_to_the_Jungle.html" }
  local topics_dir = vim.fs.joinpath(doc, "docs")
  local entries = {}

  for name, kind in vim.fs.dir(topics_dir) do
    if kind == "directory" then
      local folder = vim.fs.joinpath(topics_dir, name)
      local page

      for _, candidate in ipairs(landing) do
        if vim.uv.fs_stat(vim.fs.joinpath(folder, candidate)) then
          page = vim.fs.joinpath(folder, candidate)
          break
        end
      end

      if not page then
        local htmls = vim.fn.glob(vim.fs.joinpath(folder, "*.html"), false, true)
        table.sort(htmls)
        page = htmls[1]
      end

      if page then
        entries[#entries + 1] = { label = (name:gsub("_", " ")), path = page }
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  -- The class/method reference goes first.
  table.insert(entries, 1, { label = "API Reference", path = vim.fs.joinpath(doc, "index.html") })

  vim.ui.select(entries, {
    prompt = "Connect IQ documentation",
    format_item = function(entry)
      return entry.label
    end,
  }, function(choice)
    if choice then
      vim.ui.open(choice.path)
    end
  end)
end

function M.samples()
  local base = sdk.newest_sdk(config.options.sdk_path)
  local samples = base and vim.fs.joinpath(base, "samples")

  if not (samples and vim.uv.fs_stat(samples)) then
    return notify("no samples directory found in the SDK", vim.log.levels.WARN)
  end

  vim.cmd.edit(samples)
end

function M.sdk_manager()
  local cfg = vim.fs.joinpath(vim.fs.dirname(config.options.sdk_path), "sdkmanager-location.cfg")

  if not vim.uv.fs_stat(cfg) then
    return notify("SDK Manager not found; download it from " .. sdk_url, vim.log.levels.WARN)
  end

  vim.ui.open(vim.trim(table.concat(vim.fn.readfile(cfg), "\n")))
end

function M.monkey_graph()
  local jar = sdk.tool(config.options.sdk_path, "fit-graph.jar")

  if not jar then
    return notify("fit-graph.jar not found in the SDK", vim.log.levels.ERROR)
  end

  launch_java({ "java", "-jar", jar }, "Monkey Graph")
end

function M.era()
  local jar = sdk.tool(config.options.sdk_path, "era.jar")

  if not jar then
    return notify("era.jar not found in the SDK", vim.log.levels.ERROR)
  end

  launch_java({ "java", "-jar", jar }, "ERA")
end

function M.monkey_motion()
  local base = sdk.newest_sdk(config.options.sdk_path)

  if not base then
    return notify("SDK not found", vim.log.levels.ERROR)
  end

  -- Monkey Motion is a GUI app: MonkeyMotion.app on macOS, the monkeymotion
  -- binary elsewhere (same as VS Code). The monkeybrains MonkeyMotion class is a
  -- CLI encoder, not the GUI, so don't launch that.
  local mac = vim.fn.has("mac") == 1
  local launcher = vim.fs.joinpath(base, "bin", mac and "MonkeyMotion.app" or "monkeymotion")

  if not vim.uv.fs_stat(launcher) then
    return notify("Monkey Motion not found at " .. launcher, vim.log.levels.ERROR)
  end

  if mac then
    vim.ui.open(launcher)
  else
    vim.system({ launcher }, { detach = true })
  end

  notify("launched Monkey Motion")
end

return M
