-- Edit the project manifest: products, permissions, languages, annotations and
-- application attributes.
--
-- Products (from the installed devices) and permissions (from a known set) are
-- chosen with a checkbox buffer. Languages/annotations have no enumerable value
-- set, so they use a free-text list buffer (one entry per line). Application
-- attributes are edited with prompts.

local config = require("garmin-monkeyc.config")
local constants = require("garmin-monkeyc.constants")
local sdk = require("garmin-monkeyc.sdk")

local M = {}

local function notify(message, level)
  vim.notify("garmin-monkeyc: " .. message, level or vim.log.levels.INFO)
end

local function manifest_path()
  local root = vim.fs.root(0, { "manifest.xml", ".git" }) or vim.uv.cwd()

  return vim.fs.joinpath(sdk.project_directory(root), "manifest.xml")
end

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

local function save(path, content)
  vim.fn.writefile(vim.split(content, "\n"), path)
  vim.cmd("checktime") -- reload the manifest buffer if it is open
end

-- One entry per manifest list section: how to find current values and how to
-- render each value back to XML.
local sections = {
  products = {
    tag = "iq:products",
    pattern = 'iq:product%s+id="([^"]+)"',
    render = function(v)
      return ('<iq:product id="%s"/>'):format(v)
    end,
  },
  permissions = {
    tag = "iq:permissions",
    pattern = 'iq:uses%-permission%s+id="([^"]+)"',
    render = function(v)
      return ('<iq:uses-permission id="%s"/>'):format(v)
    end,
  },
  languages = {
    tag = "iq:languages",
    pattern = "<iq:language>%s*([^<]-)%s*</iq:language>",
    render = function(v)
      return ("<iq:language>%s</iq:language>"):format(v)
    end,
  },
  annotations = {
    tag = "iq:annotations",
    pattern = "<iq:annotation>%s*([^<]-)%s*</iq:annotation>",
    render = function(v)
      return ("<iq:annotation>%s</iq:annotation>"):format(v)
    end,
  },
}

local function current_values(content, section)
  local values = {}

  for value in content:gmatch(section.pattern) do
    values[#values + 1] = value
  end

  return values
end

-- Rewrite (or insert) a manifest list section with the given values.
local function set_section(path, section, values)
  local content = read(path)
  local indent = content:match("([ \t]*)<" .. section.tag) or "        "
  local child = indent .. "    "

  local rendered = {}
  for _, value in ipairs(values) do
    rendered[#rendered + 1] = child .. section.render(value)
  end

  local block = ("<%s>\n"):format(section.tag)
    .. table.concat(rendered, "\n")
    .. (#rendered > 0 and "\n" or "")
    .. indent
    .. ("</%s>"):format(section.tag)

  local escaped = block:gsub("%%", "%%%%")
  local updated, n = content:gsub(("<%s>.-</%s>"):format(section.tag, section.tag), escaped, 1)

  -- No such section yet: insert it on its own line before </iq:application>.
  -- Escape only the block (values may contain %); the leading newline and the
  -- %1 back-reference to the closing tag must stay literal in the replacement.
  if n == 0 then
    local insert = "\n" .. (indent .. block):gsub("%%", "%%%%") .. "%1"
    updated, n = content:gsub("(\n[ \t]*</iq:application>)", insert, 1)
  end

  if n == 0 then
    return notify("could not update " .. section.tag .. " in manifest.xml", vim.log.levels.ERROR)
  end

  save(path, updated)
  notify(("set %d %s"):format(#values, section.tag:gsub("iq:", "")))
end

-- Checkbox buffer: [x]/[ ] per entry (label shown), toggle, :w save, q cancel.
-- entries: { { label, value, checked } }; on_confirm receives the checked values.
--
-- reconcile is an optional function(entries, states, toggled) that may adjust
-- the checked states after a toggle (states is index->bool, toggled is the set
-- of indices just flipped); used to enforce dependencies between entries.
local function checkbox_ui(title, entries, on_confirm, reconcile)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "monkeyc-select"
  vim.bo[buf].bufhidden = "wipe"
  -- acwrite (not the default nofile) so :w triggers the BufWriteCmd below
  -- instead of failing with E382.
  vim.bo[buf].buftype = "acwrite"
  pcall(vim.api.nvim_buf_set_name, buf, "monkeyc://" .. title)

  local offset = 2

  local function read_states()
    local states = {}
    for index in ipairs(entries) do
      local line = vim.api.nvim_buf_get_lines(buf, offset + index - 1, offset + index, false)[1] or ""
      states[index] = line:match("^%[x%]") ~= nil
    end

    return states
  end

  local function render_states(states)
    for index, entry in ipairs(entries) do
      local text = ("[%s] %s"):format(states[index] and "x" or " ", entry.label)
      vim.api.nvim_buf_set_lines(buf, offset + index - 1, offset + index, false, { text })
    end
  end

  local header = "# " .. title .. "  <Tab>/<Space> toggle, :w save, q cancel"
  local lines = { header, "" }
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = ("[%s] %s"):format(entry.checked and "x" or " ", entry.label)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)

  local function toggle(from, to)
    local states = read_states()
    local toggled = {}

    for lnum = math.max(from, offset + 1), to do
      local index = lnum - offset
      if entries[index] then
        states[index] = not states[index]
        toggled[index] = true
      end
    end

    if reconcile then
      reconcile(entries, states, toggled)
    end

    render_states(states)
  end

  vim.keymap.set("n", "<Tab>", function()
    toggle(vim.fn.line("."), vim.fn.line("."))
  end, { buffer = buf, desc = "Toggle" })
  vim.keymap.set("n", "<Space>", function()
    toggle(vim.fn.line("."), vim.fn.line("."))
  end, { buffer = buf, desc = "Toggle" })
  vim.keymap.set("x", "<Tab>", function()
    toggle(vim.fn.line("v"), vim.fn.line("."))
    vim.api.nvim_input("<Esc>")
  end, { buffer = buf, desc = "Toggle" })
  vim.keymap.set("n", "q", function()
    vim.cmd("bwipeout! " .. buf)
  end, { buffer = buf, desc = "Cancel" })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local states = read_states()

      -- Enforce dependencies once more in case the buffer was edited by hand.
      if reconcile then
        reconcile(entries, states, {})
      end

      local values = {}
      for index, entry in ipairs(entries) do
        if states[index] then
          values[#values + 1] = entry.value
        end
      end

      vim.bo[buf].modified = false
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.cmd("bwipeout! " .. buf)
        end
        on_confirm(values)
      end)
    end,
  })
end

-- Free-text list buffer: one value per line; :w saves the non-empty lines.
local function list_ui(title, values, on_confirm)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "monkeyc-list"
  vim.bo[buf].bufhidden = "wipe"
  -- acwrite (not the default nofile) so :w triggers the BufWriteCmd below
  -- instead of failing with E382.
  vim.bo[buf].buftype = "acwrite"
  pcall(vim.api.nvim_buf_set_name, buf, "monkeyc://" .. title)

  local lines = { "# " .. title .. "  (one per line, :w save, q cancel)", "" }
  vim.list_extend(lines, values)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)

  vim.keymap.set("n", "q", function()
    vim.cmd("bwipeout! " .. buf)
  end, { buffer = buf, desc = "Cancel" })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local result = {}
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        local value = vim.trim(line)
        if value ~= "" and not value:match("^#") then
          result[#result + 1] = value
        end
      end

      vim.bo[buf].modified = false
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.cmd("bwipeout! " .. buf)
        end
        on_confirm(result)
      end)
    end,
  })
end

function M.edit_products()
  local path = manifest_path()

  if not vim.uv.fs_stat(path) then
    return notify("no manifest.xml found", vim.log.levels.ERROR)
  end

  local selected = {}
  for _, id in ipairs(current_values(read(path), sections.products)) do
    selected[id] = true
  end

  local entries, seen = {}, {}

  for _, id in ipairs(sdk.installed_devices(config.options.sdk_path)) do
    seen[id] = true
    entries[#entries + 1] = {
      label = sdk.friendly_name(config.options.sdk_path, id) or id,
      value = id,
      checked = selected[id] == true,
    }
  end

  -- Keep any manifest device that is no longer installed so it can be removed.
  for id in pairs(selected) do
    if not seen[id] then
      entries[#entries + 1] = { label = id .. " (not installed)", value = id, checked = true }
    end
  end

  if #entries == 0 then
    return notify("no installed devices found", vim.log.levels.WARN)
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  checkbox_ui("products", entries, function(values)
    set_section(path, sections.products, values)
  end)
end

local function edit_list(section, title)
  local path = manifest_path()

  if not vim.uv.fs_stat(path) then
    return notify("no manifest.xml found", vim.log.levels.ERROR)
  end

  list_ui(title, current_values(read(path), section), function(values)
    set_section(path, section, values)
  end)
end

-- Keep the Background dependency consistent: any permission that requires
-- Background forces it on, and turning Background off turns those off too.
local function reconcile_permissions(entries, states, toggled)
  local index_of = {}
  for index, entry in ipairs(entries) do
    index_of[entry.value] = index
  end

  local background = index_of["Background"]
  if not background then
    return
  end

  -- Deselecting Background cascades to everything that depends on it.
  if toggled[background] and not states[background] then
    for _, name in ipairs(constants.permissions_requiring_background) do
      local index = index_of[name]
      if index then
        states[index] = false
      end
    end

    return
  end

  for _, name in ipairs(constants.permissions_requiring_background) do
    local index = index_of[name]
    if index and states[index] then
      states[background] = true

      return
    end
  end
end

function M.edit_permissions()
  local path = manifest_path()

  if not vim.uv.fs_stat(path) then
    return notify("no manifest.xml found", vim.log.levels.ERROR)
  end

  local selected = {}
  for _, id in ipairs(current_values(read(path), sections.permissions)) do
    selected[id] = true
  end

  local entries, seen = {}, {}

  for _, id in ipairs(constants.permissions) do
    seen[id] = true
    entries[#entries + 1] = { label = id, value = id, checked = selected[id] == true }
  end

  -- Keep any permission the manifest declares that we do not know about.
  for id in pairs(selected) do
    if not seen[id] then
      entries[#entries + 1] = { label = id, value = id, checked = true }
    end
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  checkbox_ui("permissions", entries, function(values)
    set_section(path, sections.permissions, values)
  end, reconcile_permissions)
end

function M.edit_languages()
  edit_list(sections.languages, "languages")
end

function M.edit_annotations()
  edit_list(sections.annotations, "annotations")
end

-- Edit the application attributes with prompts. name is stored in the AppName
-- string resource when the manifest references it (@Strings.AppName).
function M.edit_application()
  local path = manifest_path()

  if not vim.uv.fs_stat(path) then
    return notify("no manifest.xml found", vim.log.levels.ERROR)
  end

  local content = read(path)
  local app_type = content:match('<iq:application[^>]-type="([^"]*)"') or ""
  local min_api = content:match('<iq:application[^>]-minApiLevel="([^"]*)"') or ""

  vim.ui.select({ "watch-app", "watchface", "datafield", "widget", "audio-content-provider-app" }, {
    prompt = "App type (current: " .. app_type .. ")",
  }, function(chosen_type)
    if not chosen_type then
      return
    end

    vim.ui.input({ prompt = "Minimum API level: ", default = min_api }, function(level)
      if not level then
        return
      end

      local updated = read(path)
        :gsub('(<iq:application[^>]-type=")[^"]*"', "%1" .. chosen_type .. '"', 1)
        :gsub('(<iq:application[^>]-minApiLevel=")[^"]*"', "%1" .. level .. '"', 1)

      save(path, updated)
      notify("updated application attributes")
    end)
  end)
end

return M
