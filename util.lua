---@class odoo.util
local M = {}

---@type table<string, boolean>
M._warned = {}

---@alias odoo.ProjectType "standard"|"doodba"|nil

---Notificación con nivel INFO
---@param msg string
---@param opts? table
function M.info(msg, opts)
  opts = opts or {}
  opts.title = opts.title or "Odoo"
  vim.notify(msg, vim.log.levels.INFO, opts)
end

---Notificación con nivel WARN
---@param msg string
---@param opts? table
function M.warn(msg, opts)
  opts = opts or {}
  opts.title = opts.title or "Odoo"
  vim.notify(msg, vim.log.levels.WARN, opts)
end

---Notificación con nivel ERROR
---@param msg string
---@param opts? table
function M.error(msg, opts)
  opts = opts or {}
  opts.title = opts.title or "Odoo"
  vim.notify(msg, vim.log.levels.ERROR, opts)
end

---Notificación con nivel DEBUG (solo una vez por mensaje)
---@param msg string
function M.debug(msg)
  if M._warned[msg] then
    return
  end
  M._warned[msg] = true
  vim.notify(msg, vim.log.levels.DEBUG, { title = "Odoo (Debug)" })
end

---Verifica si un archivo o directorio existe
---@param path string
---@return boolean
function M.exists(path)
  return vim.fn.isdirectory(path) == 1 or vim.fn.filereadable(path) == 1
end

---Verifica si un archivo contiene un patrón
---@param filepath string
---@param pattern string
---@return boolean
function M.file_contains(filepath, pattern)
  if vim.fn.filereadable(filepath) ~= 1 then
    return false
  end
  local content = vim.fn.readfile(filepath)
  for _, line in ipairs(content) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

---Detecta si es un proyecto Doodba
---@param start_path? string
---@return string|nil root_path
function M.get_doodba_root(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Marcadores específicos de Doodba
  local doodba_markers = {
    "repos.yaml",
    "addons.yaml",
    ".copier-answers.yml",
  }

  -- Buscar marcadores de Doodba
  local root = vim.fs.find(doodba_markers, {
    path = start_path,
    upward = true,
    stop = vim.env.HOME,
    type = "file",
  })

  if #root > 0 then
    local potential_root = vim.fs.dirname(root[1])
    -- Verificar que tenga estructura Doodba
    if M._is_valid_doodba_structure(potential_root) then
      return potential_root
    end
  end

  -- Buscar docker-compose con servicios de Odoo
  local compose_files = vim.fs.find({ "docker-compose.yml", "docker-compose.yaml" }, {
    path = start_path,
    upward = true,
    stop = vim.env.HOME,
    type = "file",
  })

  for _, compose_file in ipairs(compose_files) do
    if M.file_contains(compose_file, "odoo") then
      local potential_root = vim.fs.dirname(compose_file)
      if M._is_valid_doodba_structure(potential_root) then
        return potential_root
      end
    end
  end

  return nil
end

---Verifica si tiene estructura válida de Doodba
---@param root string
---@return boolean
function M._is_valid_doodba_structure(root)
  -- Doodba tiene estructura: odoo/custom/src/ o similar
  local doodba_dirs = {
    root .. "/odoo/custom/src",
    root .. "/odoo/auto/addons",
    root .. "/private",
  }

  for _, dir in ipairs(doodba_dirs) do
    if M.exists(dir) then
      return true
    end
  end

  -- También verificar si existe repos.yaml o addons.yaml
  return M.exists(root .. "/repos.yaml") or M.exists(root .. "/addons.yaml")
end

---Obtiene la ruta raíz del proyecto Odoo estándar
---@param start_path? string
---@return string|nil
function M.get_standard_odoo_root(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Marcadores que indican un proyecto Odoo estándar
  local markers = {
    "odoo-bin",
    "odoo/odoo-bin",
    ".odoorc",
  }

  local root = vim.fs.find(markers, {
    path = start_path,
    upward = true,
    stop = vim.env.HOME,
    type = "file",
  })

  if #root > 0 then
    return vim.fs.dirname(root[1])
  end

  -- Buscar __manifest__.py como fallback
  local manifest = vim.fs.find("__manifest__.py", {
    path = start_path,
    upward = true,
    stop = vim.env.HOME,
    type = "file",
  })

  if #manifest > 0 then
    -- Subir hasta encontrar el directorio que contiene addons
    local current = vim.fs.dirname(manifest[1])
    for _ = 1, 5 do
      local parent = vim.fs.dirname(current)
      if M.exists(parent .. "/odoo-bin") or M.exists(parent .. "/addons") then
        return parent
      end
      current = parent
    end
    return vim.fs.dirname(manifest[1])
  end

  return nil
end

---Obtiene la ruta raíz del proyecto Odoo (estándar o Doodba)
---@param start_path? string
---@return string|nil root, odoo.ProjectType type
function M.get_odoo_root(start_path)
  start_path = start_path or vim.fn.getcwd()

  -- Primero verificar Doodba (más específico)
  local doodba_root = M.get_doodba_root(start_path)
  if doodba_root then
    return doodba_root, "doodba"
  end

  -- Luego verificar Odoo estándar
  local standard_root = M.get_standard_odoo_root(start_path)
  if standard_root then
    return standard_root, "standard"
  end

  return nil, nil
end

---Obtiene el tipo de proyecto
---@return odoo.ProjectType
function M.get_project_type()
  local _, project_type = M.get_odoo_root()
  return project_type
end

---Verifica si el proyecto actual es un proyecto Odoo
---@return boolean
function M.is_odoo_project()
  local root = M.get_odoo_root()
  return root ~= nil
end

---Verifica si es un proyecto Doodba
---@return boolean
function M.is_doodba_project()
  return M.get_project_type() == "doodba"
end

---Obtiene la ruta de los stubs
---@return string
function M.get_stubs_path()
  return vim.fn.stdpath("data") .. "/odoo-stubs"
end

---Verifica si los stubs están instalados
---@return boolean
function M.stubs_installed()
  local stubs_path = M.get_stubs_path()
  return M.exists(stubs_path) and M.exists(stubs_path .. "/odoo-stubs")
end

---Ejecuta un comando de forma asíncrona
---@param cmd string[]
---@param opts? {cwd?: string, on_exit?: fun(code: number, signal: number), on_stdout?: fun(data: string)}
---@return vim.SystemObj
function M.async_cmd(cmd, opts)
  opts = opts or {}
  return vim.system(cmd, {
    cwd = opts.cwd,
    text = true,
    stdout = opts.on_stdout and function(err, data)
      if data then
        vim.schedule(function()
          opts.on_stdout(data)
        end)
      end
    end or nil,
  }, function(obj)
    if opts.on_exit then
      vim.schedule(function()
        opts.on_exit(obj.code, obj.signal)
      end)
    end
  end)
end

---Debounce una función
---@param fn function
---@param ms number
---@return function
function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

---Obtiene todos los addons paths del proyecto Odoo estándar
---@param root string
---@return string[]
function M.get_standard_addons_paths(root)
  local paths = {}

  -- Rutas comunes de addons en Odoo estándar
  local common_addon_dirs = {
    "addons",
    "odoo/addons",
    "enterprise",
    "custom",
    "custom_addons",
  }

  for _, dir in ipairs(common_addon_dirs) do
    local full_path = root .. "/" .. dir
    if M.exists(full_path) then
      table.insert(paths, full_path)
    end
  end

  return paths
end

---Obtiene todos los addons paths de un proyecto Doodba
---@param root string
---@return string[]
function M.get_doodba_addons_paths(root)
  local paths = {}

  -- Estructura típica de Doodba
  local doodba_addon_dirs = {
    -- Addons custom del proyecto
    "odoo/custom/src",
    -- Addons descargados automáticamente
    "odoo/auto/addons",
    -- Addons privados
    "private",
    -- Addons enterprise (si existe)
    "odoo/custom/src/enterprise",
    -- Otras ubicaciones comunes
    "odoo/custom/dependencies",
  }

  for _, dir in ipairs(doodba_addon_dirs) do
    local full_path = root .. "/" .. dir
    if M.exists(full_path) then
      table.insert(paths, full_path)
      -- Buscar subdirectorios que sean módulos (tienen __manifest__.py)
      M._add_addon_subdirs(full_path, paths)
    end
  end

  -- Buscar en repos.yaml para paths adicionales
  local repos_file = root .. "/repos.yaml"
  if M.exists(repos_file) then
    local extra_paths = M._parse_repos_yaml(repos_file, root)
    for _, path in ipairs(extra_paths) do
      if not vim.tbl_contains(paths, path) then
        table.insert(paths, path)
      end
    end
  end

  return paths
end

---Añade subdirectorios de addons al path
---@param base_path string
---@param paths string[]
function M._add_addon_subdirs(base_path, paths)
  local handle = vim.uv.fs_scandir(base_path)
  if not handle then
    return
  end

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if type == "directory" then
      local subdir = base_path .. "/" .. name
      -- Verificar si es un directorio de addons (contiene módulos)
      if M.exists(subdir .. "/__manifest__.py") or M.exists(subdir .. "/__openerp__.py") then
        -- Es un módulo, añadir su directorio padre si no está
        if not vim.tbl_contains(paths, base_path) then
          table.insert(paths, base_path)
        end
      end
    end
  end
end

---Parsea repos.yaml para obtener paths de repositorios
---@param repos_file string
---@param root string
---@return string[]
function M._parse_repos_yaml(repos_file, root)
  local paths = {}

  -- Lectura simple del archivo repos.yaml
  local content = vim.fn.readfile(repos_file)
  local current_repo = nil

  for _, line in ipairs(content) do
    -- Detectar rutas de repositorios
    local repo_path = line:match("^%s*['\"]?%./([^'\":]+)['\"]?%s*:")
    if repo_path then
      current_repo = root .. "/" .. repo_path
      if M.exists(current_repo) and not vim.tbl_contains(paths, current_repo) then
        table.insert(paths, current_repo)
      end
    end
  end

  return paths
end

---Obtiene todos los addons paths del proyecto (detecta tipo automáticamente)
---@param root string
---@return string[]
function M.get_addons_paths(root)
  local _, project_type = M.get_odoo_root()

  if project_type == "doodba" then
    return M.get_doodba_addons_paths(root)
  else
    return M.get_standard_addons_paths(root)
  end
end

---Formatea una ruta para mostrar al usuario
---@param path string
---@return string
function M.format_path(path)
  local home = vim.env.HOME
  if home and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

---Detecta la versión de Odoo en un proyecto
---@param root string
---@return string|nil version
function M.detect_odoo_version(root)
  -- Método 1: Leer release.py o __init__.py de odoo
  local version = M._detect_version_from_release(root)
  if version then
    return version
  end

  -- Método 2: Buscar en docker-compose.yml (para Doodba)
  version = M._detect_version_from_docker(root)
  if version then
    return version
  end

  -- Método 3: Buscar en .copier-answers.yml (para Doodba con copier)
  version = M._detect_version_from_copier(root)
  if version then
    return version
  end

  -- Método 4: Buscar en requirements.txt
  version = M._detect_version_from_requirements(root)
  if version then
    return version
  end

  -- Método 5: Buscar en .env
  version = M._detect_version_from_env(root)
  if version then
    return version
  end

  return nil
end

---Detecta versión desde release.py o __init__.py
---@param root string
---@return string|nil
function M._detect_version_from_release(root)
  local release_paths = {
    root .. "/odoo/release.py",
    root .. "/openerp/release.py", -- Versiones antiguas
    root .. "/odoo/__init__.py",
  }

  for _, filepath in ipairs(release_paths) do
    if M.exists(filepath) then
      local content = vim.fn.readfile(filepath)
      for _, line in ipairs(content) do
        -- Buscar patrones como: version_info = (16, 0, 0, FINAL, 0, '')
        local major, minor = line:match("version_info%s*=%s*%(%s*(%d+)%s*,%s*(%d+)")
        if major and minor then
          return major .. "." .. minor
        end

        -- Buscar patrones como: version = '16.0'
        local version = line:match("version%s*=%s*['\"](%d+%.%d+)")
        if version then
          return version
        end
      end
    end
  end

  return nil
end

---Detecta versión desde docker-compose.yml
---@param root string
---@return string|nil
function M._detect_version_from_docker(root)
  local compose_files = {
    root .. "/docker-compose.yml",
    root .. "/docker-compose.yaml",
  }

  for _, filepath in ipairs(compose_files) do
    if M.exists(filepath) then
      local content = vim.fn.readfile(filepath)
      local content_str = table.concat(content, "\n")

      -- Buscar imagen de Odoo con versión
      -- Patrones: odoo:16.0, ghcr.io/tecnativa/doodba:16.0, etc.
      local version = content_str:match("odoo:(%d+%.%d+)")
      if version then
        return version
      end

      version = content_str:match("doodba:(%d+%.%d+)")
      if version then
        return version
      end

      -- Buscar ODOO_VERSION en environment
      version = content_str:match("ODOO_VERSION[=:]%s*['\"]?(%d+%.%d+)")
      if version then
        return version
      end
    end
  end

  return nil
end

---Detecta versión desde .copier-answers.yml
---@param root string
---@return string|nil
function M._detect_version_from_copier(root)
  local filepath = root .. "/.copier-answers.yml"
  if not M.exists(filepath) then
    return nil
  end

  local content = vim.fn.readfile(filepath)
  for _, line in ipairs(content) do
    local version = line:match("odoo_version:%s*['\"]?(%d+%.%d+)")
    if version then
      return version
    end
  end

  return nil
end

---Detecta versión desde requirements.txt
---@param root string
---@return string|nil
function M._detect_version_from_requirements(root)
  local req_files = {
    root .. "/requirements.txt",
    root .. "/odoo/requirements.txt",
  }

  for _, filepath in ipairs(req_files) do
    if M.exists(filepath) then
      local content = vim.fn.readfile(filepath)
      for _, line in ipairs(content) do
        -- Buscar odoo==16.0.* o similar
        local version = line:match("odoo[=<>]+(%d+%.%d+)")
        if version then
          return version
        end
      end
    end
  end

  return nil
end

---Detecta versión desde archivo .env
---@param root string
---@return string|nil
function M._detect_version_from_env(root)
  local env_files = {
    root .. "/.env",
    root .. "/.env.local",
  }

  for _, filepath in ipairs(env_files) do
    if M.exists(filepath) then
      local content = vim.fn.readfile(filepath)
      for _, line in ipairs(content) do
        local version = line:match("ODOO_VERSION%s*=%s*['\"]?(%d+%.%d+)")
        if version then
          return version
        end
      end
    end
  end

  return nil
end

---Obtiene la versión de Odoo (detectada o por defecto)
---@param root? string
---@return string
function M.get_odoo_version(root)
  local config = require("odoo.config")
  local cfg = config.get()

  if root and cfg.version.auto_detect then
    local detected = M.detect_odoo_version(root)
    if detected then
      return detected
    end
  end

  return cfg.version.default
end

---Verifica si la versión de Odoo usa __openerp__.py (versiones <= 9.0)
---@param version string
---@return boolean
function M.is_legacy_odoo(version)
  local major = tonumber(version:match("^(%d+)"))
  return major and major <= 9
end

---Obtiene el nombre del archivo manifest según la versión
---@param version string
---@return string
function M.get_manifest_filename(version)
  if M.is_legacy_odoo(version) then
    return "__openerp__.py"
  end
  return "__manifest__.py"
end

---Obtiene el nombre del servicio de Docker para Odoo
---@param root string
---@return string
function M.get_docker_service(root)
  -- Intentar detectar el nombre del servicio de docker-compose
  local compose_files = { "docker-compose.yml", "docker-compose.yaml", "docker-compose.override.yml" }

  for _, file in ipairs(compose_files) do
    local filepath = root .. "/" .. file
    if M.exists(filepath) then
      local content = vim.fn.readfile(filepath)
      for i, line in ipairs(content) do
        -- Buscar servicios que parezcan ser Odoo
        if line:match("^%s+odoo:") then
          return "odoo"
        elseif line:match("^%s+web:") and i < #content then
          -- Verificar si el siguiente servicio usa imagen de Odoo
          local next_lines = table.concat(vim.list_slice(content, i, i + 5), "\n")
          if next_lines:match("image:%s*['\"]?.*odoo") then
            return "web"
          end
        end
      end
    end
  end

  return "odoo" -- Default
end

---Verifica si Docker está disponible y corriendo
---@return boolean
function M.docker_available()
  local result = vim.system({ "docker", "info" }, { text = true }):wait()
  return result.code == 0
end

---Verifica si docker-compose está disponible
---@return string|nil comando disponible
function M.get_compose_cmd()
  -- Verificar docker compose (nuevo)
  local result = vim.system({ "docker", "compose", "version" }, { text = true }):wait()
  if result.code == 0 then
    return "docker compose"
  end

  -- Verificar docker-compose (legacy)
  result = vim.system({ "docker-compose", "version" }, { text = true }):wait()
  if result.code == 0 then
    return "docker-compose"
  end

  return nil
end

return M
