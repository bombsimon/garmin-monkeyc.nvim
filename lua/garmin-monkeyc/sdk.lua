-- ConnectIQ SDK discovery: locate the SDK, its language server jar, and derive
-- per-project build inputs (jungle files, target device). Kept separate from
-- the LSP wiring so future build/run/simulator features can reuse it.

local M = {}

-- Default "Sdks" directory per OS, matching where the ConnectIQ SDK Manager
-- installs (the same locations the official VS Code extension probes):
--   macOS:        $HOME/Library/Application Support/Garmin/ConnectIQ/Sdks
--   Windows:      $APPDATA/Garmin/ConnectIQ/Sdks  ($APPDATA already ends in Roaming)
--   Linux/other:  $HOME/.Garmin/ConnectIQ/Sdks    (no official SDK Manager; best effort)
function M.default_sdk_path()
  if vim.fn.has("mac") == 1 then
    return vim.fs.joinpath(vim.env.HOME, "Library", "Application Support", "Garmin", "ConnectIQ", "Sdks")
  elseif vim.fn.has("win32") == 1 then
    return vim.fs.joinpath(vim.env.APPDATA or "", "Garmin", "ConnectIQ", "Sdks")
  end

  return vim.fs.joinpath(vim.env.HOME, ".Garmin", "ConnectIQ", "Sdks")
end

-- Newest installed SDK directory under sdk_path (the versioned
-- connectiq-sdk-* folder). Folder names sort, so the last is the newest.
function M.newest_sdk(sdk_path)
  local bins = vim.fn.glob(vim.fs.joinpath(sdk_path, "*", "bin"), false, true)
  local newest_bin = bins[#bins]

  return newest_bin and vim.fs.dirname(newest_bin) or nil
end

-- Path to a tool in the newest SDK's bin (e.g. "monkeyc", "monkeydo",
-- "connectiq", "LanguageServer.jar"), or nil if it isn't there.
function M.tool(sdk_path, name)
  local sdk_dir = M.newest_sdk(sdk_path)

  if not sdk_dir then
    return nil
  end

  local path = vim.fs.joinpath(sdk_dir, "bin", name)

  return vim.uv.fs_stat(path) and path or nil
end

function M.language_server_jar(sdk_path)
  return M.tool(sdk_path, "LanguageServer.jar")
end

-- Installed devices live in a sibling of the Sdks directory
-- (…/ConnectIQ/Devices), one folder per device id.
function M.devices_path(sdk_path)
  return vim.fs.joinpath(vim.fs.dirname(sdk_path), "Devices")
end

-- Project template directory for an app type ("watch-app", "watchface",
-- "datafield", "widget", ...), preferring the "simple" variant.
function M.template_dir(sdk_path, app_type)
  local base = M.newest_sdk(sdk_path)

  if not base then
    return nil
  end

  local simple = vim.fs.joinpath(base, "bin", "templates", app_type, "simple")
  if vim.uv.fs_stat(simple) then
    return simple
  end

  return vim.fn.glob(vim.fs.joinpath(base, "bin", "templates", app_type, "*"), false, true)[1]
end

-- Ids of all installed devices (folders under Devices/ with a compiler.json),
-- sorted.
function M.installed_devices(sdk_path)
  local ids = {}

  for _, compiler_json in
    ipairs(vim.fn.glob(vim.fs.joinpath(M.devices_path(sdk_path), "*", "compiler.json"), false, true))
  do
    ids[#ids + 1] = vim.fs.basename(vim.fs.dirname(compiler_json))
  end

  table.sort(ids)

  return ids
end

-- Friendly device name from the installed device's compiler.json displayName
-- (e.g. "fēnix® 7 / quatix® 7"), or nil if the device isn't installed.
function M.friendly_name(sdk_path, device_id)
  local compiler_json = vim.fs.joinpath(M.devices_path(sdk_path), device_id, "compiler.json")

  if vim.uv.fs_stat(compiler_json) then
    return table.concat(vim.fn.readfile(compiler_json), "\n"):match('"displayName"%s*:%s*"([^"]+)"')
  end

  return nil
end

-- The manifest and jungle files usually live in the repo root, but search
-- upward from the resolved root so a nested app directory is handled too.
function M.project_directory(root)
  local manifest = vim.fs.find("manifest.xml", { upward = true, path = root, type = "file" })[1]

  return manifest and vim.fs.dirname(manifest) or root
end

function M.jungle_files(directory)
  local jungle_files = vim.fn.glob(directory .. "/*.jungle", false, true)

  if #jungle_files == 0 then
    jungle_files = vim.fs.find(function(name)
      return name:match("%.jungle$") ~= nil
    end, { upward = true, path = directory, type = "file", limit = math.huge })
  end

  -- The server still initializes against a non-existent default jungle, which
  -- keeps single-file editing usable when no jungle is present yet.
  if #jungle_files == 0 then
    jungle_files = { directory .. "/monkey.jungle" }
  end

  -- Keep monkey.jungle first and barrels.jungle last (the barrel jungle appends
  -- to base.barrelPath, so it reads more naturally after the project jungle,
  -- matching the VS Code extension's `-f monkey.jungle;barrels.jungle` order).
  table.sort(jungle_files, function(a, b)
    local function rank(file)
      local name = vim.fs.basename(file)
      if name == "monkey.jungle" then
        return 0
      elseif name == "barrels.jungle" then
        return 2
      end

      return 1
    end

    return rank(a) < rank(b)
  end)

  return jungle_files
end

-- The manifest's application type ("watchface", "watch-app", "datafield",
-- "widget", "audio-content-provider-app", ...), or nil if there is no manifest.
function M.app_type(directory)
  local manifest = vim.fs.joinpath(directory, "manifest.xml")

  if not vim.uv.fs_stat(manifest) then
    return nil
  end

  return table.concat(vim.fn.readfile(manifest), "\n"):match('<iq:application[^>]-type="([^"]*)"')
end

-- Device ids declared in the project's manifest (<iq:product id="…">), in
-- declaration order.
function M.manifest_devices(directory)
  local manifest = vim.fs.joinpath(directory, "manifest.xml")

  if not vim.uv.fs_stat(manifest) then
    return {}
  end

  local devices = {}
  local contents = table.concat(vim.fn.readfile(manifest), "\n")

  for id in contents:gmatch('iq:product%s+id="([^"]+)"') do
    devices[#devices + 1] = id
  end

  return devices
end

return M
