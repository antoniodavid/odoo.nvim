---@class odoo.templates
---Módulo para gestionar templates/snippets de código Odoo
---Soporta templates multi-versión con sustitución de variables
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")

---Obtiene el año actual
---@return string
local function get_current_year()
  return os.date("%Y")
end

---Obtiene el autor desde config o usa default
---@return string
local function get_author()
  local cfg = config.get()
  return cfg.scaffolding.default_author or "Your Company"
end

---Obtiene la licencia desde config o usa default
---@return string
local function get_license()
  local cfg = config.get()
  return cfg.scaffolding.default_license or "LGPL-3"
end

---Sustituye variables en un template
---@param template string
---@param vars table<string, string>
---@return string
local function substitute_vars(template, vars)
  local result = template
  for key, value in pairs(vars) do
    result = result:gsub("%${" .. key .. "}", value)
  end
  return result
end

---Templates para modelos Odoo
M.TEMPLATES = {
  ---Template de modelo básico
  model = [[# -*- coding: utf-8 -*-
from odoo import models, fields, api


class ${ModelClass}(models.Model):
    _name = '${model_name}'
    _description = '${description}'

    name = fields.Char(string='Name', required=True)
    active = fields.Boolean(string='Active', default=True)
    description = fields.Text(string='Description')
]],

  ---Template de campo Many2one
  many2one = [[${field_name} = fields.Many2one(
    comodel_name='${comodel_name}',
    string='${string}',
    ${required}
)]],

  ---Template de campo One2many
  one2many = [[${field_name} = fields.One2many(
    comodel_name='${comodel_name}',
    inverse_name='${inverse_name}',
    string='${string}',
)]],

  ---Template de campo Many2many
  many2many = [[${field_name} = fields.Many2many(
    comodel_name='${comodel_name}',
    relation='${relation}',
    column1='${column1}',
    column2='${column2}',
    string='${string}',
)]],

  ---Template de campo computado
  computed = [[${field_name} = fields.${field_type}(
    string='${string}',
    compute='_compute_${field_name}',
    store=True,
)

@api.depends('${depends}')
def _compute_${field_name}(self):
    for record in self:
        record.${field_name} = ${computation}
]],

  ---Template de vista form
  form = [[<?xml version="1.0" encoding="UTF-8"?>
<odoo>
    <record id="view_${model_underscore}_form" model="ir.ui.view">
        <field name="name">${model_name}.form</field>
        <field name="model">${model_name}</field>
        <field name="arch" type="xml">
            <form string="${description}">
                <sheet>
                    <group>
                        <field name="name"/>
                        <field name="active"/>
                    </group>
                    <group>
                        <field name="description"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>
</odoo>
]],

  ---Template de vista tree
  tree = [[<?xml version="1.0" encoding="UTF-8"?>
<odoo>
    <record id="view_${model_underscore}_tree" model="ir.ui.view">
        <field name="name">${model_name}.tree</field>
        <field name="model">${model_name}</field>
        <field name="arch" type="xml">
            <tree string="${description}">
                <field name="name"/>
                <field name="active"/>
            </tree>
        </field>
    </record>
</odoo>
]],

  ---Template de vista search
  search = [[<?xml version="1.0" encoding="UTF-8"?>
<odoo>
    <record id="view_${model_underscore}_search" model="ir.ui.view">
        <field name="name">${model_name}.search</field>
        <field name="model">${model_name}</field>
        <field name="arch" type="xml">
            <search string="${description}">
                <field name="name"/>
                <filter name="active" string="Active" domain="[('active', '=', True)]"/>
                <filter name="inactive" string="Inactive" domain="[('active', '=', False)]"/>
            </search>
        </field>
    </record>
</odoo>
]],

  ---Template de wizard (TransientModel)
  wizard = [[# -*- coding: utf-8 -*-
from odoo import models, fields, api
from odoo.exceptions import UserError


class ${ModelClass}(models.TransientModel):
    _name = '${model_name}'
    _description = '${description}'

    ${field_name} = fields.Char(string='${field_string}', required=True)

    def action_confirm(self):
        """Ejecutar la acción del wizard"""
        self.ensure_one()
        # TODO: Implementar lógica del wizard
        return {'type': 'ir.actions.act_window_close'}
]],

  ---Template de controller
  controller = [[# -*- coding: utf-8 -*-
from odoo import http
from odoo.http import request


class ${ControllerClass}(http.Controller):

    @http.route('/${route_path}', type='http', auth='user', website=True)
    def ${method_name}(self, **kwargs):
        """${description}"""
        return request.render('${module}.${template_name}', {
            # TODO: Add context variables
        })
]],

  ---Template de __manifest__.py
  manifest = [[# -*- coding: utf-8 -*-
{
    'name': '${display_name}',
    'version': '${version}',
    'category': '${category}',
    'summary': '${summary}',
    'description': """
${description}
    """,
    'author': '${author}',
    'website': '${website}',
    'license': '${license}',
    'depends': ['base'],
    'data': [
        'security/ir.model.access.csv',
        'views/views.xml',
    ],
    'demo': [],
    'installable': True,
    'application': ${application},
    'auto_install': False,
}
]],

  ---Template de ir.model.access.csv
  security = [[id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_${model_underscore}_user,access.${model_name}.user,model_${model_underscore},base.group_user,1,1,1,1
]],

  ---Template de __init__.py para módulo
  module_init = [[# -*- coding: utf-8 -*-
from . import models
]],

  ---Template de __init__.py para directorio models
  models_init = [[# -*- coding: utf-8 -*-
from . import ${model_file}
]],
}

---Genera un template con las variables proporcionadas
---@param template_type string Tipo de template ('model', 'field', 'view', etc.)
---@param vars? table<string, string> Variables para sustituir
---@return string|nil
function M.generate(template_type, vars)
  local template = M.TEMPLATES[template_type]
  if not template then
    util.error("Template '" .. template_type .. "' no encontrado")
    return nil
  end

  vars = vars or {}

  -- Agregar variables comunes
  vars.year = vars.year or get_current_year()
  vars.author = vars.author or get_author()
  vars.license = vars.license or get_license()

  return substitute_vars(template, vars)
end

---Inserta un template en el buffer actual
---@param template_type string
---@param vars? table<string, string>
function M.insert_template(template_type, vars)
  local content = M.generate(template_type, vars)
  if not content then
    return
  end

  -- Obtener posición del cursor
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  -- Dividir content en líneas
  local lines = vim.split(content, "\n", { plain = true })

  -- Insertar líneas en el buffer
  vim.api.nvim_buf_set_lines(0, row, row, false, lines)

  util.info("Template '" .. template_type .. "' insertado")
end

---Crea variables interactivamente para un modelo
---@param callback function
local function prompt_model_vars(callback)
  local vars = {}

  -- Prompt para nombre del modelo
  vim.ui.input({
    prompt = "Nombre del modelo (ej. res.partner): ",
  }, function(model_name)
    if not model_name then
      return
    end

    vars.model_name = model_name

    -- Generar ModelClass desde model_name
    -- res.partner → ResPartner
    local class_parts = {}
    for part in model_name:gmatch("[^.]+") do
      table.insert(class_parts, part:sub(1, 1):upper() .. part:sub(2))
    end
    vars.ModelClass = table.concat(class_parts, "")

    -- Generar model_underscore para templates
    vars.model_underscore = model_name:gsub("%.", "_")

    -- Prompt para descripción
    vim.ui.input({
      prompt = "Descripción: ",
      default = vars.ModelClass,
    }, function(description)
      if not description then
        description = vars.ModelClass
      end

      vars.description = description
      callback(vars)
    end)
  end)
end

---Crea variables interactivamente para un campo
---@param callback function
local function prompt_field_vars(callback)
  local vars = {}

  vim.ui.input({
    prompt = "Nombre del campo: ",
  }, function(field_name)
    if not field_name then
      return
    end

    vars.field_name = field_name

    vim.ui.input({
      prompt = "Tipo de campo (Char, Integer, Many2one, etc.): ",
      default = "Char",
    }, function(field_type)
      vars.field_type = field_type or "Char"

      vim.ui.input({
        prompt = "String (label): ",
        default = field_name:sub(1, 1):upper() .. field_name:sub(2),
      }, function(string_val)
        vars.string = string_val or field_name
        callback(vars)
      end)
    end)
  end)
end

---Comando principal para generar templates
---@param opts table
function M.template_command(opts)
  local template_type = opts.args

  if template_type == "" or template_type == nil then
    -- Mostrar menu de selección
    vim.ui.select({
      "model",
      "many2one",
      "one2many",
      "many2many",
      "computed",
      "form",
      "tree",
      "search",
      "wizard",
      "controller",
    }, {
      prompt = "Selecciona un template:",
    }, function(choice)
      if choice then
        M.template_command({ args = choice })
      end
    end)
    return
  end

  -- Para templates de modelo, pedir variables interactivamente
  if template_type == "model" or template_type == "wizard" then
    prompt_model_vars(function(vars)
      M.insert_template(template_type, vars)
    end)
  elseif template_type == "form" or template_type == "tree" or template_type == "search" then
    prompt_model_vars(function(vars)
      M.insert_template(template_type, vars)
    end)
  elseif template_type:find("many") or template_type == "computed" then
    prompt_field_vars(function(vars)
      -- Para campos relacionales, pedir comodel_name
      if template_type == "many2one" then
        vim.ui.input({
          prompt = "Comodel name (ej. res.partner): ",
        }, function(comodel)
          vars.comodel_name = comodel or "res.partner"
          vars.required = "required=True,"
          M.insert_template(template_type, vars)
        end)
      elseif template_type == "one2many" then
        vim.ui.input({
          prompt = "Comodel name: ",
        }, function(comodel)
          vars.comodel_name = comodel or ""
          vim.ui.input({
            prompt = "Inverse name: ",
          }, function(inverse)
            vars.inverse_name = inverse or ""
            M.insert_template(template_type, vars)
          end)
        end)
      elseif template_type == "many2many" then
        vim.ui.input({
          prompt = "Comodel name: ",
        }, function(comodel)
          vars.comodel_name = comodel or ""
          vars.relation = vars.field_name .. "_" .. comodel:gsub("%.", "_") .. "_rel"
          vars.column1 = "id"
          vars.column2 = comodel:gsub("%.", "_") .. "_id"
          M.insert_template(template_type, vars)
        end)
      elseif template_type == "computed" then
        vim.ui.input({
          prompt = "Depends (ej. partner_id.name): ",
        }, function(depends)
          vars.depends = depends or ""
          vars.computation = "# TODO: Implement computation"
          M.insert_template(template_type, vars)
        end)
      end
    end)
  else
    M.insert_template(template_type)
  end
end

---Registra los comandos del módulo
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooTemplate", function(opts)
    M.template_command(opts)
  end, {
    nargs = "?",
    desc = "Insertar template de Odoo en buffer actual",
    complete = function()
      return vim.tbl_keys(M.TEMPLATES)
    end,
  })
end

---Integración con LuaSnip (opcional)
---@return boolean
function M.setup_luasnip()
  local has_luasnip, luasnip = pcall(require, "luasnip")
  if not has_luasnip then
    util.debug("LuaSnip no disponible, templates funcionarán sin expansión automática")
    return false
  end

  local s = luasnip.snippet
  local t = luasnip.text_node
  local i = luasnip.insert_node
  local f = luasnip.function_node

  -- Snippets para Python
  luasnip.add_snippets("python", {
    s("odmodel", {
      t({ "class " }),
      i(1, "ModelName"),
      t({ "(models.Model):", "" }),
      t({ "    _name = '" }),
      i(2, "module.model"),
      t({ "'", "" }),
      t({ "    _description = '" }),
      i(3, "Description"),
      t({ "'", "", "" }),
      t({ "    name = fields.Char(string='Name', required=True)", "" }),
      t({ "    active = fields.Boolean(string='Active', default=True)", "" }),
    }),

    s("odmany2one", {
      i(1, "field_name"),
      t({ " = fields.Many2one('" }),
      i(2, "comodel.name"),
      t({ "', string='" }),
      i(3, "Label"),
      t({ "')" }),
    }),
  })

  -- Snippets para XML
  luasnip.add_snippets("xml", {
    s("odform", {
      t({ '<record id="view_' }),
      i(1, "model"),
      t({ '_form" model="ir.ui.view">', "" }),
      t({ '    <field name="name">' }),
      f(function(args)
        return args[1][1] .. ".form"
      end, { 1 }),
      t({ '</field>', "" }),
      t({ '    <field name="model">' }),
      i(2, "module.model"),
      t({ '</field>', "" }),
      t({ '    <field name="arch" type="xml">', "" }),
      t({ "        <form>", "" }),
      t({ "            ", "" }),
      t({ "        </form>", "" }),
      t({ "    </field>", "" }),
      t({ "</record>", "" }),
    }),
  })

  util.debug("LuaSnip snippets configurados para Odoo")
  return true
end

return M
