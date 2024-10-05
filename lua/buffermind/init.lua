-- ~/.config/nvim/lua/llm_chat/init.lua

local chat = require("llm_chat.chat")
local config = require("llm_chat.config")

config.setup()

-- Set up commands and key mappings
vim.api.nvim_create_user_command("ChatOpen", chat.open_chat_buffer, {})

-- Key mapping for <leader>chc to open chat
vim.api.nvim_set_keymap("n", "<leader>chc", "<cmd>ChatOpen<CR>", { noremap = true, silent = true })
