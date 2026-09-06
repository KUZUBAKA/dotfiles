local M = {}

local schemas_dir = vim.fn.stdpath("data") .. "/minecraft-schemas"
local types_dir = vim.fn.stdpath("data") .. "/minecraft-types/node_modules/@minecraft"

local schemas = {
  {
    url = "https://raw.githubusercontent.com/Blockception/Minecraft-bedrock-json-schemas/main/vscode-settings.json",
    file = "blockception-settings.json",
  },
}

function M.has_manifest()
  local cwd = vim.fn.getcwd()

  local direct = vim.uv.fs_stat(cwd .. "/manifest.json")
  local nested = vim.fn.glob(cwd .. "/*/manifest.json")

  return direct ~= nil or nested ~= ""
end

local function download_schemas()
  local curl = require("plenary.curl")

  for _, schema in ipairs(schemas) do
    local dest = schemas_dir .. "/" .. schema.file

    if not vim.uv.fs_stat(dest) then
      curl.get(schema.url, { output = dest })
    end
  end
end

function M.get_blockception_schemas()
  local settings_path = schemas_dir .. "/blockception-settings.json"

  if not vim.uv.fs_stat(settings_path) then return {} end

  local lines = vim.fn.readfile(settings_path)
  local content = table.concat(lines, "\n")

  local ok, settings = pcall(vim.json.decode, content)

  if not ok or not settings then return {} end

  return settings["json.schemas"] or {}
end

local function generate_jsconfig()
  local cwd = vim.fn.getcwd()
  local jsconifg_path = cwd .. "/jsconfig.json"

  if vim.uv.fs_stat(jsconifg_path) then
    return
  end

  local base = types_dir:gsub("\\", "/")

  local content = string.format([[{
	"compilerOptions": {
		"module": "ESNext",
		"target": "ES2022",
		"moduleResolution": "Bundler",
		"checkJs": true,
		"paths": {
			"@minecraft/server": ["%s/server"],
			"@minecraft/server-ui": ["%s/server-ui"],
			"@minecraft/server-gametest": ["%s/server-gametest"]
		}
	},
	"include": ["**/*.js", "**/*.ts"]
	}]], base, base, base)

  vim.fn.writefile(vim.split(content, "\n"), jsconifg_path)
end

function M.setup()
  if not M.has_manifest() then
    return
  end

  download_schemas()
  generate_jsconfig()
end

return M
