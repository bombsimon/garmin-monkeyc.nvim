-- Shared constants.
--
-- server_name is the name we register the language server under via
-- vim.lsp.config/enable, and the key hover/signature use to find it. It is
-- client-chosen (the server reports no serverInfo). "monkeyc" (one word)
-- matches the Neovim filetype and the VS Code extension's client id.
return {
  server_name = "monkeyc-lsp",

  -- Valid optimization_level option values (matching the VS Code extension's
  -- monkeyC.optimizationLevel enum). "Default" omits -O; build.lua maps the
  -- rest to the compiler's -O 0..3.
  optimization_levels = { "Default", "None", "Basic", "Fast", "Slow" },

  -- The permissions a manifest can declare. Not discoverable from the SDK, so
  -- they are enumerated here (matching the VS Code extension's picklist).
  permissions = {
    "Ant",
    "Background",
    "BluetoothLowEnergy",
    "Communications",
    "ComplicationSubscriber",
    "Notifications",
    "Positioning",
    "PushNotification",
    "Sensor",
    "SensorHistory",
    "UserProfile",
  },

  -- Permissions that require "Background" to also be granted. Selecting any of
  -- them auto-selects Background; deselecting Background deselects all of them.
  permissions_requiring_background = {
    "Ant",
    "BluetoothLowEnergy",
    "Communications",
    "PushNotification",
    "Sensor",
  },
}
