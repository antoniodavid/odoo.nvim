---@class odoo.scaffold
---Módulo para scaffolding de módulos, modelos y vistas de Odoo
---Soporta wizards interactivos con nui.nvim
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")
local templates = require("odoo.templates")

---Verifica si nui.nvim está disponible
---@return boolean, any
local function has_nui()
  return pcall(require, "nui.popup")
end

---Crea un directorio si no existe
---@param path string
---@return boolean
local function ensure_dir(path)
  if not util.exists(path) then
    vim.fn.mkdir(path, "p")
    return true
  end
  return false
end

---Escribe contenido en un archivo
---@param filepath string
---@param content string
local function write_file(filepath, content)
  local file = io.open(filepath, "w")
  if file then
    file:write(content)
    file:close()
    return true
  end
  return false
end

---@class ModuleConfig
---@field name string Nombre técnico del módulo
---@field display_name string Nombre para mostrar
---@field category string Categoría del módulo
---@field summary string Resumen corto
---@field author string Autor
---@field license string Licencia
---@field version string Versión de Odoo
---@field create_model boolean Crear modelo inicial
---@field create_views boolean Crear vistas
---@field create_security boolean Crear seguridad
---@field model_name? string Nombre del modelo (si create_model=true)

---Genera la estructura de directorios de un módulo
---@param base_path string Ruta donde crear el módulo
---@param module_config ModuleConfig
function M.generate_module_structure(base_path, module_config)
  local module_path = base_path .. "/" .. module_config.name

  -- Crear directorio principal
  if not ensure_dir(module_path) then
    util.error("El módulo '" .. module_config.name .. "' ya existe")
    return false
  end

  util.info("Creando estructura del módulo '" .. module_config.name .. "'...")

  -- Crear subdirectorios
  ensure_dir(module_path .. "/models")
  ensure_dir(module_path .. "/views")
  ensure_dir(module_path .. "/security")
  ensure_dir(module_path .. "/data")
  ensure_dir(module_path .. "/static/description")

  -- Generar __manifest__.py
  local manifest_vars = {
    display_name = module_config.display_name,
    version = module_config.version or "1.0",
    category = module_config.category or "Uncategorized",
    summary = module_config.summary or module_config.display_name,
    description = module_config.summary or module_config.display_name,
    author = module_config.author,
    website = "",
    license = module_config.license,
    application = "False",
  }

  local manifest_content = templates.generate("manifest", manifest_vars)
  write_file(module_path .. "/__manifest__.py", manifest_content)

  -- Generar __init__.py principal
  local module_init_content = templates.generate("module_init", {})
  write_file(module_path .. "/__init__.py", module_init_content)

  -- Si se debe crear un modelo inicial
  if module_config.create_model and module_config.model_name then
    local model_filename = module_config.model_name:gsub("%.", "_")

    -- Generar modelo
    local model_vars = {
      ModelClass = module_config.model_name:gsub("^%l", string.upper):gsub("%.%l", string.upper):gsub("%.", ""),
      model_name = module_config.model_name,
      description = module_config.display_name,
    }

    local model_content = templates.generate("model", model_vars)
    write_file(module_path .. "/models/" .. model_filename .. ".py", model_content)

    -- Generar __init__.py de models
    local models_init_vars = {
      model_file = model_filename,
    }
    local models_init_content = templates.generate("models_init", models_init_vars)
    write_file(module_path .. "/models/__init__.py", models_init_content)

    -- Si se deben crear vistas
    if module_config.create_views then
      local view_vars = {
        model_name = module_config.model_name,
        model_underscore = module_config.model_name:gsub("%.", "_"),
        description = module_config.display_name,
      }

      -- Crear archivo de vistas combinado
      local views_content = '<?xml version="1.0" encoding="UTF-8"?>\n<odoo>\n\n'

      -- Vista form
      local form_content = templates.generate("form", view_vars)
      views_content = views_content .. form_content .. "\n\n"

      -- Vista tree
      local tree_content = templates.generate("tree", view_vars)
      views_content = views_content .. tree_content .. "\n\n"

      -- Vista search
      local search_content = templates.generate("search", view_vars)
      views_content = views_content .. search_content .. "\n\n"

      -- Action y menu
      views_content = views_content .. [[
    <record id="action_]] .. view_vars.model_underscore .. [[" model="ir.actions.act_window">
        <field name="name">]] .. module_config.display_name .. [[</field>
        <field name="res_model">]] .. module_config.model_name .. [[</field>
        <field name="view_mode">tree,form</field>
    </record>

    <menuitem id="menu_]] .. view_vars.model_underscore .. [["
              name="]] .. module_config.display_name .. [["
              action="action_]] .. view_vars.model_underscore .. [["
              sequence="10"/>

</odoo>
]]

      write_file(module_path .. "/views/" .. model_filename .. "_views.xml", views_content)
    end

    -- Si se debe crear seguridad
    if module_config.create_security then
      local security_vars = {
        model_name = module_config.model_name,
        model_underscore = module_config.model_name:gsub("%.", "_"),
      }

      local security_content = templates.generate("security", security_vars)
      write_file(module_path .. "/security/ir.model.access.csv", security_content)
    end
  else
    -- Crear archivos vacíos básicos si no se crea modelo
    write_file(module_path .. "/models/__init__.py", "# -*- coding: utf-8 -*-\n")
    write_file(module_path .. "/views/views.xml", '<?xml version="1.0" encoding="UTF-8"?>\n<odoo>\n</odoo>\n')

    if module_config.create_security then
      write_file(
        module_path .. "/security/ir.model.access.csv",
        "id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink\n"
      )
    end
  end

  util.info("✓ Módulo '" .. module_config.name .. "' creado exitosamente")
  util.info("  Ruta: " .. module_path)

  return true, module_path
end

---Wizard con vim.ui.input (fallback sin nui.nvim)
---@param callback function
local function wizard_simple(callback)
  local cfg = config.get()
  local module_config = {}

  -- Paso 1: Nombre del módulo
  vim.ui.input({
    prompt = "Nombre técnico del módulo (ej. my_module): ",
  }, function(name)
    if not name or name == "" then
      return
    end

    module_config.name = name

    -- Paso 2: Display name
    vim.ui.input({
      prompt = "Nombre para mostrar: ",
      default = name:gsub("_", " "):gsub("^%l", string.upper),
    }, function(display_name)
      module_config.display_name = display_name or name

      -- Paso 3: Categoría
      vim.ui.select({
        "Accounting",
        "CRM",
        "Sales",
        "Purchase",
        "Inventory",
        "Manufacturing",
        "Human Resources",
        "Marketing",
        "Website",
        "Services",
        "Productivity",
        "Administration",
        "Customizations",
        "Hidden",
        "Uncategorized",
      }, {
        prompt = "Categoría: ",
      }, function(category)
        module_config.category = category or "Uncategorized"

        -- Paso 4: Resumen
        vim.ui.input({
          prompt = "Resumen (summary): ",
          default = module_config.display_name,
        }, function(summary)
          module_config.summary = summary or module_config.display_name

          -- Paso 5: Autor (desde config)
          module_config.author = cfg.scaffolding.default_author

          -- Paso 6: Licencia (desde config)
          module_config.license = cfg.scaffolding.default_license

          -- Paso 7: Versión de Odoo
          local root, _ = util.get_odoo_root()
          if root then
            module_config.version = util.get_odoo_version(root)
          else
            module_config.version = cfg.version.default
          end

          -- Paso 8: ¿Crear modelo inicial?
          vim.ui.select({
            "Sí",
            "No",
          }, {
            prompt = "¿Crear modelo inicial?",
          }, function(create_model)
            module_config.create_model = (create_model == "Sí")

            if module_config.create_model then
              -- Preguntar nombre del modelo
              vim.ui.input({
                prompt = "Nombre del modelo (ej. x_" .. name .. "): ",
                default = "x_" .. name,
              }, function(model_name)
                module_config.model_name = model_name or ("x_" .. name)

                -- Paso 9: ¿Crear vistas?
                vim.ui.select({
                  "Sí",
                  "No",
                }, {
                  prompt = "¿Crear vistas automáticamente?",
                }, function(create_views)
                  module_config.create_views = (create_views == "Sí")

                  -- Paso 10: ¿Crear security?
                  vim.ui.select({
                    "Sí",
                    "No",
                  }, {
                    prompt = "¿Crear archivos de seguridad?",
                  }, function(create_security)
                    module_config.create_security = (create_security == "Sí")

                    -- Ejecutar callback
                    callback(module_config)
                  end)
                end)
              end)
            else
              module_config.create_views = false

              -- Preguntar por security sin modelo
              vim.ui.select({
                "Sí",
                "No",
              }, {
                prompt = "¿Crear archivos de seguridad?",
              }, function(create_security)
                module_config.create_security = (create_security == "Sí")
                callback(module_config)
              end)
            end
          end)
        end)
      end)
    end)
  end)
end

---Wizard con nui.nvim (interfaz mejorada)
---@param callback function
local function wizard_nui(callback)
  local has_nui_popup, Popup = pcall(require, "nui.popup")
  local has_nui_input, Input = pcall(require, "nui.input")

  if not (has_nui_popup and has_nui_input) then
    util.warn("nui.nvim no disponible, usando wizard simple")
    wizard_simple(callback)
    return
  end

  local cfg = config.get()
  local module_config = {}

  -- Crear popup de información
  local info_popup = Popup({
    position = "50%",
    size = {
      width = 60,
      height = 12,
    },
    enter = false,
    focusable = false,
    zindex = 50,
    relative = "editor",
    border = {
      padding = {
        top = 1,
        bottom = 1,
        left = 2,
        right = 2,
      },
      style = "rounded",
      text = {
        top = " 🐍 Odoo Module Wizard ",
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  })

  local function update_info()
    local lines = {
      "Configuración del módulo:",
      "",
      "Nombre: " .. (module_config.name or "-"),
      "Display: " .. (module_config.display_name or "-"),
      "Categoría: " .. (module_config.category or "-"),
      "Autor: " .. (module_config.author or cfg.scaffolding.default_author),
      "Licencia: " .. (module_config.license or cfg.scaffolding.default_license),
      "",
      "Crear modelo: " .. (module_config.create_model and "Sí" or "No"),
      "Crear vistas: " .. (module_config.create_views and "Sí" or "No"),
    }

    vim.api.nvim_buf_set_option(info_popup.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(info_popup.bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(info_popup.bufnr, "modifiable", false)
  end

  info_popup:mount()
  update_info()

  -- Helper para crear inputs
  local function create_input(prompt, default, on_submit)
    local input = Input({
      position = {
        row = "80%",
        col = "50%",
      },
      size = {
        width = 50,
      },
      border = {
        style = "single",
        text = {
          top = " " .. prompt .. " ",
          top_align = "left",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    }, {
      prompt = "> ",
      default_value = default or "",
      on_submit = on_submit,
    })

    input:mount()
    return input
  end

  -- Paso 1: Nombre técnico
  local input1 = create_input("Nombre técnico del módulo", "", function(value)
    module_config.name = value
    update_info()

    -- Paso 2: Display name
    local input2 = create_input(
      "Nombre para mostrar",
      value:gsub("_", " "):gsub("^%l", string.upper),
      function(value2)
        module_config.display_name = value2
        update_info()

        -- Continuar con vim.ui.select para selecciones
        vim.ui.select({
          "Accounting",
          "Sales",
          "Purchase",
          "Customizations",
          "Uncategorized",
        }, {
          prompt = "Categoría:",
        }, function(category)
          module_config.category = category or "Uncategorized"
          module_config.author = cfg.scaffolding.default_author
          module_config.license = cfg.scaffolding.default_license

          local root, _ = util.get_odoo_root()
          module_config.version = root and util.get_odoo_version(root) or cfg.version.default

          update_info()

          vim.ui.select({ "Sí", "No" }, {
            prompt = "¿Crear modelo inicial?",
          }, function(create_model)
            module_config.create_model = (create_model == "Sí")
            module_config.create_views = module_config.create_model
            module_config.create_security = true

            if module_config.create_model then
              local input3 = create_input("Nombre del modelo", "x_" .. module_config.name, function(model_name)
                module_config.model_name = model_name
                module_config.summary = module_config.display_name
                update_info()

                info_popup:unmount()
                callback(module_config)
              end)
            else
              module_config.summary = module_config.display_name
              update_info()

              info_popup:unmount()
              callback(module_config)
            end
          end)
        end)
      end
    )
  end)
end

---Comando para crear un nuevo módulo
---@param opts table
function M.new_module_command(opts)
  -- Detectar si estamos en un proyecto Odoo
  local root, project_type = util.get_odoo_root()
  local base_path

  if root then
    -- Determinar dónde crear el módulo según el tipo de proyecto
    if project_type == "doodba" then
      -- En Doodba, crear en odoo/custom/src/private/
      base_path = root .. "/odoo/custom/src/private"
      if not util.exists(base_path) then
        base_path = root .. "/odoo/custom/src"
      end
    else
      -- En proyectos estándar, crear en addons/ o en la raíz
      local addons_path = root .. "/addons"
      if util.exists(addons_path) then
        base_path = addons_path
      else
        base_path = root
      end
    end
  else
    -- Si no es proyecto Odoo, usar directorio actual
    base_path = vim.fn.getcwd()
  end

  -- Lanzar wizard
  local wizard_fn = has_nui() and wizard_nui or wizard_simple

  wizard_fn(function(module_config)
    local success, module_path = M.generate_module_structure(base_path, module_config)

    if success then
      -- Preguntar si abrir el módulo
      vim.ui.select({ "Sí", "No" }, {
        prompt = "¿Abrir el módulo creado?",
      }, function(choice)
        if choice == "Sí" then
          vim.cmd("edit " .. module_path .. "/__manifest__.py")
        end
      end)
    end
  end)
end

---Registra los comandos del módulo
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooNewModule", function(opts)
    M.new_module_command(opts)
  end, {
    desc = "Crear nuevo módulo de Odoo con wizard interactivo",
  })

  -- Comandos adicionales que se implementarán más adelante
  vim.api.nvim_create_user_command("OdooNewModel", function(opts)
    util.info("Comando OdooNewModel - Por implementar en Sprint 2")
  end, {
    desc = "Crear nuevo modelo de Odoo",
  })

  vim.api.nvim_create_user_command("OdooAddField", function(opts)
    util.info("Comando OdooAddField - Por implementar en Sprint 2")
  end, {
    desc = "Agregar campo a modelo actual",
  })

  vim.api.nvim_create_user_command("OdooGenerateViews", function(opts)
    util.info("Comando OdooGenerateViews - Por implementar en Sprint 2")
  end, {
    desc = "Generar vistas para modelo actual",
  })
end

return M
