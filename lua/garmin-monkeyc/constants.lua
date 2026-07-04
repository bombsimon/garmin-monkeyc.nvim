-- Shared constants.
--
-- server_name is the name we register the language server under via
-- vim.lsp.config/enable, and the key hover/signature use to find it. It is
-- client-chosen (the server reports no serverInfo). "monkeyc" (one word)
-- matches the Neovim filetype and the VS Code extension's client id.
return {
	server_name = "monkeyc-lsp",
}
