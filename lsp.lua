---@class odoo.lsp
---Módulo para configurar e inyectar settings en pyright/basedpyright
---Soporta múltiples versiones de Odoo
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")
local stubs = require("odoo.stubs")

---@type boolean
local _hooked = false

---Genera la configuración de pyright para un proyecto Odoo estándar
---@param root_dir string
---@param version string
---@return table
function M.generate_standard_settings(root_dir, version)
  local cfg = config.get()

  -- Obtener rutas de addons
  local extra_paths = util.get_standard_addons_paths(root_dir)

  -- Añadir la raíz del proyecto
  table.insert(extra_paths, root_dir)

  -- Añadir stubs si existen para esta versión
  local stub_path = nil
  if stubs.installed(version) then
    stub_path = stubs.get_path(version)
    table.insert(extra_paths, stub_path .. "/odoo-stubs")
  elseif stubs.installed() then
    -- Fallback: usar cualquier versión de stubs disponible
    local installed = stubs.get_installed_versions()
    if #installed > 0 then
      stub_path = stubs.get_path(installed[1])
      table.insert(extra_paths, stub_path .. "/odoo-stubs")
      util.debug("Usando stubs de v" .. installed[1] .. " como fallback para v" .. version)
    end
  end

  -- Obtener versión de Python recomendada
  local python_version = config.get_python_version(version)

  ---@type table
  local settings = {
    python = {
      analysis = {
        typeCheckingMode = cfg.lsp.analysis.typeCheckingMode,
        diagnosticSeverityOverrides = cfg.lsp.analysis.diagnosticSeverityOverrides,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        autoImportCompletions = true,
        extraPaths = extra_paths,
        pythonVersion = python_version,
      },
      pythonPath = M.find_python(root_dir),
    },
  }

  -- Añadir stubPath solo si los stubs existen
  if stub_path then
    settings.python.analysis.stubPath = stub_path
  end

  return settings
end

---Genera la configuración de pyright para un proyecto Doodba
---@param root_dir string
---@param version string
---@return table
function M.generate_doodba_settings(root_dir, version)
  local cfg = config.get()

  -- Obtener rutas de addons de Doodba
  local extra_paths = util.get_doodba_addons_paths(root_dir)

  -- Añadir la raíz del proyecto
  table.insert(extra_paths, root_dir)

  -- Añadir rutas específicas de Doodba
  local doodba_paths = {
    root_dir .. "/odoo/custom/src",
    root_dir .. "/odoo/auto/addons",
    root_dir .. "/private",
  }

  for _, path in ipairs(doodba_paths) do
    if util.exists(path) and not vim.tbl_contains(extra_paths, path) then
      table.insert(extra_paths, path)
    end
  end

  -- Añadir stubs si existen para esta versión
  local stub_path = nil
  if stubs.installed(version) then
    stub_path = stubs.get_path(version)
    table.insert(extra_paths, stub_path .. "/odoo-stubs")
  elseif stubs.installed() then
    local installed = stubs.get_installed_versions()
    if #installed > 0 then
      stub_path = stubs.get_path(installed[1])
      table.insert(extra_paths, stub_path .. "/odoo-stubs")
    end
  end

  -- Obtener versión de Python recomendada
  local python_version = config.get_python_version(version)

  ---@type table
  local settings = {
    python = {
      analysis = {
        typeCheckingMode = cfg.lsp.analysis.typeCheckingMode,
        diagnosticSeverityOverrides = cfg.lsp.analysis.diagnosticSeverityOverrides,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        autoImportCompletions = true,
        extraPaths = extra_paths,
        pythonVersion = python_version,
        -- Ignorar directorios de Docker/volúmenes
        ignore = {
          "**/node_modules",
          "**/__pycache__",
          "**/filestore",
          "**/sessions",
        },
      },
      pythonPath = M.find_python_doodba(root_dir),
    },
  }

  -- Añadir stubPath solo si los stubs existen
  if stub_path then
    settings.python.analysis.stubPath = stub_path
  end

  return settings
end

---Genera la configuración de pyright (detecta tipo automáticamente)
---@param root_dir string
---@return table
function M.generate_settings(root_dir)
  local _, project_type = util.get_odoo_root(root_dir)
  local version = util.get_odoo_version(root_dir)

  if project_type == "doodba" then
    return M.generate_doodba_settings(root_dir, version)
  else
    return M.generate_standard_settings(root_dir, version)
  end
end

---Busca el intérprete de Python para proyectos estándar
---@param root_dir string
---@return string
function M.find_python(root_dir)
  -- Buscar venv común
  local venv_paths = {
    root_dir .. "/venv/bin/python",
    root_dir .. "/.venv/bin/python",
    root_dir .. "/env/bin/python",
    root_dir .. "/.env/bin/python",
    vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python") or nil,
  }

  for _, path in ipairs(venv_paths) do
    if path and util.exists(path) then
      return path
    end
  end

  -- Fallback a python del sistema
  return vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
end

---Busca el intérprete de Python para proyectos Doodba
---@param root_dir string
---@return string
function M.find_python_doodba(root_dir)
  -- En Doodba, primero intentar venv local (para desarrollo)
  local local_venvs = {
    root_dir .. "/venv/bin/python",
    root_dir .. "/.venv/bin/python",
    root_dir .. "/odoo/custom/.venv/bin/python",
  }

  for _, path in ipairs(local_venvs) do
    if util.exists(path) then
      return path
    end
  end

  -- Si hay VIRTUAL_ENV activo
  if vim.env.VIRTUAL_ENV then
    local venv_python = vim.env.VIRTUAL_ENV .. "/bin/python"
    if util.exists(venv_python) then
      return venv_python
    end
  end

  -- Fallback a python del sistema
  return vim.fn.exepath("python3") or vim.fn.exepath("python") or "python3"
end

---Intercepta la configuración de lspconfig para pyright
function M.hook_lspconfig()
  if _hooked then
    return
  end

  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    util.debug("lspconfig no está disponible")
    return
  end

  local cfg = config.get()
  local server_name = cfg.lsp.server

  -- Obtener la configuración original del servidor
  local server_config = lspconfig[server_name]
  if not server_config then
    util.warn("Servidor LSP '" .. server_name .. "' no encontrado en lspconfig")
    return
  end

  -- Guardar el setup original
  local original_setup = server_config.setup

  ---@param user_config table
  server_config.setup = function(user_config)
    user_config = user_config or {}

    -- Personalizar on_new_config para inyectar settings de Odoo
    local original_on_new_config = user_config.on_new_config

    user_config.on_new_config = function(new_config, new_root_dir)
      -- Llamar al callback original si existe
      if original_on_new_config then
        original_on_new_config(new_config, new_root_dir)
      end

      -- Verificar si es un proyecto Odoo
      local odoo_root, project_type = util.get_odoo_root(new_root_dir)
      if not odoo_root then
        return
      end

      local version = util.get_odoo_version(odoo_root)
      local type_label = project_type == "doodba" and "Doodba" or "Odoo"
      util.info("🐍 Proyecto " .. type_label .. " " .. version .. " detectado")

      -- Generar y mergear settings de Odoo
      local odoo_settings = M.generate_settings(odoo_root)

      -- Merge profundo con la configuración existente
      new_config.settings = vim.tbl_deep_extend(
        "force",
        new_config.settings or {},
        odoo_settings
      )

      -- Log para debug
      util.debug("LSP configurado con " .. #odoo_settings.python.analysis.extraPaths .. " extraPaths")
    end

    -- Llamar al setup original con la configuración modificada
    return original_setup(user_config)
  end

  _hooked = true
  util.debug("Hook de lspconfig instalado para " .. server_name)
end

---Recarga la configuración LSP para el buffer actual
function M.reload_config()
  -- Detener todos los clientes LSP del buffer actual
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, client in ipairs(clients) do
    if client.name == "pyright" or client.name == "basedpyright" then
      vim.lsp.stop_client(client.id)
    end
  end

  -- Esperar y reiniciar
  vim.defer_fn(function()
    vim.cmd("LspStart")
    util.info("Configuración LSP recargada")
  end, 500)
end

---Muestra la configuración LSP actual para debug
function M.show_config()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local found = false

  for _, client in ipairs(clients) do
    if client.name == "pyright" or client.name == "basedpyright" then
      found = true
      util.info("═══════════════════════════════════════")
      util.info("  " .. client.name .. " Configuration")
      util.info("═══════════════════════════════════════")
      util.info("Root: " .. (client.config.root_dir or "N/A"))

      local settings = client.config.settings or {}
      local python = settings.python or {}
      local analysis = python.analysis or {}

      -- Mostrar tipo de proyecto y versión
      local root, project_type = util.get_odoo_root()
      local version = root and util.get_odoo_version(root) or "N/A"
      util.info("Project Type: " .. (project_type or "unknown"))
      util.info("Odoo Version: " .. version)
      util.info("Python Version: " .. (analysis.pythonVersion or "N/A"))

      util.info("")
      util.info("Extra Paths (" .. #(analysis.extraPaths or {}) .. "):")
      for i, path in ipairs(analysis.extraPaths or {}) do
        if i <= 10 then
          util.info("  " .. i .. ". " .. util.format_path(path))
        elseif i == 11 then
          util.info("  ... y " .. (#analysis.extraPaths - 10) .. " más")
        end
      end

      util.info("")
      util.info("Stub Path: " .. util.format_path(analysis.stubPath or "N/A"))
      util.info("Type Checking: " .. (analysis.typeCheckingMode or "N/A"))
      util.info("Python: " .. (python.pythonPath or "N/A"))
    end
  end

  if not found then
    util.warn("No hay cliente pyright/basedpyright activo")
  end
end

---Registra los comandos del módulo
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooLspReload", function()
    M.reload_config()
  end, {
    desc = "Recarga la configuración LSP de Odoo",
  })

  vim.api.nvim_create_user_command("OdooLspInfo", function()
    M.show_config()
  end, {
    desc = "Muestra la configuración LSP actual",
  })
end

---Genera un archivo pyrightconfig.json (para usuarios que lo prefieran)
---@param path? string Ruta donde guardar el archivo (default: cwd)
function M.generate_pyrightconfig(path)
  path = path or vim.fn.getcwd()
  local filepath = path .. "/pyrightconfig.json"

  local odoo_root, project_type = util.get_odoo_root(path)
  if not odoo_root then
    util.error("No se detectó un proyecto Odoo en: " .. path)
    return
  end

  local version = util.get_odoo_version(odoo_root)
  local settings = M.generate_settings(odoo_root)
  local analysis = settings.python.analysis

  local pyrightconfig = {
    include = project_type == "doodba"
      and { "odoo/custom/src", "private" }
      or { "." },
    exclude = {
      "**/__pycache__",
      "**/node_modules",
      "**/.git",
      "**/static",
      "**/filestore",
      "**/sessions",
    },
    typeCheckingMode = analysis.typeCheckingMode,
    pythonVersion = analysis.pythonVersion or config.get_python_version(version),
    pythonPlatform = "Linux",
    stubPath = analysis.stubPath,
    extraPaths = analysis.extraPaths,
    reportGeneralTypeIssues = false,
    reportOptionalMemberAccess = false,
    reportAttributeAccessIssue = false,
  }

  -- Escribir archivo
  local json = vim.fn.json_encode(pyrightconfig)
  -- Formatear JSON bonito
  json = json:gsub(",", ",\n  ")
  json = json:gsub("{", "{\n  ")
  json = json:gsub("}", "\n}")
  json = json:gsub("%[", "[\n    ")
  json = json:gsub("%]", "\n  ]")

  local file = io.open(filepath, "w")
  if file then
    file:write(json)
    file:close()
    util.info("Archivo generado: " .. filepath)
    util.info("Tipo de proyecto: " .. (project_type or "unknown"))
    util.info("Versión de Odoo: " .. version)
  else
    util.error("No se pudo escribir: " .. filepath)
  end
end

return M
