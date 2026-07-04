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

-- Newest installed SDK's LanguageServer.jar under sdk_path. The list form of
-- glob returns sorted matches, so the last one is the newest SDK.
function M.language_server_jar(sdk_path)
	local jars = vim.fn.glob(vim.fs.joinpath(sdk_path, "*", "bin", "LanguageServer.jar"), false, true)

	return jars[#jars]
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

	return jungle_files
end

return M
