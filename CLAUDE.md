# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**odoo.nvim** is a Neovim plugin that transforms Neovim into a complete IDE for Odoo development. It supports all Odoo versions (8.0-18.0+) and both standard Odoo projects and Doodba (Docker-based) projects.

### Key Capabilities
- **Zero-config auto-detection**: Automatically detects Odoo projects (standard or Doodba)
- **Multi-version support**: Works with Odoo 8.0-18.0+ with automatic version detection
- **LSP integration**: Automatically injects configuration into Pyright/Basedpyright
- **Type stubs management**: Downloads and manages type stubs from [odoo-ide/odoo-stubs](https://github.com/odoo-ide/odoo-stubs)
- **XML→Python navigation**: Jump from XML views to Python model definitions using `gd`
- **Docker integration**: Control Doodba containers directly from Neovim

## Architecture

### Module Structure
The plugin uses a **flat Lua module architecture** at the repository root (no `lua/` subdirectory):

```
odoo.nvim/
├── init.lua         # Main entry point, setup() and plugin lifecycle
├── config.lua       # Configuration management and version definitions
├── util.lua         # Utilities: project detection, file operations, Odoo version detection
├── stubs.lua        # Stubs download/management from odoo-ide/odoo-stubs repo
├── lsp.lua          # LSP configuration injection for Pyright/Basedpyright
├── navigation.lua   # XML→Python navigation using Treesitter
├── docker.lua       # Docker/Doodba container management
└── health.lua       # :checkhealth implementation
```

**Important**: Lua files are at the repository root, NOT in a `lua/odoo/` subdirectory. Modules are required as `require("odoo.util")` but files live at `./util.lua`.

### Key Architectural Patterns

1. **Lazy Module Loading**: Modules use setmetatable() lazy-loading proxies in init.lua
2. **Type Annotations**: Full LuaLS type annotations (@class, @param, @return)
3. **Project Type Detection**: Dual detection for "standard" Odoo vs "doodba" projects
4. **Version-Specific Configuration**: VERSION_INFO table maps Odoo versions to Python versions and stub branches
5. **LSP Hook Injection**: Intercepts lspconfig setup to inject Odoo-specific settings

### Critical Data Structures

**config.lua** - `VERSION_INFO` table:
- Maps Odoo versions (8.0-18.0+) to Python versions and stubs branches
- Determines manifest file name (`__manifest__.py` vs `__openerp__.py`)
- Used throughout the codebase for version-dependent behavior

**util.lua** - Project detection:
- `get_odoo_root()` returns `(root_path, project_type)` where type is "standard" | "doodba" | nil
- `get_odoo_version(root)` extracts version from multiple sources (odools.toml, release.py, docker-compose.yml, etc.)
- `get_addons_paths(root)` finds all addon directories for LSP extraPaths

**lsp.lua** - Settings generation:
- `generate_standard_settings()` for standard Odoo projects
- `generate_doodba_settings()` for Docker-based projects
- Both inject stubPath, extraPaths, pythonVersion into Pyright

## Development Commands

### Testing
```bash
# No automated test suite currently
# Manual testing: Open in Neovim with the plugin installed
nvim test-project/  # where test-project is an Odoo directory
```

### Plugin Installation (for testing)
```lua
-- In your Neovim config for development:
{
  dir = "/path/to/odoo.nvim",  -- Use local directory
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {},
}
```

### Documentation
```bash
# Generate vim help tags
nvim --headless -c "helptags ." -c quit

# View help
:help odoo.nvim
```

### Debugging
```lua
-- Enable debug messages in Neovim
vim.lsp.set_log_level("debug")

-- Check plugin state
:OdooInfo          -- Shows detected version, stubs, LSP config
:OdooHealth        -- Runs diagnostic checks
:checkhealth odoo  -- Full health check
```

## Common Development Workflows

### Adding Support for a New Odoo Version
1. Update `config.lua` → `VERSION_INFO` table with new version entry
2. Add version to `defaults.version.supported` array
3. Test auto-detection with a project of that version
4. Verify stubs download works for the new version

### Modifying LSP Configuration
1. Edit `lsp.lua` → `generate_standard_settings()` or `generate_doodba_settings()`
2. Test with `:OdooLspReload` command
3. Verify with `:LspInfo` in a Python buffer
4. Check generated settings with `:OdooLspInfo`

### Adding New Navigation Features
1. Edit `navigation.lua`
2. Add Treesitter queries if needed (see `get_xml_context()`)
3. Implement search logic using Telescope or vim.fn.search()
4. Register keymaps in `setup_keymaps()`

### Docker/Doodba Commands
1. Edit `docker.lua`
2. Add command registration in `setup_commands()`
3. Use `util.get_compose_cmd()` to detect docker-compose vs docker compose
4. Commands should check project type before executing

## Important Implementation Details

### Project Detection Logic
The plugin uses a **hierarchical detection** approach:
1. Check for Doodba markers (odools.toml, tasks.py, common.yaml, .copier-answers.yml)
2. If Doodba markers found, validate structure (odoo/ directory, yaml files)
3. Fall back to standard Odoo markers (odoo-bin, __manifest__.py, __openerp__.py)

### Version Detection Priority
```lua
-- Checked in this order:
1. odools.toml (Doodba projects)
2. common.yaml / devel.yaml (Docker compose)
3. release.py (official Odoo version file)
4. docker-compose.yml (image tag)
5. .copier-answers.yml (Doodba template)
6. requirements.txt (odoo package version)
7. .env (environment variables)
8. config.version.default (fallback: "16.0")
```

### Stubs Management
- Stubs are downloaded from [odoo-ide/odoo-stubs](https://github.com/odoo-ide/odoo-stubs) repository
- Stored in `~/.local/share/nvim/odoo-stubs/{version}/`
- Each version has its own directory (12.0, 14.0, 16.0, etc.)
- LSP stubPath points to the version-specific directory

### LSP Configuration Injection
The plugin **hooks into lspconfig** before user setup:
1. `lsp.hook_lspconfig()` wraps `lspconfig.pyright.setup` and `lspconfig.basedpyright.setup`
2. When user calls setup(), plugin injects Odoo-specific settings
3. Settings include: stubPath, extraPaths (addons), pythonVersion, diagnosticSeverityOverrides
4. User settings are deep-merged with plugin settings (user takes precedence)

### XML Navigation with Treesitter
Uses Treesitter XML parser to:
1. Find cursor position in XML tree
2. Extract context (model attribute, field name, ref attribute)
3. Search Python files for matching `_name = 'model.name'` or field definitions
4. Uses Telescope picker if multiple matches found

## Code Style Conventions

### LuaLS Type Annotations
```lua
---@class odoo.Config
---@field stubs odoo.Config.Stubs
---@param opts? odoo.Config
---@return string|nil, odoo.ProjectType
```

### Notification Functions
```lua
util.info("message")   -- INFO level
util.warn("message")   -- WARN level
util.error("message")  -- ERROR level
util.debug("message")  -- DEBUG level, only once per message
```

### Path Handling
- Always use `vim.fs.find()` for upward search from current directory
- Stop search at `vim.env.HOME` to avoid scanning entire filesystem
- Use `util.exists()` wrapper instead of direct vim.fn checks
- Format paths for display with `util.format_path()` (makes ~ for home)

### Docker Command Construction
```lua
-- Always detect compose command first
local compose_cmd = util.get_compose_cmd()  -- Returns "docker-compose" or "docker compose"
if not compose_cmd then
  util.error("docker-compose not available")
  return
end

-- Build commands dynamically
local cmd = string.format("%s -f devel.yaml up -d", compose_cmd)
```

## Testing Checklist

When making changes, test with:
- [ ] Standard Odoo project (with odoo-bin)
- [ ] Doodba project (with Docker structure)
- [ ] Multiple Odoo versions (12.0, 14.0, 16.0, 17.0)
- [ ] Projects without stubs installed
- [ ] XML navigation (gd on model, field, ref attributes)
- [ ] Docker commands (for Doodba projects)
- [ ] LSP configuration (check :LspInfo shows correct extraPaths)

## Common Pitfalls

1. **Stubs path structure**: Stubs are in `{base}/{version}/odoo-stubs/`, not just `{base}/{version}/`
2. **Project type detection**: Always check both standard AND Doodba markers, order matters
3. **Version parsing**: Different files have different formats (YAML vs Python vs env vars)
4. **LSP injection timing**: Must hook lspconfig BEFORE user calls setup()
5. **Lazy loading**: Modules loaded on-demand, don't assume all are loaded
6. **Treesitter optional**: XML navigation falls back to regex if Treesitter unavailable

## File References for Common Tasks

- **Add new command**: Check `stubs.lua:setup_commands()`, `lsp.lua:setup_commands()`, `docker.lua:setup_commands()`
- **Modify version support**: Edit `config.lua:VERSION_INFO` and `config.lua:defaults.version.supported`
- **Change detection logic**: Edit `util.lua:get_odoo_root()`, `util.lua:get_odoo_version()`
- **Fix LSP issues**: Check `lsp.lua:generate_standard_settings()` and `lsp.lua:hook_lspconfig()`
- **Improve navigation**: Edit `navigation.lua:get_xml_context()` and `navigation.lua:goto_definition()`
