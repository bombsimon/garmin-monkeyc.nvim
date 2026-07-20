-- Neovim's builtin runtime detects `.mc` as `m4`, so register it as `monkeyc`.
-- In ftdetect/ so it runs at startup (Neovim sources these early, and lazy.nvim
-- sources plugin ftdetect files even for lazy-loaded plugins), which is also
-- what lets `ft = "monkeyc"` lazy-loading of this plugin work.
--
-- Extensions match Garmin's official Monkey C VS Code extension: Monkey C
-- (.mc/.mb/.mcgen), Jungle build files (.jungle), and Monkey Style Sheets (.mss).
vim.filetype.add({
  extension = {
    mc = "monkeyc",
    mb = "monkeyc",
    mcgen = "monkeyc",
    jungle = "jungle",
    mss = "mss",
  },
})
