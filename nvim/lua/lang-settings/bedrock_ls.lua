return function()
	vim.filetype.add({
		extension = {
			lang = "bedrock_lang",
			mcfunction = "mcfunction",
		},
	})
end
