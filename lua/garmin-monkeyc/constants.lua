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

  -- Languages a manifest can declare, with display names (matching the VS Code
  -- extension's fixed picklist). code is the <iq:language> value.
  languages = {
    { code = "ara", name = "Arabic" },
    { code = "bul", name = "Bulgarian" },
    { code = "ces", name = "Czech" },
    { code = "dan", name = "Danish" },
    { code = "deu", name = "German" },
    { code = "dut", name = "Dutch" },
    { code = "eng", name = "English" },
    { code = "est", name = "Estonian" },
    { code = "fin", name = "Finnish" },
    { code = "fre", name = "French" },
    { code = "gre", name = "Greek" },
    { code = "heb", name = "Hebrew" },
    { code = "hrv", name = "Croatian" },
    { code = "hun", name = "Hungarian" },
    { code = "ind", name = "Indonesian" },
    { code = "ita", name = "Italian" },
    { code = "jpn", name = "Japanese" },
    { code = "kor", name = "Korean" },
    { code = "lav", name = "Latvian" },
    { code = "lit", name = "Lithuanian" },
    { code = "nob", name = "Norwegian" },
    { code = "pol", name = "Polish" },
    { code = "por", name = "Portuguese" },
    { code = "ron", name = "Romanian" },
    { code = "rus", name = "Russian" },
    { code = "slo", name = "Slovak" },
    { code = "slv", name = "Slovenian" },
    { code = "spa", name = "Spanish" },
    { code = "swe", name = "Swedish" },
    { code = "tha", name = "Thai" },
    { code = "tur", name = "Turkish" },
    { code = "ukr", name = "Ukrainian" },
    { code = "vie", name = "Vietnamese" },
    { code = "zhs", name = "Chinese (Simplified)" },
    { code = "zht", name = "Chinese (Traditional)" },
    { code = "zsm", name = "Standard (Bahasa) Malay" },
  },
}
