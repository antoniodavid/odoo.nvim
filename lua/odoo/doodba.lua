---@class odoo.doodba
local M = {}

local util = require("odoo.util")

---Detecta el módulo actual desde el archivo abierto
---@return string|nil module_name
---@return string|nil module_path
function M.get_current_module()
  local file_path = vim.fn.expand("%:p")
  local odoo_root = util.get_odoo_root()
  
  if not odoo_root then
    return nil, nil
  end
  
  -- Buscar __manifest__.py o __openerp__.py hacia arriba
  local dir = vim.fn.fnamemodify(file_path, ":h")
  local max_depth = 10
  local depth = 0
  
  while dir ~= odoo_root and depth < max_depth do
    if util.exists(dir .. "/__manifest__.py") or util.exists(dir .. "/__openerp__.py") then
      local module_name = vim.fn.fnamemodify(dir, ":t")
      return module_name, dir
    end
    dir = vim.fn.fnamemodify(dir, ":h")
    depth = depth + 1
  end
  
  return nil, nil
end

---Ejecuta un comando en terminal flotante
---@param cmd string|string[] Comando a ejecutar
---@param opts? {title?: string, cwd?: string, on_exit?: function}
function M.run_in_terminal(cmd, opts)
  opts = opts or {}
  
  -- Convertir tabla a string si es necesario
  if type(cmd) == "table" then
    cmd = table.concat(cmd, " ")
  end
  
  -- Crear buffer de terminal
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  
  -- Calcular dimensiones
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)
  
  -- Crear ventana flotante
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or cmd) .. " ",
    title_pos = "center",
  })
  
  -- Configurar highlights
  vim.api.nvim_win_set_option(win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
  
  -- Ejecutar comando en terminal
  local job_id = vim.fn.termopen(cmd, {
    cwd = opts.cwd,
    on_exit = function(_, exit_code)
      if opts.on_exit then
        opts.on_exit(exit_code)
      end
      
      if exit_code == 0 then
        vim.notify("✓ Command completed successfully", vim.log.levels.INFO)
      else
        vim.notify("✗ Command failed with code " .. exit_code, vim.log.levels.ERROR)
      end
    end
  })
  
  -- Keymaps para cerrar
  vim.keymap.set("n", "q", ":q<CR>", { buffer = buf, silent = true, desc = "Close terminal" })
  vim.keymap.set("n", "<Esc>", ":q<CR>", { buffer = buf, silent = true, desc = "Close terminal" })
  
  -- Entrar en modo insert automáticamente
  vim.cmd("startinsert")
  
  return job_id, buf, win
end

---Ejecuta un comando invoke
---@param args string Argumentos para invoke
---@param opts? {show_terminal?: boolean, title?: string}
function M.invoke(args, opts)
  opts = opts or {}
  local root = util.get_odoo_root()
  
  if not root then
    util.warn("No se detectó un proyecto Odoo")
    return
  end
  
  local cmd = "inv " .. args
  
  if opts.show_terminal then
    M.run_in_terminal(cmd, {
      title = opts.title or ("Invoke: " .. args),
      cwd = root,
    })
  else
    -- Ejecutar en background
    vim.fn.jobstart(cmd, {
      cwd = root,
      on_exit = function(_, code)
        if code == 0 then
          vim.notify("✓ inv " .. args, vim.log.levels.INFO)
        else
          vim.notify("✗ inv " .. args .. " failed", vim.log.levels.ERROR)
        end
      end
    })
  end
end

---Ejecuta un comando docker compose
---@param args string Argumentos para docker compose
---@param opts? {show_terminal?: boolean, title?: string}
function M.docker_compose(args, opts)
  opts = opts or {}
  local root = util.get_odoo_root()
  
  if not root then
    util.warn("No se detectó un proyecto Odoo")
    return
  end
  
  local cmd = "docker compose " .. args
  
  if opts.show_terminal then
    M.run_in_terminal(cmd, {
      title = opts.title or ("Docker: " .. args),
      cwd = root,
    })
  else
    vim.fn.jobstart(cmd, {
      cwd = root,
      on_exit = function(_, code)
        if code == 0 then
          vim.notify("✓ " .. cmd, vim.log.levels.INFO)
        else
          vim.notify("✗ " .. cmd .. " failed", vim.log.levels.ERROR)
        end
      end
    })
  end
end

---Inicia Odoo con logs
function M.start()
  M.invoke("start logs -c odoo", {
    show_terminal = true,
    title = "Odoo Start",
  })
end

---Reinicia Odoo con logs
function M.restart()
  M.invoke("restart logs -c odoo", {
    show_terminal = true,
    title = "Odoo Restart",
  })
end

---Detiene Odoo
function M.stop()
  M.invoke("stop", {
    show_terminal = false,
  })
end

---Muestra logs de un servicio
---@param service? string Nombre del servicio (default: odoo)
function M.logs(service)
  service = service or "odoo"
  M.invoke("logs -c " .. service, {
    show_terminal = true,
    title = "Logs: " .. service,
  })
end

---Reset completo de base de datos
function M.resetdb()
  vim.ui.input({
    prompt = "⚠️  Esto eliminará TODA la base de datos. ¿Continuar? (yes/no): ",
  }, function(input)
    if input == "yes" then
      M.invoke("resetdb preparedb start logs -c odoo", {
        show_terminal = true,
        title = "Reset Database",
      })
    else
      vim.notify("Reset cancelado", vim.log.levels.INFO)
    end
  end)
end

---Abre shell en contenedor Odoo
function M.shell()
  M.docker_compose("run --rm odoo bash", {
    show_terminal = true,
    title = "Odoo Shell",
  })
end

---Abre PostgreSQL shell
function M.psql()
  M.docker_compose("run --rm odoo psql", {
    show_terminal = true,
    title = "PostgreSQL",
  })
end

---Ejecuta comando en contenedor Odoo
---@param cmd string Comando a ejecutar
function M.exec(cmd)
  M.docker_compose("run --rm odoo " .. cmd, {
    show_terminal = true,
    title = "Exec: " .. cmd,
  })
end

---Actualiza módulos con odoo-click-update
---@param modules? string Módulos a actualizar (separados por coma)
function M.update(modules)
  local cmd = "run --rm odoo odoo-click-update"
  if modules then
    cmd = cmd .. " " .. modules
  end
  
  M.docker_compose(cmd, {
    show_terminal = true,
    title = "Update: " .. (modules or "all"),
  })
end

---Instala módulos con odoo-click-install
---@param modules string Módulos a instalar (separados por coma)
function M.install(modules)
  if not modules or modules == "" then
    util.warn("Especifica módulos a instalar")
    return
  end
  
  M.docker_compose("run --rm odoo odoo-click-install " .. modules, {
    show_terminal = true,
    title = "Install: " .. modules,
  })
end

---Desinstala módulos con odoo-click-uninstall
---@param modules string Módulos a desinstalar (separados por coma)
function M.uninstall(modules)
  if not modules or modules == "" then
    util.warn("Especifica módulos a desinstalar")
    return
  end
  
  M.docker_compose("run --rm odoo odoo-click-uninstall " .. modules, {
    show_terminal = true,
    title = "Uninstall: " .. modules,
  })
end

---Actualiza el módulo actual (auto-detectado)
function M.update_current()
  local module_name, module_path = M.get_current_module()
  
  if not module_name then
    util.warn("No se pudo detectar el módulo actual")
    util.info("Asegúrate de estar en un archivo dentro de un módulo Odoo")
    return
  end
  
  vim.notify("Actualizando módulo: " .. module_name, vim.log.levels.INFO)
  M.update(module_name)
end

---Instala el módulo actual (auto-detectado)
function M.install_current()
  local module_name, module_path = M.get_current_module()
  
  if not module_name then
    util.warn("No se pudo detectar el módulo actual")
    util.info("Asegúrate de estar en un archivo dentro de un módulo Odoo")
    return
  end
  
  vim.notify("Instalando módulo: " .. module_name, vim.log.levels.INFO)
  M.install(module_name)
end

---Reinicia y actualiza el módulo actual
function M.restart_update()
  local module_name = M.get_current_module()
  
  if not module_name then
    util.warn("No se pudo detectar el módulo actual")
    return
  end
  
  -- Primero reiniciar
  vim.notify("Reiniciando Odoo...", vim.log.levels.INFO)
  M.invoke("restart", { show_terminal = false })
  
  -- Esperar 3 segundos y luego actualizar
  vim.defer_fn(function()
    vim.notify("Actualizando módulo: " .. module_name, vim.log.levels.INFO)
    M.update(module_name)
  end, 3000)
end

---Configura keymaps para Doodba
function M.setup_keymaps()
  local odoo_root, project_type = util.get_odoo_root()
  
  -- Solo aplicar en proyectos Doodba
  if project_type ~= "doodba" then
    return
  end
  
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "python",
    callback = function(args)
      local bufnr = args.buf
      
      -- Solo aplicar en proyectos Doodba
      if not util.is_doodba_project() then
        return
      end
      
      -- <leader>du: Update current module
      vim.keymap.set("n", "<leader>du", function()
        M.update_current()
      end, {
        buffer = bufnr,
        desc = "Doodba: Update current module",
      })
      
      -- <leader>dr: Restart and update
      vim.keymap.set("n", "<leader>dr", function()
        M.restart_update()
      end, {
        buffer = bufnr,
        desc = "Doodba: Restart and update",
      })
      
      -- <leader>ds: Start Odoo
      vim.keymap.set("n", "<leader>ds", function()
        M.start()
      end, {
        buffer = bufnr,
        desc = "Doodba: Start Odoo",
      })
      
      -- <leader>dl: View logs
      vim.keymap.set("n", "<leader>dl", function()
        M.logs()
      end, {
        buffer = bufnr,
        desc = "Doodba: View logs",
      })
      
      -- <leader>dh: Shell
      vim.keymap.set("n", "<leader>dh", function()
        M.shell()
      end, {
        buffer = bufnr,
        desc = "Doodba: Shell",
      })
      
      util.debug("Keymaps de Doodba configurados para buffer " .. bufnr)
    end,
  })
end

return M
