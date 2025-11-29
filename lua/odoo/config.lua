---@class odoo.Config
---@field stubs odoo.Config.Stubs
---@field lsp odoo.Config.Lsp
---@field navigation odoo.Config.Navigation
---@field detection odoo.Config.Detection
---@field doodba odoo.Config.Doodba
---@field version odoo.Config.Version

---@class odoo.Config.Stubs
---@field repo string URL del repositorio de stubs
---@field branch string|nil Rama del repositorio (nil = auto-detectar)
---@field auto_download boolean Descargar automáticamente si no existen
---@field fallback_branch string Rama por defecto si no se detecta versión

---@class odoo.Config.Lsp
---@field auto_inject boolean Inyectar configuración automáticamente
---@field server "pyright"|"basedpyright" Servidor LSP a configurar
---@field analysis odoo.Config.Lsp.Analysis

---@class odoo.Config.Lsp.Analysis
---@field typeCheckingMode "off"|"basic"|"standard"|"strict" Modo de chequeo de tipos
---@field diagnosticSeverityOverrides table<string, string> Sobrescrituras de severidad
---@field reportGeneralTypeIssues boolean
---@field reportOptionalMemberAccess boolean
---@field reportAttributeAccessIssue boolean

---@class odoo.Config.Navigation
---@field use_telescope boolean Usar telescope para navegación
---@field xml_goto_definition boolean Habilitar gd en archivos XML
---@field keymaps odoo.Config.Navigation.Keymaps

---@class odoo.Config.Navigation.Keymaps
---@field goto_definition string
---@field goto_xml_id string
---@field goto_model string

---@class odoo.Config.Detection
---@field markers string[] Archivos/directorios que identifican un proyecto Odoo
---@field doodba_markers string[] Archivos que identifican un proyecto Doodba
---@field auto_detect boolean Detectar automáticamente proyectos Odoo

---@class odoo.Config.Doodba
---@field enabled boolean Habilitar soporte para Doodba
---@field docker_service string Nombre del servicio de Docker para Odoo
---@field auto_detect_service boolean Detectar automáticamente el servicio
---@field shell_command string Comando para abrir shell en el contenedor
---@field python_path string Path de Python dentro del contenedor
---@field odoo_path string Path de Odoo dentro del contenedor
---@field addons_paths string[] Paths adicionales de addons dentro del contenedor

---@class odoo.Config.Version
---@field auto_detect boolean Detectar versión automáticamente
---@field default string Versión por defecto si no se detecta
---@field supported string[] Versiones soportadas

---@alias odoo.OdooVersion "12.0"|"13.0"|"14.0"|"15.0"|"16.0"|"17.0"|"18.0"|"master"

local M = {}

---Versiones de Odoo soportadas con sus características
---@type table<string, {python: string, stubs_branch: string|nil, manifest: string}>
M.VERSION_INFO = {
  ["12.0"] = {
    python = "3.6",
    stubs_branch = "12.0",
    manifest = "__manifest__.py",
  },
  ["13.0"] = {
    python = "3.6",
    stubs_branch = "13.0",
    manifest = "__manifest__.py",
  },
  ["14.0"] = {
    python = "3.8",
    stubs_branch = "14.0",
    manifest = "__manifest__.py",
  },
  ["15.0"] = {
    python = "3.8",
    stubs_branch = "15.0",
    manifest = "__manifest__.py",
  },
  ["16.0"] = {
    python = "3.10",
    stubs_branch = "16.0",
    manifest = "__manifest__.py",
  },
  ["17.0"] = {
    python = "3.10",
    stubs_branch = "17.0",
    manifest = "__manifest__.py",
  },
  ["18.0"] = {
    python = "3.12",
    stubs_branch = "18.0",
    manifest = "__manifest__.py",
  },
  ["19.0"] = {
    python = "3.12",
    stubs_branch = "master", -- Usar master hasta que exista rama 19.0
    manifest = "__manifest__.py",
  },
  ["master"] = {
    python = "3.12",
    stubs_branch = "master",
    manifest = "__manifest__.py",
  },
  -- Versiones legacy con __openerp__.py
  ["11.0"] = {
    python = "3.5",
    stubs_branch = nil, -- No hay stubs para esta versión
    manifest = "__openerp__.py",
  },
  ["10.0"] = {
    python = "2.7",
    stubs_branch = nil,
    manifest = "__openerp__.py",
  },
  ["9.0"] = {
    python = "2.7",
    stubs_branch = nil,
    manifest = "__openerp__.py",
  },
  ["8.0"] = {
    python = "2.7",
    stubs_branch = nil,
    manifest = "__openerp__.py",
  },
}

---@type odoo.Config
M.defaults = {
  stubs = {
    -- Repositorio oficial de stubs de odoo-ide
    repo = "https://github.com/odoo-ide/odoo-stubs",
    branch = nil, -- nil = auto-detectar basado en versión de Odoo
    auto_download = true,
    fallback_branch = "16.0",
    -- Generación dinámica con stubgen
    generate = {
      enabled = false, -- Habilitar generación dinámica con stubgen
      output_dir = nil, -- nil = usar directorio por defecto
      use_inspect = true, -- Usar --inspect-mode para mejor calidad
    },
  },

  lsp = {
    auto_inject = true,
    server = "pyright",
    analysis = {
      typeCheckingMode = "basic",
      -- Ignorar errores comunes en Odoo por la meta-programación
      diagnosticSeverityOverrides = {
        reportGeneralTypeIssues = "none",
        reportOptionalMemberAccess = "none",
        reportAttributeAccessIssue = "none",
        reportArgumentType = "warning",
        reportUnusedImport = "warning",
        reportUnusedVariable = "warning",
        reportMissingImports = "warning",
        reportPrivateUsage = "none",
        reportUnknownMemberType = "none",
        reportUnknownArgumentType = "none",
        reportUnknownVariableType = "none",
        reportUntypedBaseClass = "none",
        reportOptionalSubscript = "none",
        reportOptionalCall = "none",
        reportOptionalIterable = "none",
        reportOptionalContextManager = "none",
        reportOptionalOperand = "none",
      },
    },
  },

  navigation = {
    use_telescope = true,
    xml_goto_definition = true,
    keymaps = {
      goto_definition = "gd",
      goto_xml_id = "gx",
      goto_model = "gm",
    },
  },

  detection = {
    markers = {
      "odoo-bin",
      "odoo/odoo-bin",
      "openerp-server", -- Versiones antiguas
      ".odoorc",
      "__manifest__.py",
      "__openerp__.py", -- Versiones <= 9.0
    },
    -- Marcadores reales de proyectos Doodba (estructura Copier/Tecnativa)
    doodba_markers = {
      "odools.toml",            -- Archivo de configuración de odools
      "tasks.py",               -- Tareas invoke de Doodba
      "common.yaml",            -- Docker compose común
      "devel.yaml",             -- Docker compose desarrollo
      "prod.yaml",              -- Docker compose producción
      "test.yaml",              -- Docker compose tests
      ".copier-answers.yml",    -- Respuestas de Copier
      "setup-devel.yaml",       -- Setup de desarrollo
    },
    auto_detect = true,
  },

  doodba = {
    enabled = true,
    docker_service = "odoo",
    auto_detect_service = true,
    shell_command = "bash",
    python_path = "/usr/bin/python3",
    odoo_path = "/opt/odoo",
    addons_paths = {
      "/opt/odoo/auto/addons",
      "/opt/odoo/custom/src",
      "/opt/odoo/addons",
    },
  },

  version = {
    auto_detect = true,
    default = "16.0",
    supported = { "12.0", "13.0", "14.0", "15.0", "16.0", "17.0", "18.0", "19.0", "master" },
  },

  -- Configuración de templates y snippets
  templates = {
    enabled = true,
    expand_on_tab = true,
    use_luasnip = true,  -- Usar LuaSnip si está disponible
  },

  -- Configuración de scaffolding
  scaffolding = {
    enabled = true,
    templates_dir = nil,  -- Custom templates directory (nil = usar built-in)
    default_license = "LGPL-3",
    default_author = "Your Company",
    auto_init_file = true,  -- Auto-generar __init__.py
    auto_manifest = true,   -- Auto-generar __manifest__.py
  },
}

---@type odoo.Config
M.options = {}

---Configura el plugin con las opciones del usuario
---@param opts? odoo.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---Obtiene la configuración actual
---@return odoo.Config
function M.get()
  return M.options
end

---Obtiene información de una versión específica con fallback
---@param version string
---@param use_fallback? boolean Si es true, usa fallback para versiones desconocidas
---@return table|nil
---@return boolean is_fallback
function M.get_version_info(version, use_fallback)
  local info = M.VERSION_INFO[version]
  if info then
    return info, false
  end

  -- Si no se encuentra y se permite fallback
  if use_fallback then
    -- Para versiones futuras (20.0+), usar la última versión conocida
    local version_num = tonumber(version:match("^(%d+)%.0$"))
    if version_num and version_num >= 20 then
      -- Usar 19.0 como base para versiones futuras
      return M.VERSION_INFO["19.0"], true
    end

    -- Para versiones entre las soportadas, buscar la más cercana inferior
    if version_num then
      local closest = nil
      local closest_num = 0
      for v, vinfo in pairs(M.VERSION_INFO) do
        local v_num = tonumber(v:match("^(%d+)%.0$"))
        if v_num and v_num < version_num and v_num > closest_num then
          closest = vinfo
          closest_num = v_num
        end
      end
      if closest then
        return closest, true
      end
    end

    -- Fallback final: usar 16.0
    return M.VERSION_INFO["16.0"], true
  end

  return nil, false
end

---Verifica si una versión está soportada
---@param version string
---@return boolean
function M.is_version_supported(version)
  return M.VERSION_INFO[version] ~= nil
end

---Obtiene la rama de stubs para una versión
---@param version string
---@return string|nil
function M.get_stubs_branch(version)
  local info = M.VERSION_INFO[version]
  if info then
    return info.stubs_branch
  end
  return nil
end

---Obtiene la versión de Python recomendada para una versión de Odoo
---@param version string
---@return string
function M.get_python_version(version)
  local info, is_fallback = M.get_version_info(version, true)
  if info then
    return info.python
  end
  return "3.10" -- Default
end

return M
