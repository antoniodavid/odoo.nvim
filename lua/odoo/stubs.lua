---@class odoo.stubs
---Módulo para gestionar la descarga y actualización de stubs de Odoo
---Soporta múltiples versiones de Odoo
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")

---@class odoo.stubs.DownloadState
---@field in_progress boolean
---@field job? vim.SystemObj

---@type odoo.stubs.DownloadState
local state = {
  in_progress = false,
  job = nil,
}

---Obtiene la ruta base donde se guardan los stubs
---@return string
function M.get_base_path()
  return vim.fn.stdpath("data") .. "/odoo-stubs"
end

---Obtiene la ruta de stubs para una versión específica
---@param version? string
---@return string
function M.get_path(version)
  local base = M.get_base_path()
  if version then
    return base .. "/" .. version
  end
  return base
end

---Verifica si los stubs están instalados para una versión
---@param version? string
---@return boolean
function M.installed(version)
  if version then
    local version_path = M.get_path(version)
    return util.exists(version_path) and util.exists(version_path .. "/odoo-stubs")
  end

  -- Verificar si hay alguna versión instalada
  local base = M.get_base_path()
  if not util.exists(base) then
    return false
  end

  -- Buscar cualquier carpeta de versión
  local handle = vim.uv.fs_scandir(base)
  if handle then
    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if type == "directory" and name:match("^%d+%.%d+$") then
        return true
      end
    end
  end

  return false
end

---Obtiene las versiones de stubs instaladas
---@return string[]
function M.get_installed_versions()
  local versions = {}
  local base = M.get_base_path()

  if not util.exists(base) then
    return versions
  end

  local handle = vim.uv.fs_scandir(base)
  if handle then
    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if type == "directory" and name:match("^%d+%.%d+$") or name == "master" then
        if util.exists(base .. "/" .. name .. "/odoo-stubs") then
          table.insert(versions, name)
        end
      end
    end
  end

  table.sort(versions)
  return versions
end

---Obtiene la rama de stubs para una versión de Odoo
---@param version string
---@return string|nil
function M.get_branch_for_version(version)
  local cfg = config.get()

  -- Si el usuario especificó una rama, usarla
  if cfg.stubs.branch then
    return cfg.stubs.branch
  end

  -- Obtener la rama desde la configuración de versiones
  local branch = config.get_stubs_branch(version)
  if branch then
    return branch
  end

  -- Fallback
  return cfg.stubs.fallback_branch
end

---Descarga los stubs de Odoo para una versión específica
---@param opts? {version?: string, force?: boolean, on_complete?: fun(success: boolean)}
function M.download(opts)
  opts = opts or {}

  if state.in_progress then
    util.warn("Ya hay una descarga en progreso...")
    return
  end

  -- Detectar versión si no se especifica
  local version = opts.version
  if not version then
    local root = util.get_odoo_root()
    version = util.get_odoo_version(root)
  end

  local branch = M.get_branch_for_version(version)
  if not branch then
    util.error("No hay stubs disponibles para Odoo " .. version)
    util.info("Versiones con stubs: 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0")
    return
  end

  local stubs_path = M.get_path(version)
  local cfg = config.get().stubs

  -- Si ya existen y no es forzado, salir
  if M.installed(version) and not opts.force then
    util.info("Los stubs para Odoo " .. version .. " ya están instalados en:")
    util.info("  " .. util.format_path(stubs_path))
    util.info("Usa :OdooDownloadStubs! para forzar la actualización")
    return
  end

  state.in_progress = true

  -- Crear directorio padre si no existe
  vim.fn.mkdir(stubs_path, "p")

  local function on_complete(success)
    state.in_progress = false
    state.job = nil
    if opts.on_complete then
      opts.on_complete(success)
    end
  end

  -- Si existe, hacer pull; si no, clonar
  if vim.fn.isdirectory(stubs_path .. "/.git") == 1 then
    M._update_stubs(stubs_path, cfg, branch, version, on_complete)
  else
    M._clone_stubs(stubs_path, cfg, branch, version, on_complete)
  end
end

---Clona el repositorio de stubs
---@param path string
---@param cfg odoo.Config.Stubs
---@param branch string
---@param version string
---@param on_complete fun(success: boolean)
function M._clone_stubs(path, cfg, branch, version, on_complete)
  util.info("󰇚 Clonando stubs de Odoo " .. version .. "...")
  util.info("  Repo: " .. cfg.repo)
  util.info("  Rama: " .. branch)

  -- Limpiar directorio existente si hay
  if vim.fn.isdirectory(path) == 1 then
    vim.fn.delete(path, "rf")
    vim.fn.mkdir(path, "p")
  end

  local cmd = {
    "git",
    "clone",
    "--depth=1",
    "--single-branch",
    "--branch",
    branch,
    cfg.repo,
    path,
  }

  state.job = util.async_cmd(cmd, {
    on_exit = function(code)
      if code == 0 then
        util.info("✓ Stubs para Odoo " .. version .. " descargados correctamente en:")
        util.info("  " .. util.format_path(path))
        on_complete(true)
      else
        util.error("✗ Error al clonar los stubs (código: " .. code .. ")")
        util.error("  Verifica tu conexión a internet y que la rama " .. branch .. " exista")
        on_complete(false)
      end
    end,
  })
end

---Actualiza el repositorio de stubs existente
---@param path string
---@param cfg odoo.Config.Stubs
---@param branch string
---@param version string
---@param on_complete fun(success: boolean)
function M._update_stubs(path, cfg, branch, version, on_complete)
  util.info("󰇚 Actualizando stubs de Odoo " .. version .. "...")

  local cmd = { "git", "pull", "--ff-only" }

  state.job = util.async_cmd(cmd, {
    cwd = path,
    on_exit = function(code)
      if code == 0 then
        util.info("✓ Stubs para Odoo " .. version .. " actualizados correctamente")
        on_complete(true)
      else
        util.warn("⚠ Error al actualizar, intentando re-clonar...")
        -- Si falla el pull, intentar clonar de nuevo
        vim.fn.delete(path, "rf")
        vim.fn.mkdir(path, "p")
        M._clone_stubs(path, cfg, branch, version, on_complete)
      end
    end,
  })
end

---Cancela la descarga en progreso
function M.cancel()
  if state.job then
    state.job:kill(9)
    state.in_progress = false
    state.job = nil
    util.warn("Descarga cancelada")
  end
end

---Elimina los stubs descargados
---@param version? string Si se especifica, solo elimina esa versión
function M.remove(version)
  if version then
    local path = M.get_path(version)
    if vim.fn.isdirectory(path) == 1 then
      vim.fn.delete(path, "rf")
      util.info("Stubs de Odoo " .. version .. " eliminados")
    else
      util.warn("No hay stubs instalados para Odoo " .. version)
    end
  else
    local path = M.get_base_path()
    if vim.fn.isdirectory(path) == 1 then
      vim.fn.delete(path, "rf")
      util.info("Todos los stubs eliminados de: " .. util.format_path(path))
    else
      util.warn("No hay stubs instalados")
    end
  end
end

---Muestra información sobre los stubs instalados
function M.info()
  local base_path = M.get_base_path()
  local versions = M.get_installed_versions()

  util.info("═══════════════════════════════════════")
  util.info("  Odoo Stubs Info")
  util.info("═══════════════════════════════════════")
  util.info("Ruta base: " .. util.format_path(base_path))
  util.info("")

  if #versions == 0 then
    util.warn("No hay stubs instalados")
    util.info("Ejecuta :OdooDownloadStubs para descargarlos")
    return
  end

  util.info("Versiones instaladas:")
  for _, version in ipairs(versions) do
    local path = M.get_path(version)

    -- Obtener información del commit
    local result = vim.system({ "git", "log", "-1", "--format=%h %s (%cr)" }, {
      cwd = path,
      text = true,
    }):wait()

    local commit_info = ""
    if result.code == 0 and result.stdout then
      commit_info = " - " .. vim.trim(result.stdout)
    end

    util.info("  • Odoo " .. version .. commit_info)
  end

  -- Mostrar versión actual del proyecto
  local root = util.get_odoo_root()
  if root then
    local current_version = util.get_odoo_version(root)
    util.info("")
    util.info("Versión del proyecto actual: " .. current_version)
    if not vim.tbl_contains(versions, current_version) then
      util.warn("⚠ No hay stubs instalados para esta versión")
    end
  end
end

---Descarga stubs para todas las versiones soportadas
---@param opts? {on_complete?: fun()}
function M.download_all(opts)
  opts = opts or {}
  local cfg = config.get()
  local versions_to_download = {}

  -- Filtrar versiones que tienen stubs disponibles
  for _, version in ipairs(cfg.version.supported) do
    local branch = config.get_stubs_branch(version)
    if branch then
      table.insert(versions_to_download, version)
    end
  end

  if #versions_to_download == 0 then
    util.warn("No hay versiones con stubs disponibles")
    return
  end

  util.info("Descargando stubs para " .. #versions_to_download .. " versiones...")

  local completed = 0
  local function download_next()
    completed = completed + 1
    if completed <= #versions_to_download then
      local version = versions_to_download[completed]
      M.download({
        version = version,
        force = false,
        on_complete = function()
          vim.defer_fn(download_next, 500)
        end,
      })
    else
      util.info("✓ Descarga de todos los stubs completada")
      if opts.on_complete then
        opts.on_complete()
      end
    end
  end

  download_next()
end

---Registra los comandos del módulo
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooDownloadStubs", function(cmd_opts)
    local version = cmd_opts.args ~= "" and cmd_opts.args or nil
    M.download({ force = cmd_opts.bang, version = version })
  end, {
    bang = true,
    nargs = "?",
    desc = "Descarga los stubs de Odoo (usa ! para forzar, opcionalmente especifica versión)",
    complete = function()
      local cfg = config.get()
      return cfg.version.supported
    end,
  })

  vim.api.nvim_create_user_command("OdooDownloadAllStubs", function()
    M.download_all()
  end, {
    desc = "Descarga stubs para todas las versiones de Odoo soportadas",
  })

  vim.api.nvim_create_user_command("OdooRemoveStubs", function(cmd_opts)
    local version = cmd_opts.args ~= "" and cmd_opts.args or nil
    M.remove(version)
  end, {
    nargs = "?",
    desc = "Elimina los stubs de Odoo (opcionalmente especifica versión)",
    complete = function()
      return M.get_installed_versions()
    end,
  })

  vim.api.nvim_create_user_command("OdooStubsInfo", function()
    M.info()
  end, {
    desc = "Muestra información sobre los stubs instalados",
  })

  vim.api.nvim_create_user_command("OdooGenerateStubs", function(cmd_opts)
    local path = cmd_opts.args ~= "" and cmd_opts.args or nil
    M.generate_stubs({ path = path, force = cmd_opts.bang })
  end, {
    bang = true,
    nargs = "?",
    desc = "Genera stubs dinámicamente con stubgen (usa ! para forzar)",
    complete = "file",
  })
end

-- ============================================================================
-- GENERACIÓN DINÁMICA DE STUBS CON STUBGEN
-- ============================================================================

---Verifica si stubgen está disponible
---@return boolean
function M.stubgen_available()
  local result = vim.system({ "stubgen", "--version" }, { text = true }):wait()
  return result.code == 0
end

---Genera stubs dinámicamente usando stubgen de mypy
---Útil para versiones de Odoo sin stubs preexistentes o para módulos custom
---@param opts? {path?: string, output?: string, force?: boolean, on_complete?: fun(success: boolean)}
function M.generate_stubs(opts)
  opts = opts or {}

  -- Verificar que stubgen esté disponible
  if not M.stubgen_available() then
    util.error("stubgen no está disponible. Instálalo con: pip install mypy")
    util.info("  pip install mypy --break-system-packages")
    return
  end

  -- Detectar path de Odoo si no se especifica
  local odoo_path = opts.path
  if not odoo_path then
    local root, project_type = util.get_odoo_root()
    if not root then
      util.error("No se detectó un proyecto Odoo")
      return
    end

    -- Buscar el directorio de Odoo source
    if project_type == "doodba" then
      -- En Doodba, buscar en el contenedor o en odoo/auto
      odoo_path = root .. "/odoo/auto/addons/odoo"
      if not util.exists(odoo_path) then
        util.warn("No se encontró el código fuente de Odoo")
        util.info("En proyectos Doodba, considera ejecutar stubgen dentro del contenedor")
        util.info("  :OdooDockerExec stubgen -p odoo -o /opt/odoo/stubs")
        return
      end
    else
      -- En proyectos estándar, buscar odoo/
      odoo_path = root .. "/odoo"
      if not util.exists(odoo_path) then
        odoo_path = root
      end
    end
  end

  -- Determinar directorio de salida
  local version = util.get_odoo_version(odoo_path)
  local output_dir = opts.output or (M.get_base_path() .. "/generated-" .. version)

  -- Verificar si ya existen stubs generados
  if util.exists(output_dir) and not opts.force then
    util.info("Ya existen stubs generados en: " .. util.format_path(output_dir))
    util.info("Usa :OdooGenerateStubs! para forzar regeneración")
    return
  end

  -- Crear directorio de salida
  vim.fn.mkdir(output_dir, "p")

  util.info("🔧 Generando stubs con stubgen...")
  util.info("  Fuente: " .. util.format_path(odoo_path))
  util.info("  Salida: " .. util.format_path(output_dir))

  -- Construir comando stubgen
  -- Opciones importantes:
  -- --inspect-mode: Importa e inspecciona módulos para mejor calidad
  -- --include-docstrings: Incluye docstrings en stubs
  -- --no-import: Evita ejecutar código (más seguro pero menor calidad)
  local cmd = {
    "stubgen",
    "-p", "odoo",              -- Paquete a generar
    "-o", output_dir,          -- Directorio de salida
    "--ignore-errors",         -- Continuar si hay errores
  }

  -- Usar inspect-mode si está configurado (mejor calidad)
  local cfg = config.get()
  if cfg.stubs.generate.use_inspect then
    table.insert(cmd, "--inspect-mode")
  else
    table.insert(cmd, "--no-import")
  end

  state.in_progress = true

  state.job = util.async_cmd(cmd, {
    cwd = odoo_path,
    on_exit = function(code)
      state.in_progress = false
      state.job = nil

      if code == 0 then
        util.info("✓ Stubs generados correctamente en:")
        util.info("  " .. util.format_path(output_dir))
        util.info("")
        util.info("Nota: Los stubs generados son borradores y pueden")
        util.info("requerir ajustes manuales para mejor precisión.")

        if opts.on_complete then
          opts.on_complete(true)
        end
      else
        util.error("✗ Error al generar stubs (código: " .. code .. ")")
        util.info("Intenta con --no-import si hay errores de importación")

        if opts.on_complete then
          opts.on_complete(false)
        end
      end
    end,
  })
end

---Genera stubs para un módulo específico
---@param module_name string
---@param opts? {output?: string, on_complete?: fun(success: boolean)}
function M.generate_module_stubs(module_name, opts)
  opts = opts or {}

  if not M.stubgen_available() then
    util.error("stubgen no está disponible. Instálalo con: pip install mypy")
    return
  end

  local root = util.get_odoo_root()
  if not root then
    util.error("No se detectó un proyecto Odoo")
    return
  end

  local version = util.get_odoo_version(root)
  local output_dir = opts.output or (M.get_base_path() .. "/modules-" .. version)

  vim.fn.mkdir(output_dir, "p")

  util.info("🔧 Generando stubs para módulo: " .. module_name)

  local cmd = {
    "stubgen",
    "-m", module_name,
    "-o", output_dir,
    "--ignore-errors",
    "--no-import",  -- Más seguro para módulos individuales
  }

  state.job = util.async_cmd(cmd, {
    cwd = root,
    on_exit = function(code)
      state.job = nil

      if code == 0 then
        util.info("✓ Stubs generados para " .. module_name)
        if opts.on_complete then
          opts.on_complete(true)
        end
      else
        util.error("✗ Error al generar stubs para " .. module_name)
        if opts.on_complete then
          opts.on_complete(false)
        end
      end
    end,
  })
end

---Obtiene información sobre las capacidades de generación de stubs
function M.stubgen_info()
  util.info("═══════════════════════════════════════")
  util.info("  Generación Dinámica de Stubs")
  util.info("═══════════════════════════════════════")

  if M.stubgen_available() then
    util.info("✓ stubgen está disponible")

    local result = vim.system({ "stubgen", "--version" }, { text = true }):wait()
    if result.stdout then
      util.info("  Versión: " .. vim.trim(result.stdout))
    end
  else
    util.warn("✗ stubgen no está disponible")
    util.info("  Instálalo con: pip install mypy")
  end

  util.info("")
  util.info("Comandos disponibles:")
  util.info("  :OdooGenerateStubs [path]  - Genera stubs para Odoo")
  util.info("  :OdooGenerateStubs!        - Fuerza regeneración")
  util.info("")
  util.info("Opciones de stubgen:")
  util.info("  --inspect-mode: Mejor calidad (requiere importar)")
  util.info("  --no-import: Más seguro (menor calidad)")
  util.info("  --include-docstrings: Incluye documentación")
end

return M
