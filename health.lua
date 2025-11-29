---@class odoo.health
---Módulo de diagnóstico para :checkhealth odoo
local M = {}

local health = vim.health or require("health")

---@param msg string
local function ok(msg)
  health.ok(msg)
end

---@param msg string
local function warn(msg)
  health.warn(msg)
end

---@param msg string
local function error(msg)
  health.error(msg)
end

---@param msg string
local function info(msg)
  health.info(msg)
end

---@param msg string
local function start(msg)
  health.start(msg)
end

function M.check()
  start("odoo.nvim")

  -- Verificar versión de Neovim
  start("Neovim Version")
  local nvim_version = vim.version()
  if nvim_version.major >= 0 and nvim_version.minor >= 9 then
    ok("Neovim " .. tostring(nvim_version))
  else
    error("Se requiere Neovim >= 0.9.0 (actual: " .. tostring(nvim_version) .. ")")
  end

  -- Verificar dependencias opcionales
  start("Dependencies")

  -- Treesitter
  local ts_ok = pcall(require, "nvim-treesitter")
  if ts_ok then
    ok("nvim-treesitter instalado")
    -- Verificar parser XML
    local parsers_ok, parsers = pcall(require, "nvim-treesitter.parsers")
    if parsers_ok and parsers.has_parser("xml") then
      ok("Treesitter parser XML instalado")
    else
      warn("Treesitter parser XML no instalado. Ejecuta :TSInstall xml")
    end
  else
    warn("nvim-treesitter no instalado (navegación XML limitada)")
  end

  -- Telescope
  local telescope_ok = pcall(require, "telescope")
  if telescope_ok then
    ok("telescope.nvim instalado")
  else
    warn("telescope.nvim no instalado (se usará grep para búsquedas)")
  end

  -- lspconfig
  local lspconfig_ok = pcall(require, "lspconfig")
  if lspconfig_ok then
    ok("nvim-lspconfig instalado")
  else
    error("nvim-lspconfig no instalado (requerido para inyección de LSP)")
  end

  -- Herramientas externas
  start("External Tools")

  if vim.fn.executable("git") == 1 then
    ok("git disponible")
  else
    error("git no encontrado (requerido para descargar stubs)")
  end

  if vim.fn.executable("grep") == 1 then
    ok("grep disponible")
  else
    warn("grep no encontrado (fallback para búsquedas)")
  end

  -- Verificar pyright/basedpyright
  if vim.fn.executable("pyright-langserver") == 1 then
    ok("pyright-langserver disponible")
  elseif vim.fn.executable("basedpyright-langserver") == 1 then
    ok("basedpyright-langserver disponible")
  else
    warn("pyright/basedpyright no instalado. Instala con: npm i -g pyright")
  end

  -- Docker/Doodba
  start("Docker (Doodba Support)")

  local util_ok, util = pcall(require, "odoo.util")
  if not util_ok then
    error("Error cargando módulo util")
    return
  end

  if vim.fn.executable("docker") == 1 then
    ok("docker instalado")
    if util.docker_available() then
      ok("docker daemon corriendo")
    else
      warn("docker daemon no está corriendo")
    end
  else
    warn("docker no instalado (necesario para proyectos Doodba)")
  end

  local compose_cmd = util.get_compose_cmd()
  if compose_cmd then
    ok(compose_cmd .. " disponible")
  else
    warn("docker-compose no disponible (necesario para proyectos Doodba)")
  end

  -- Estado del plugin
  start("Plugin Status")

  local stubs_ok, stubs = pcall(require, "odoo.stubs")
  if stubs_ok then
    if stubs.installed() then
      ok("Stubs instalados en: " .. util.format_path(stubs.get_path()))
    else
      warn("Stubs no instalados. Ejecuta :OdooDownloadStubs")
    end
  end

  -- Detectar proyecto Odoo
  start("Project Detection")

  local root, project_type = util.get_odoo_root()

  if root then
    local version = util.get_odoo_version(root)

    if project_type == "doodba" then
      ok("Proyecto Doodba detectado: " .. util.format_path(root))
    else
      ok("Proyecto Odoo estándar detectado: " .. util.format_path(root))
    end

    info("Versión de Odoo: " .. version)
    info("Versión de Python recomendada: " .. require("odoo.config").get_python_version(version))

    -- Verificar si hay stubs para esta versión
    if stubs_ok then
      if stubs.installed(version) then
        ok("Stubs para v" .. version .. " instalados")
      else
        local installed = stubs.get_installed_versions()
        if #installed > 0 then
          warn("No hay stubs para v" .. version .. ". Instalados: " .. table.concat(installed, ", "))
          info("Ejecuta: :OdooDownloadStubs " .. version)
        else
          warn("No hay stubs instalados. Ejecuta :OdooDownloadStubs " .. version)
        end
      end
    end

    -- Verificar estructura específica
    if project_type == "doodba" then
      local doodba_paths = {
        { path = root .. "/odoo/custom/src", name = "Custom addons" },
        { path = root .. "/odoo/auto/addons", name = "Auto addons" },
        { path = root .. "/repos.yaml", name = "repos.yaml" },
        { path = root .. "/addons.yaml", name = "addons.yaml" },
        { path = root .. "/docker-compose.yml", name = "docker-compose.yml" },
      }

      for _, item in ipairs(doodba_paths) do
        if util.exists(item.path) then
          info("  ✓ " .. item.name)
        end
      end

      -- Verificar estado de contenedores
      local docker_ok, docker = pcall(require, "odoo.docker")
      if docker_ok then
        if docker.is_running(root) then
          ok("Contenedores Docker corriendo")
        else
          warn("Contenedores Docker no están corriendo. Ejecuta :OdooDockerUp")
        end
      end
    end

    -- Mostrar addons paths
    local addons = util.get_addons_paths(root)
    if #addons > 0 then
      info("Addons paths encontrados (" .. #addons .. "):")
      for i, path in ipairs(addons) do
        if i <= 5 then
          info("  - " .. util.format_path(path))
        elseif i == 6 then
          info("  ... y " .. (#addons - 5) .. " más")
        end
      end
    end
  else
    info("No se detectó un proyecto Odoo en el directorio actual")
  end

  -- Estado de LSP
  start("LSP Status")

  local clients = vim.lsp.get_clients()
  local pyright_found = false

  for _, client in ipairs(clients) do
    if client.name == "pyright" or client.name == "basedpyright" then
      pyright_found = true
      ok(client.name .. " activo (root: " .. (client.config.root_dir or "N/A") .. ")")

      -- Verificar configuración
      local settings = client.config.settings or {}
      local python = settings.python or {}
      local analysis = python.analysis or {}

      if analysis.stubPath then
        info("stubPath configurado: " .. util.format_path(analysis.stubPath))
      end

      if analysis.extraPaths and #analysis.extraPaths > 0 then
        info("extraPaths: " .. #analysis.extraPaths .. " rutas configuradas")
      end
    end
  end

  if not pyright_found then
    info("No hay cliente pyright/basedpyright activo en el buffer actual")
  end
end

return M
