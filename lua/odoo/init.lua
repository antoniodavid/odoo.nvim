---@class odoo
---@field config odoo.Config
---@field util odoo.util
---@field stubs odoo.stubs
---@field lsp odoo.lsp
---@field navigation odoo.navigation
---@field docker odoo.docker
---@field templates odoo.templates
---@field scaffold odoo.scaffold
---
---Odoo.nvim - Convierte Neovim en un IDE para Odoo 16
---Soporta proyectos estándar y Doodba (Docker)
---Inspirado en el estilo de arquitectura de Folke
---
---Autor: Claude AI
---Licencia: MIT
---
local M = {}

M._VERSION = "0.2.0"

---@type boolean
local _setup_done = false

---Punto de entrada principal del plugin
---@param opts? odoo.Config Opciones de configuración del usuario
function M.setup(opts)
  if _setup_done then
    return
  end

  -- Cargar módulos
  local config = require("odoo.config")
  local util = require("odoo.util")
  local stubs = require("odoo.stubs")
  local lsp = require("odoo.lsp")
  local navigation = require("odoo.navigation")
  local docker = require("odoo.docker")
  local templates = require("odoo.templates")
  local scaffold = require("odoo.scaffold")

  -- Aplicar configuración
  config.setup(opts)
  local cfg = config.get()

  -- Registrar comandos
  stubs.setup_commands()
  lsp.setup_commands()
  navigation.setup_commands()
  templates.setup_commands()
  scaffold.setup_commands()

  -- Registrar comandos de Docker si está habilitado
  if cfg.doodba.enabled then
    docker.setup_commands()
  end

  -- Setup LuaSnip integration para templates si está habilitado y disponible
  if cfg.templates.enabled and cfg.templates.use_luasnip then
    templates.setup_luasnip()
  end

  -- Configurar keymaps
  navigation.setup_keymaps()

  -- Configurar autodetección de proyectos Odoo
  if cfg.detection.auto_detect then
    M._setup_autodetection()
  end

  -- Inyectar configuración en lspconfig
  if cfg.lsp.auto_inject then
    lsp.hook_lspconfig()
  end

  -- Verificar stubs en el primer proyecto Odoo detectado
  if cfg.stubs.auto_download then
    M._check_stubs_on_enter()
  end

  -- Crear comandos globales
  M._setup_global_commands()

  _setup_done = true
  util.debug("odoo.nvim v" .. M._VERSION .. " inicializado")
end

---Configura la autodetección de proyectos Odoo
function M._setup_autodetection()
  local util = require("odoo.util")

  vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("OdooDetection", { clear = true }),
    callback = util.debounce(function()
      local root, project_type = util.get_odoo_root()
      if root then
        local type_label = project_type == "doodba" and "Doodba" or "Odoo estándar"
        util.debug("Proyecto " .. type_label .. " detectado: " .. root)
      end
    end, 100),
  })
end

---Verifica e instala stubs automáticamente
function M._check_stubs_on_enter()
  local util = require("odoo.util")
  local stubs = require("odoo.stubs")

  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("OdooStubsCheck", { clear = true }),
    once = true,
    callback = function()
      -- Solo verificar si es un proyecto Odoo
      vim.defer_fn(function()
        if util.is_odoo_project() and not stubs.installed() then
          local _, project_type = util.get_odoo_root()
          local type_label = project_type == "doodba" and "Doodba" or "Odoo"

          vim.ui.select({ "Sí", "No", "No preguntar de nuevo" }, {
            prompt = "󱔗 Proyecto " .. type_label .. " detectado. ¿Descargar stubs para autocompletado?",
          }, function(choice)
            if choice == "Sí" then
              stubs.download()
            elseif choice == "No preguntar de nuevo" then
              util.info("Puedes descargarlos más tarde con :OdooDownloadStubs")
            end
          end)
        end
      end, 500)
    end,
  })
end

---Configura comandos globales del plugin
function M._setup_global_commands()
  vim.api.nvim_create_user_command("OdooInfo", function()
    M.show_info()
  end, {
    desc = "Muestra información del plugin y estado del proyecto",
  })

  vim.api.nvim_create_user_command("OdooHealth", function()
    M.health_check()
  end, {
    desc = "Ejecuta un diagnóstico del plugin",
  })

  vim.api.nvim_create_user_command("OdooGeneratePyrightConfig", function()
    require("odoo.lsp").generate_pyrightconfig()
  end, {
    desc = "Genera un archivo pyrightconfig.json para el proyecto",
  })
end

---Muestra información del estado del plugin en un buffer flotante
function M.show_info()
  local util = require("odoo.util")
  local stubs = require("odoo.stubs")
  local config = require("odoo.config")

  local cfg = config.get()

  local lines = {
    "═══════════════════════════════════════════════════════════",
    "  🐍 odoo.nvim v" .. M._VERSION,
    "═══════════════════════════════════════════════════════════",
    "",
    "Estado del Proyecto:",
  }

  local root, project_type = util.get_odoo_root()
  if root then
    local version = util.get_odoo_version(root)
    local type_icon = project_type == "doodba" and "🐳" or "🐍"
    local type_label = project_type == "doodba" and "Doodba" or "Estándar"
    table.insert(lines, "  ✓ Proyecto Odoo detectado")
    table.insert(lines, "  Tipo: " .. type_icon .. " " .. type_label)
    table.insert(lines, "  Versión: Odoo " .. version)
    table.insert(lines, "  Python: " .. config.get_python_version(version))
    table.insert(lines, "  Raíz: " .. util.format_path(root))

    -- Mostrar addons paths
    local addons = util.get_addons_paths(root)
    if #addons > 0 then
      table.insert(lines, "  Addons paths: " .. #addons)
    end
  else
    table.insert(lines, "  ✗ No es un proyecto Odoo")
  end

  table.insert(lines, "")
  table.insert(lines, "Stubs:")
  local installed_versions = stubs.get_installed_versions()
  if #installed_versions > 0 then
    table.insert(lines, "  ✓ Versiones instaladas: " .. table.concat(installed_versions, ", "))
    table.insert(lines, "  Ruta: " .. util.format_path(stubs.get_base_path()))

    -- Verificar si hay stubs para la versión actual
    if root then
      local current_version = util.get_odoo_version(root)
      if not vim.tbl_contains(installed_versions, current_version) then
        table.insert(lines, "  ⚠ No hay stubs para v" .. current_version .. " (usa :OdooDownloadStubs " .. current_version .. ")")
      end
    end
  else
    table.insert(lines, "  ✗ No instalados (ejecuta :OdooDownloadStubs)")
  end

  table.insert(lines, "")
  table.insert(lines, "Configuración:")
  table.insert(lines, "  LSP Server: " .. cfg.lsp.server)
  table.insert(lines, "  Auto-inject LSP: " .. (cfg.lsp.auto_inject and "✓" or "✗"))
  table.insert(lines, "  Telescope: " .. (cfg.navigation.use_telescope and "✓" or "✗"))
  table.insert(lines, "  XML gd override: " .. (cfg.navigation.xml_goto_definition and "✓" or "✗"))
  table.insert(lines, "  Doodba support: " .. (cfg.doodba.enabled and "✓" or "✗"))
  table.insert(lines, "  Version auto-detect: " .. (cfg.version.auto_detect and "✓" or "✗"))

  -- Mostrar estado del LSP
  table.insert(lines, "")
  table.insert(lines, "Estado LSP:")
  local lsp_clients = vim.lsp.get_clients({ bufnr = 0 })
  local pyright_active = false
  local lsp_stub_path = nil
  
  for _, client in ipairs(lsp_clients) do
    if client.name == "pyright" or client.name == "basedpyright" then
      pyright_active = true
      local settings = client.config.settings or {}
      local python = settings.python or {}
      local analysis = python.analysis or {}
      lsp_stub_path = analysis.stubPath
      
      table.insert(lines, "  ✓ " .. client.name .. " activo")
      if lsp_stub_path then
        table.insert(lines, "  Stub path: " .. util.format_path(lsp_stub_path))
      end
      break
    end
  end
  
  if not pyright_active then
    table.insert(lines, "  ✗ LSP no activo (abre un archivo .py)")
  end
  
  -- Advertencia si no hay stubs para la versión actual
  if root and #installed_versions > 0 then
    local current_version = util.get_odoo_version(root)
    if not vim.tbl_contains(installed_versions, current_version) then
      table.insert(lines, "  ⚠ Sin stubs para v" .. current_version .. " - ejecuta :OdooDownloadStubs")
    end
  end

  -- Mostrar info de Docker si es Doodba
  if project_type == "doodba" and root then
    table.insert(lines, "")
    table.insert(lines, "Docker:")
    local compose_cmd = util.get_compose_cmd()
    if compose_cmd then
      table.insert(lines, "  ✓ docker-compose: " .. compose_cmd)
      local docker = require("odoo.docker")
      local running = docker.is_running(root)
      table.insert(lines, "  Contenedores: " .. (running and "🟢 Corriendo" or "🔴 Detenidos"))
    else
      table.insert(lines, "  ✗ docker-compose no disponible")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Keymaps (en XML):")
  table.insert(lines, "  " .. cfg.navigation.keymaps.goto_definition .. " - Ir a definición")
  table.insert(lines, "  " .. cfg.navigation.keymaps.goto_model .. " - Ir a modelo")
  table.insert(lines, "  " .. cfg.navigation.keymaps.goto_xml_id .. " - Ir a XML ID")

  table.insert(lines, "")
  table.insert(lines, "Versiones de Odoo soportadas:")
  table.insert(lines, "  " .. table.concat(cfg.version.supported, ", "))

  if project_type == "doodba" then
    table.insert(lines, "")
    table.insert(lines, "Comandos Docker:")
    table.insert(lines, "  :OdooDockerUp     - Iniciar contenedores")
    table.insert(lines, "  :OdooDockerDown   - Detener contenedores")
    table.insert(lines, "  :OdooDockerShell  - Shell en contenedor")
    table.insert(lines, "  :OdooDockerLogs   - Ver logs")
  end

  table.insert(lines, "")
  table.insert(lines, "═══════════════════════════════════════════════════════════")
  table.insert(lines, "")
  table.insert(lines, "Presiona 'q' o <Esc> para cerrar")

  -- Crear buffer flotante
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  -- Calcular dimensiones de la ventana
  local width = 63
  local height = #lines
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = ui.width
  local win_height = ui.height

  -- Centrar la ventana
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  -- Configuración de la ventana flotante
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Odoo Info ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Configurar highlight para el buffer
  vim.api.nvim_win_set_option(win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

  -- Keymaps para cerrar la ventana
  local close_keys = { "q", "<Esc>", "<CR>" }
  for _, key in ipairs(close_keys) do
    vim.api.nvim_buf_set_keymap(buf, "n", key, ":close<CR>", { noremap = true, silent = true })
  end
end

---Ejecuta un diagnóstico del plugin
function M.health_check()
  local util = require("odoo.util")
  local stubs = require("odoo.stubs")

  local lines = {
    "═══════════════════════════════════════",
    "  🩺 Diagnóstico de odoo.nvim",
    "═══════════════════════════════════════",
    "",
  }

  -- Verificar dependencias
  local checks = {
    { name = "Treesitter", check = function() return pcall(require, "nvim-treesitter") end },
    { name = "Treesitter XML", check = function()
        local ok, parsers = pcall(require, "nvim-treesitter.parsers")
        if not ok then return false end
        -- Intentar obtener el parser de XML
        return pcall(parsers.get_parser, "xml")
      end },
    { name = "Telescope", check = function() return pcall(require, "telescope") end },
    { name = "lspconfig", check = function() return pcall(require, "lspconfig") end },
    { name = "Git", check = function() return vim.fn.executable("git") == 1 end },
    { name = "Grep", check = function() return vim.fn.executable("grep") == 1 end },
    { name = "Docker", check = function() return util.docker_available() end },
    { name = "docker-compose", check = function() return util.get_compose_cmd() ~= nil end },
  }

  table.insert(lines, "Dependencias:")
  for _, check in ipairs(checks) do
    local ok = check.check()
    local status = ok and "✓" or "✗"
    table.insert(lines, "  " .. status .. " " .. check.name)
  end

  -- Verificar stubs
  table.insert(lines, "")
  table.insert(lines, "Stubs: " .. (stubs.installed() and "✓ Instalados" or "✗ No instalados"))

  -- Verificar proyecto Odoo
  local root, project_type = util.get_odoo_root()
  table.insert(lines, "")
  if root then
    local type_label = project_type == "doodba" and "Doodba" or "Estándar"
    table.insert(lines, "Proyecto Odoo: ✓ " .. type_label .. " en " .. util.format_path(root))

    -- Si es Doodba, verificar Docker
    if project_type == "doodba" then
      local docker = require("odoo.docker")
      local running = docker.is_running(root)
      table.insert(lines, "Docker: " .. (running and "✓ Corriendo" or "⚠ Detenido"))
    end
  else
    table.insert(lines, "Proyecto Odoo: ✗ No detectado")
  end

  -- Verificar LSP
  local clients = vim.lsp.get_clients()
  local pyright_running = false
  for _, client in ipairs(clients) do
    if client.name == "pyright" or client.name == "basedpyright" then
      pyright_running = true
      break
    end
  end
  table.insert(lines, "Pyright/Basedpyright: " .. (pyright_running and "✓ Activo" or "✗ No activo"))
  
  table.insert(lines, "")
  table.insert(lines, "═══════════════════════════════════════")
  table.insert(lines, "")
  table.insert(lines, "Presiona 'q' o <Esc> para cerrar")

  util.show_float_window(lines, { title = " Diagnóstico Odoo " })
end

-- Exponer submódulos para acceso directo
M.config = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.config")[key]
  end,
})

M.util = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.util")[key]
  end,
})

M.stubs = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.stubs")[key]
  end,
})

M.lsp = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.lsp")[key]
  end,
})

M.navigation = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.navigation")[key]
  end,
})

M.docker = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.docker")[key]
  end,
})

M.templates = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.templates")[key]
  end,
})

M.scaffold = setmetatable({}, {
  __index = function(_, key)
    return require("odoo.scaffold")[key]
  end,
})

return M
