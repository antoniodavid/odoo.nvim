---@class odoo.docker
---Módulo para interactuar con Docker en proyectos Doodba
local M = {}

local util = require("odoo.util")
local config = require("odoo.config")

---@class odoo.docker.ContainerInfo
---@field id string
---@field name string
---@field status string
---@field image string

---@type {job?: vim.SystemObj, terminal_bufnr?: number}
local state = {}

---Obtiene el comando de docker-compose disponible
---@return string[]
function M.get_compose_cmd()
  local compose = util.get_compose_cmd()
  if not compose then
    return {}
  end

  if compose == "docker compose" then
    return { "docker", "compose" }
  else
    return { "docker-compose" }
  end
end

---Obtiene el nombre del servicio de Odoo
---@param root string
---@return string
function M.get_service_name(root)
  local cfg = config.get()

  if cfg.doodba.auto_detect_service then
    return util.get_docker_service(root)
  end

  return cfg.doodba.docker_service
end

---Verifica si los contenedores están corriendo
---@param root string
---@return boolean
function M.is_running(root)
  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    return false
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "ps", "-q" })

  local result = vim.system(cmd, {
    cwd = root,
    text = true,
  }):wait()

  return result.code == 0 and result.stdout and result.stdout ~= ""
end

---Inicia los contenedores
---@param opts? {detach?: boolean, build?: boolean, callback?: fun(success: boolean)}
function M.up(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "up" })

  if opts.detach ~= false then
    table.insert(cmd, "-d")
  end

  if opts.build then
    table.insert(cmd, "--build")
  end

  util.info("🐳 Iniciando contenedores...")

  state.job = util.async_cmd(cmd, {
    cwd = root,
    on_exit = function(code)
      state.job = nil
      if code == 0 then
        util.info("✓ Contenedores iniciados correctamente")
        if opts.callback then
          opts.callback(true)
        end
      else
        util.error("✗ Error al iniciar contenedores (código: " .. code .. ")")
        if opts.callback then
          opts.callback(false)
        end
      end
    end,
  })
end

---Detiene los contenedores
---@param opts? {callback?: fun(success: boolean)}
function M.down(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "down" })

  util.info("🐳 Deteniendo contenedores...")

  state.job = util.async_cmd(cmd, {
    cwd = root,
    on_exit = function(code)
      state.job = nil
      if code == 0 then
        util.info("✓ Contenedores detenidos")
        if opts.callback then
          opts.callback(true)
        end
      else
        util.error("✗ Error al detener contenedores")
        if opts.callback then
          opts.callback(false)
        end
      end
    end,
  })
end

---Reinicia los contenedores
---@param opts? {service?: string, callback?: fun(success: boolean)}
function M.restart(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "restart" })

  if opts.service then
    table.insert(cmd, opts.service)
  else
    table.insert(cmd, M.get_service_name(root))
  end

  util.info("🐳 Reiniciando servicio...")

  state.job = util.async_cmd(cmd, {
    cwd = root,
    on_exit = function(code)
      state.job = nil
      if code == 0 then
        util.info("✓ Servicio reiniciado")
        if opts.callback then
          opts.callback(true)
        end
      else
        util.error("✗ Error al reiniciar servicio")
        if opts.callback then
          opts.callback(false)
        end
      end
    end,
  })
end

---Abre un shell en el contenedor de Odoo
---@param opts? {service?: string, cmd?: string}
function M.shell(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  if not M.is_running(root) then
    util.error("Los contenedores no están corriendo. Ejecuta :OdooDockerUp primero")
    return
  end

  local cfg = config.get()
  local service = opts.service or M.get_service_name(root)
  local shell_cmd = opts.cmd or cfg.doodba.shell_command

  local compose_cmd = M.get_compose_cmd()
  local cmd_str = table.concat(compose_cmd, " ") .. " exec " .. service .. " " .. shell_cmd

  -- Abrir terminal con el comando
  vim.cmd("vsplit | terminal cd " .. vim.fn.shellescape(root) .. " && " .. cmd_str)

  -- Entrar en modo insert automáticamente
  vim.cmd("startinsert")

  util.info("🐳 Shell abierto en " .. service)
end

---Ejecuta odoo-bin shell en el contenedor
function M.odoo_shell()
  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  if not M.is_running(root) then
    util.error("Los contenedores no están corriendo. Ejecuta :OdooDockerUp primero")
    return
  end

  local service = M.get_service_name(root)
  local compose_cmd = M.get_compose_cmd()
  local cmd_str = table.concat(compose_cmd, " ") .. " exec " .. service .. " odoo shell"

  vim.cmd("vsplit | terminal cd " .. vim.fn.shellescape(root) .. " && " .. cmd_str)
  vim.cmd("startinsert")

  util.info("🐍 Odoo Shell abierto")
end

---Muestra los logs del servicio de Odoo
---@param opts? {follow?: boolean, tail?: number, service?: string}
function M.logs(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local service = opts.service or M.get_service_name(root)
  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "logs" })

  if opts.follow ~= false then
    table.insert(cmd, "-f")
  end

  if opts.tail then
    table.insert(cmd, "--tail=" .. opts.tail)
  else
    table.insert(cmd, "--tail=100")
  end

  table.insert(cmd, service)

  local cmd_str = table.concat(cmd, " ")

  -- Abrir terminal con los logs
  vim.cmd("vsplit | terminal cd " .. vim.fn.shellescape(root) .. " && " .. cmd_str)

  util.info("🐳 Mostrando logs de " .. service)
end

---Ejecuta un comando en el contenedor de Odoo
---@param command string
---@param opts? {service?: string, callback?: fun(output: string, code: number)}
function M.exec(command, opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  if not M.is_running(root) then
    util.error("Los contenedores no están corriendo")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  local service = opts.service or M.get_service_name(root)

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "exec", "-T", service })
  -- Añadir el comando como argumentos separados
  for word in command:gmatch("%S+") do
    table.insert(cmd, word)
  end

  local output = ""

  state.job = util.async_cmd(cmd, {
    cwd = root,
    on_stdout = function(data)
      output = output .. data
    end,
    on_exit = function(code)
      state.job = nil
      if opts.callback then
        opts.callback(output, code)
      end
    end,
  })
end

---Actualiza un módulo de Odoo en el contenedor
---@param module_name string
---@param opts? {database?: string}
function M.update_module(module_name, opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  -- Intentar obtener el nombre de la base de datos
  local database = opts.database

  if not database then
    -- Intentar leer del .env
    local env_file = root .. "/.env"
    if util.exists(env_file) then
      local content = vim.fn.readfile(env_file)
      for _, line in ipairs(content) do
        local db = line:match("^PGDATABASE=(.+)$") or line:match("^DB_NAME=(.+)$")
        if db then
          database = db:gsub('"', ""):gsub("'", "")
          break
        end
      end
    end
  end

  if not database then
    vim.ui.input({ prompt = "Nombre de la base de datos: " }, function(input)
      if input and input ~= "" then
        M._do_update_module(root, module_name, input)
      end
    end)
  else
    M._do_update_module(root, module_name, database)
  end
end

---Ejecuta la actualización del módulo
---@param root string
---@param module_name string
---@param database string
function M._do_update_module(root, module_name, database)
  util.info("🔄 Actualizando módulo: " .. module_name)

  local cmd = "odoo -d " .. database .. " -u " .. module_name .. " --stop-after-init"

  M.exec(cmd, {
    callback = function(output, code)
      if code == 0 then
        util.info("✓ Módulo " .. module_name .. " actualizado correctamente")
      else
        util.error("✗ Error al actualizar módulo")
        util.error(output)
      end
    end,
  })
end

---Muestra el estado de los contenedores
function M.status()
  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "ps" })

  local result = vim.system(cmd, {
    cwd = root,
    text = true,
  }):wait()

  if result.code == 0 then
    util.info("═══════════════════════════════════════")
    util.info("  🐳 Docker Status")
    util.info("═══════════════════════════════════════")

    for line in result.stdout:gmatch("[^\n]+") do
      util.info(line)
    end
  else
    util.error("Error al obtener estado de contenedores")
  end
end

---Reconstruye los contenedores
---@param opts? {no_cache?: boolean, service?: string}
function M.build(opts)
  opts = opts or {}

  local root = util.get_doodba_root()
  if not root then
    util.error("No se detectó un proyecto Doodba")
    return
  end

  local compose_cmd = M.get_compose_cmd()
  if #compose_cmd == 0 then
    util.error("docker-compose no está disponible")
    return
  end

  local cmd = vim.list_extend(vim.deepcopy(compose_cmd), { "build" })

  if opts.no_cache then
    table.insert(cmd, "--no-cache")
  end

  if opts.service then
    table.insert(cmd, opts.service)
  end

  util.info("🐳 Construyendo contenedores (esto puede tomar un momento)...")

  -- Usar terminal para ver el progreso
  local cmd_str = table.concat(cmd, " ")
  vim.cmd("vsplit | terminal cd " .. vim.fn.shellescape(root) .. " && " .. cmd_str)
end

---Registra los comandos de Docker
function M.setup_commands()
  vim.api.nvim_create_user_command("OdooDockerUp", function(cmd_opts)
    M.up({ build = cmd_opts.bang })
  end, {
    bang = true,
    desc = "Inicia contenedores Docker (! para rebuild)",
  })

  vim.api.nvim_create_user_command("OdooDockerDown", function()
    M.down()
  end, {
    desc = "Detiene contenedores Docker",
  })

  vim.api.nvim_create_user_command("OdooDockerRestart", function(cmd_opts)
    M.restart({ service = cmd_opts.args ~= "" and cmd_opts.args or nil })
  end, {
    nargs = "?",
    desc = "Reinicia el servicio de Odoo (o servicio especificado)",
  })

  vim.api.nvim_create_user_command("OdooDockerShell", function()
    M.shell()
  end, {
    desc = "Abre un shell en el contenedor de Odoo",
  })

  vim.api.nvim_create_user_command("OdooDockerOdooShell", function()
    M.odoo_shell()
  end, {
    desc = "Abre un Odoo shell en el contenedor",
  })

  vim.api.nvim_create_user_command("OdooDockerLogs", function(cmd_opts)
    local tail = cmd_opts.args ~= "" and tonumber(cmd_opts.args) or nil
    M.logs({ tail = tail })
  end, {
    nargs = "?",
    desc = "Muestra logs del contenedor de Odoo",
  })

  vim.api.nvim_create_user_command("OdooDockerStatus", function()
    M.status()
  end, {
    desc = "Muestra estado de los contenedores",
  })

  vim.api.nvim_create_user_command("OdooDockerBuild", function(cmd_opts)
    M.build({ no_cache = cmd_opts.bang })
  end, {
    bang = true,
    desc = "Construye contenedores (! para --no-cache)",
  })

  vim.api.nvim_create_user_command("OdooDockerExec", function(cmd_opts)
    M.exec(cmd_opts.args, {
      callback = function(output, code)
        if code == 0 then
          util.info("Salida:\n" .. output)
        else
          util.error("Error (código " .. code .. "):\n" .. output)
        end
      end,
    })
  end, {
    nargs = "+",
    desc = "Ejecuta un comando en el contenedor de Odoo",
  })

  vim.api.nvim_create_user_command("OdooUpdateModule", function(cmd_opts)
    M.update_module(cmd_opts.args)
  end, {
    nargs = 1,
    desc = "Actualiza un módulo de Odoo (-u)",
    complete = function()
      -- Podría implementarse autocompletado de módulos
      return {}
    end,
  })
end

return M
