---@class odoo.navigation
---Módulo para navegación inteligente entre archivos XML y Python de Odoo
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")

---@class odoo.navigation.Context
---@field type "model"|"field"|"ref"|"inherit"|"unknown"
---@field value string
---@field model? string
---@field parent_model? string

---Obtiene el contexto del cursor en un archivo XML
---@return odoo.navigation.Context|nil
function M.get_xml_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  -- Verificar que tenemos el parser de XML
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "xml")
  if not ok or not parser then
    util.debug("Parser XML no disponible, usando fallback regex")
    return M._get_context_regex()
  end

  local tree = parser:parse()[1]
  if not tree then
    return M._get_context_regex()
  end

  local root = tree:root()

  -- Query para encontrar atributos en XML
  local query_str = [[
    (attribute
      (attribute_name) @attr_name
      (attribute_value) @attr_value)
  ]]

  local query = vim.treesitter.query.parse("xml", query_str)

  ---@type odoo.navigation.Context|nil
  local context = nil
  local closest_node = nil
  local min_distance = math.huge

  for id, node in query:iter_captures(root, bufnr, row, row + 1) do
    local name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()

    -- Verificar si el cursor está en este nodo o cerca
    if start_row == row then
      local distance = math.abs(col - start_col)
      if distance < min_distance then
        min_distance = distance
        closest_node = node
      end
    end
  end

  -- Analizar el contexto basado en el nodo más cercano
  if closest_node then
    context = M._analyze_node(closest_node, bufnr)
  end

  return context or M._get_context_regex()
end

---Analiza un nodo de Treesitter para extraer contexto
---@param node TSNode
---@param bufnr number
---@return odoo.navigation.Context|nil
function M._analyze_node(node, bufnr)
  local parent = node:parent()
  if not parent or parent:type() ~= "attribute" then
    parent = node
  end

  -- Obtener nombre y valor del atributo
  local attr_name_node = parent:named_child(0)
  local attr_value_node = parent:named_child(1)

  if not attr_name_node or not attr_value_node then
    return nil
  end

  local attr_name = vim.treesitter.get_node_text(attr_name_node, bufnr)
  local attr_value = vim.treesitter.get_node_text(attr_value_node, bufnr)

  -- Limpiar comillas del valor
  attr_value = attr_value:gsub('^["\']', ""):gsub('["\']$', "")

  ---@type odoo.navigation.Context
  local context = {
    type = "unknown",
    value = attr_value,
  }

  -- Determinar tipo de contexto
  if attr_name == "model" then
    context.type = "model"
  elseif attr_name == "ref" then
    context.type = "ref"
  elseif attr_name == "inherit_id" then
    context.type = "ref"
  elseif attr_name == "name" then
    -- Determinar si es un field buscando el elemento padre
    local element = M._find_parent_element(parent)
    if element then
      local element_name = M._get_element_name(element, bufnr)
      if element_name == "field" then
        context.type = "field"
        -- Buscar el modelo del record padre
        context.parent_model = M._find_parent_model(element, bufnr)
      end
    end
  end

  return context
end

---Encuentra el elemento XML padre
---@param node TSNode
---@return TSNode|nil
function M._find_parent_element(node)
  local current = node:parent()
  while current do
    if current:type() == "element" or current:type() == "STag" then
      return current
    end
    current = current:parent()
  end
  return nil
end

---Obtiene el nombre de un elemento XML
---@param element TSNode
---@param bufnr number
---@return string|nil
function M._get_element_name(element, bufnr)
  for child in element:iter_children() do
    if child:type() == "STag" or child:type() == "start_tag" then
      for c in child:iter_children() do
        if c:type() == "Name" or c:type() == "tag_name" then
          return vim.treesitter.get_node_text(c, bufnr)
        end
      end
    end
    if child:type() == "Name" or child:type() == "tag_name" then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

---Busca el modelo en el elemento record padre
---@param node TSNode
---@param bufnr number
---@return string|nil
function M._find_parent_model(node, bufnr)
  local current = node:parent()
  while current do
    if current:type() == "element" then
      -- Buscar atributo model="..."
      local text = vim.treesitter.get_node_text(current, bufnr)
      local model = text:match('model%s*=%s*["\']([^"\']+)["\']')
      if model then
        return model
      end
    end
    current = current:parent()
  end
  return nil
end

---Fallback: obtener contexto usando regex
---@return odoo.navigation.Context|nil
function M._get_context_regex()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Buscar el atributo más cercano al cursor
  ---@type odoo.navigation.Context|nil
  local context = nil

  -- Pattern para model="..."
  for attr_name, attr_value in line:gmatch('(%w+)%s*=%s*["\']([^"\']+)["\']') do
    local start_pos, end_pos = line:find(attr_value, 1, true)
    if start_pos and col >= start_pos - 1 and col <= end_pos then
      context = { type = "unknown", value = attr_value }

      if attr_name == "model" then
        context.type = "model"
      elseif attr_name == "ref" or attr_name == "inherit_id" then
        context.type = "ref"
      elseif attr_name == "name" and line:match("<field") then
        context.type = "field"
        -- Buscar modelo en líneas anteriores
        context.parent_model = M._find_model_in_buffer()
      end
      break
    end
  end

  return context
end

---Busca el modelo en el buffer actual (hacia arriba)
---@return string|nil
function M._find_model_in_buffer()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, cursor_row, false)

  for i = #lines, 1, -1 do
    local model = lines[i]:match('model%s*=%s*["\']([^"\']+)["\']')
    if model then
      return model
    end
  end
  return nil
end

---Navega a la definición basada en el contexto
---@param ctx odoo.navigation.Context
function M.goto_from_context(ctx)
  if ctx.type == "model" then
    M.goto_model(ctx.value)
  elseif ctx.type == "field" then
    M.goto_field(ctx.value, ctx.parent_model)
  elseif ctx.type == "ref" then
    M.goto_xml_id(ctx.value)
  else
    util.warn("No se pudo determinar el tipo de navegación")
  end
end

---Navega a la definición de un modelo de Odoo
---@param model_name string Nombre técnico del modelo (ej: "res.partner")
function M.goto_model(model_name)
  local cfg = config.get()
  local pattern = "_name%s*=%s*['\"]" .. vim.pesc(model_name) .. "['\"]"

  if cfg.navigation.use_telescope then
    M._telescope_search(pattern, {
      prompt_title = "Modelo: " .. model_name,
      search_dirs = M._get_search_dirs(),
    })
  else
    M._grep_search(pattern)
  end
end

---Navega a todas las definiciones de un modelo (incluyendo herencias)
---Busca tanto _name como _inherit para el modelo especificado
---@param model_name string Nombre técnico del modelo
function M.find_model_definitions(model_name)
  local cfg = config.get()
  
  -- Buscar tanto _name como _inherit
  local name_pattern = "_name%s*=%s*['\"]" .. vim.pesc(model_name) .. "['\"]"
  local inherit_pattern = "_inherit%s*=.*['\"]" .. vim.pesc(model_name) .. "['\"]"
  
  -- Combinar ambos patrones con OR
  local combined_pattern = "(" .. name_pattern .. "|" .. inherit_pattern .. ")"
  
  if cfg.navigation.use_telescope then
    M._telescope_search(combined_pattern, {
      prompt_title = "Definiciones de: " .. model_name,
      search_dirs = M._get_search_dirs(),
    })
  else
    M._grep_search(combined_pattern)
  end
end

---Navega al modelo bajo el cursor (para archivos Python)
---Extrae el nombre del modelo de la posición del cursor
function M.goto_model_under_cursor()
  local model_name = util.extract_model_name_at_cursor()
  
  if not model_name then
    util.warn("No se detectó un nombre de modelo bajo el cursor")
    util.info("Coloca el cursor sobre un string como 'mail.thread' o 'account.account'")
    return
  end
  
  -- Usar la función que busca tanto _name como _inherit
  M.find_model_definitions(model_name)
end

---Navega a la definición de un campo
---@param field_name string
---@param model_name? string
function M.goto_field(field_name, model_name)
  local cfg = config.get()

  -- Buscar definición del campo: field_name = fields.XXX(
  local pattern = field_name .. "%s*=%s*fields%."

  if cfg.navigation.use_telescope then
    M._telescope_search(pattern, {
      prompt_title = "Campo: " .. field_name .. (model_name and (" en " .. model_name) or ""),
      search_dirs = M._get_search_dirs(),
    })
  else
    M._grep_search(pattern)
  end
end

---Navega a un XML ID
---@param xml_id string
function M.goto_xml_id(xml_id)
  local cfg = config.get()

  -- El xml_id puede ser "module.id" o solo "id"
  local pattern
  if xml_id:match("%.") then
    local _, id = xml_id:match("([^.]+)%.(.+)")
    pattern = 'id%s*=%s*["\']' .. vim.pesc(id or xml_id) .. '["\']'
  else
    pattern = 'id%s*=%s*["\']' .. vim.pesc(xml_id) .. '["\']'
  end

  if cfg.navigation.use_telescope then
    M._telescope_search(pattern, {
      prompt_title = "XML ID: " .. xml_id,
      search_dirs = M._get_search_dirs(),
      type_filter = "xml",
    })
  else
    M._grep_search(pattern, "xml")
  end
end

---Obtiene los directorios donde buscar
---@return string[]
function M._get_search_dirs()
  local root = util.get_odoo_root()
  if root then
    return { root }
  end
  return { vim.fn.getcwd() }
end

---Búsqueda usando Telescope
---@param pattern string
---@param opts? table
function M._telescope_search(pattern, opts)
  opts = opts or {}

  local ok, telescope = pcall(require, "telescope.builtin")
  if not ok then
    util.warn("Telescope no está disponible, usando grep...")
    M._grep_search(pattern)
    return
  end

  local grep_opts = {
    prompt_title = opts.prompt_title or "Odoo Search",
    search = pattern,
    use_regex = true,
    search_dirs = opts.search_dirs,
  }

  -- Filtrar por tipo de archivo si se especifica
  if opts.type_filter then
    grep_opts.type_filter = opts.type_filter
  end

  telescope.grep_string(grep_opts)
end

---Búsqueda usando grep nativo
---@param pattern string
---@param file_type? string
function M._grep_search(pattern, file_type)
  local search_dirs = M._get_search_dirs()
  local cmd = { "grep", "-rn", "-E", pattern }

  if file_type then
    table.insert(cmd, "--include=*." .. file_type)
  else
    table.insert(cmd, "--include=*.py")
    table.insert(cmd, "--include=*.xml")
  end

  for _, dir in ipairs(search_dirs) do
    table.insert(cmd, dir)
  end

  local result = vim.system(cmd, { text = true }):wait()

  if result.code == 0 and result.stdout and result.stdout ~= "" then
    local lines = vim.split(result.stdout, "\n")
    if #lines > 0 then
      -- Parsear primera coincidencia: archivo:linea:contenido
      local file, line = lines[1]:match("([^:]+):(%d+):")
      if file and line then
        vim.cmd("edit " .. file)
        vim.cmd(":" .. line)
        util.info("Encontrado en: " .. file .. ":" .. line)
        return
      end
    end
  end

  util.warn("No se encontró: " .. pattern)
end

---Función principal de goto_definition para XML
function M.goto_definition()
  local ft = vim.bo.filetype

  if ft ~= "xml" then
    -- Delegar al LSP para archivos Python
    vim.lsp.buf.definition()
    return
  end

  local ctx = M.get_xml_context()
  if ctx and ctx.type ~= "unknown" then
    M.goto_from_context(ctx)
  else
    util.warn("No se detectó un elemento navegable bajo el cursor")
    util.info("Elementos soportados: model=\"...\", name=\"...\" (en fields), ref=\"...\"")
  end
end

---Configura los keymaps de navegación
function M.setup_keymaps()
  local cfg = config.get()

  if not cfg.navigation.xml_goto_definition then
    return
  end

  -- Autocomando para archivos XML de Odoo
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "xml",
    callback = function(args)
      local bufnr = args.buf

      -- Solo aplicar en proyectos Odoo
      if not util.is_odoo_project() then
        return
      end

      vim.keymap.set("n", cfg.navigation.keymaps.goto_definition, function()
        M.goto_definition()
      end, {
        buffer = bufnr,
        desc = "Odoo: Ir a definición (XML)",
      })

      vim.keymap.set("n", cfg.navigation.keymaps.goto_model, function()
        local model = M._find_model_in_buffer()
        if model then
          M.goto_model(model)
        else
          util.warn("No se encontró modelo en el contexto")
        end
      end, {
        buffer = bufnr,
        desc = "Odoo: Ir al modelo",
      })

      vim.keymap.set("n", cfg.navigation.keymaps.goto_xml_id, function()
        local ctx = M.get_xml_context()
        if ctx and ctx.type == "ref" then
          M.goto_xml_id(ctx.value)
        else
          -- Pedir al usuario
          vim.ui.input({ prompt = "XML ID: " }, function(input)
            if input and input ~= "" then
              M.goto_xml_id(input)
            end
          end)
        end
      end, {
        buffer = bufnr,
        desc = "Odoo: Ir a XML ID",
      })

      -- Keymaps adicionales para find references y herencia
      vim.keymap.set("n", "gr", function()
        M.find_references()
      end, {
        buffer = bufnr,
        desc = "Odoo: Buscar referencias",
      })

      vim.keymap.set("n", "gi", function()
        M.show_inheritance()
      end, {
        buffer = bufnr,
        desc = "Odoo: Mostrar herencia",
      })
    end,
  })

  -- También configurar keymaps para archivos Python en proyectos Odoo
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "python",
    callback = function(args)
      local bufnr = args.buf

      -- Solo aplicar en proyectos Odoo
      if not util.is_odoo_project() then
        return
      end

      -- gm: Ir a modelo bajo cursor
      vim.keymap.set("n", cfg.navigation.keymaps.goto_model, function()
        M.goto_model_under_cursor()
      end, {
        buffer = bufnr,
        desc = "Odoo: Ir a definiciones de modelo",
      })

      vim.keymap.set("n", "gr", function()
        M.find_references()
      end, {
        buffer = bufnr,
        desc = "Odoo: Buscar referencias",
      })

      vim.keymap.set("n", "gi", function()
        M.show_inheritance()
      end, {
        buffer = bufnr,
        desc = "Odoo: Mostrar herencia",
      })
    end,
  })
end

---Busca todas las referencias a un símbolo
---@param symbol? string Símbolo a buscar (si no se especifica, usa cursor actual)
function M.find_references(symbol)
  -- Si no se especifica símbolo, detectar desde el contexto
  if not symbol then
    local ft = vim.bo.filetype

    if ft == "xml" then
      local ctx = M.get_xml_context()
      if ctx and ctx.value then
        symbol = ctx.value
      end
    elseif ft == "python" then
      -- En Python, obtener palabra bajo cursor
      symbol = vim.fn.expand("<cword>")
    else
      util.warn("Tipo de archivo no soportado para find references")
      return
    end
  end

  if not symbol or symbol == "" then
    util.warn("No se pudo detectar símbolo para buscar referencias")
    return
  end

  local cfg = config.get()

  -- Buscar referencias del símbolo (en Python y XML)
  local pattern = vim.pesc(symbol)

  if cfg.navigation.use_telescope then
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      util.warn("Telescope no disponible")
      return
    end

    telescope.grep_string({
      prompt_title = "Referencias de: " .. symbol,
      search = pattern,
      use_regex = true,
      search_dirs = M._get_search_dirs(),
    })
  else
    M._grep_search(pattern)
  end
end

---Muestra el árbol de herencia de un modelo
---@param model_name? string Nombre del modelo (si no se especifica, usa cursor)
function M.show_inheritance(model_name)
  -- Detectar modelo desde contexto si no se especifica
  if not model_name then
    local ft = vim.bo.filetype

    if ft == "xml" then
      local ctx = M.get_xml_context()
      if ctx and ctx.type == "model" then
        model_name = ctx.value
      else
        model_name = M._find_model_in_buffer()
      end
    elseif ft == "python" then
      -- Buscar _name en el archivo actual
      local bufnr = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      for _, line in ipairs(lines) do
        local name = line:match("_name%s*=%s*['\"]([^'\"]+)['\"]")
        if name then
          model_name = name
          break
        end
      end
    end
  end

  if not model_name or model_name == "" then
    util.warn("No se pudo detectar modelo para mostrar herencia")
    return
  end

  util.info("Buscando herencia para modelo: " .. model_name)

  -- Buscar modelos que heredan de este
  local inherit_pattern = "_inherit%s*=%s*['\"]" .. vim.pesc(model_name) .. "['\"]"

  local cfg = config.get()
  if cfg.navigation.use_telescope then
    local ok, telescope = pcall(require, "telescope.builtin")
    if ok then
      telescope.grep_string({
        prompt_title = "Herencia de: " .. model_name,
        search = inherit_pattern,
        use_regex = true,
        search_dirs = M._get_search_dirs(),
      })
    end
  else
    M._grep_search(inherit_pattern)
  end
end

---Muestra la cadena de herencia de vistas
---@param view_id? string XML ID de la vista
function M.view_inheritance(view_id)
  -- Detectar view_id desde contexto si no se especifica
  if not view_id then
    local ft = vim.bo.filetype
    if ft == "xml" then
      local ctx = M.get_xml_context()
      if ctx and ctx.type == "ref" then
        view_id = ctx.value
      end
    end
  end

  if not view_id or view_id == "" then
    -- Pedir al usuario
    vim.ui.input({ prompt = "XML ID de vista: " }, function(input)
      if input and input ~= "" then
        M.view_inheritance(input)
      end
    end)
    return
  end

  util.info("Buscando vistas que heredan de: " .. view_id)

  -- Buscar vistas que heredan de este XML ID
  local inherit_pattern = "inherit_id.*" .. vim.pesc(view_id)

  local cfg = config.get()
  if cfg.navigation.use_telescope then
    local ok, telescope = pcall(require, "telescope.builtin")
    if ok then
      telescope.grep_string({
        prompt_title = "Herencia de vista: " .. view_id,
        search = inherit_pattern,
        use_regex = true,
        search_dirs = M._get_search_dirs(),
        type_filter = "xml",
      })
    end
  else
    M._grep_search(inherit_pattern, "xml")
  end
end

---Registra los comandos del módulo
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooGotoModel", function(opts)
    M.goto_model(opts.args)
  end, {
    nargs = 1,
    desc = "Navega a la definición de un modelo Odoo",
    complete = function()
      -- Podría implementarse autocompletado de modelos
      return {}
    end,
  })

  vim.api.nvim_create_user_command("OdooGotoXmlId", function(opts)
    M.goto_xml_id(opts.args)
  end, {
    nargs = 1,
    desc = "Navega a un XML ID",
  })

  vim.api.nvim_create_user_command("OdooGotoField", function(opts)
    M.goto_field(opts.args)
  end, {
    nargs = 1,
    desc = "Navega a la definición de un campo",
  })

  -- Nuevos comandos para find references y herencia
  vim.api.nvim_create_user_command("OdooFindReferences", function(opts)
    M.find_references(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    desc = "Buscar todas las referencias a un símbolo",
  })

  vim.api.nvim_create_user_command("OdooShowInheritance", function(opts)
    M.show_inheritance(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    desc = "Mostrar árbol de herencia de modelo",
  })

  vim.api.nvim_create_user_command("OdooViewInheritance", function(opts)
    M.view_inheritance(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    desc = "Mostrar cadena de herencia de vistas",
  })
end

return M
