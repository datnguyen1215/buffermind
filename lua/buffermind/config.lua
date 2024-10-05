local config = {
	model = "gpt-4o", -- Default model
	platform = "openai", -- Default platform
}

-- Function to allow users to configure the plugin
function setup(user_config)
	user_config = user_config or {}
	config = vim.tbl_extend("force", config, user_config)
end

return {
	setup = setup,
	get = function()
		return config
	end,
}
