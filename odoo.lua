---@brief [[
--- odoo.nvim - IDE para Odoo 16 en Neovim
---
--- Este archivo carga el plugin automáticamente.
--- Para lazy loading, usar lazy.nvim con cmd/ft/event.
---@brief ]]

if vim.g.loaded_odoo then
  return
end
vim.g.loaded_odoo = true

-- Verificar versión mínima de Neovim
if vim.fn.has("nvim-0.9.0") ~= 1 then
  vim.notify("odoo.nvim requiere Neovim >= 0.9.0", vim.log.levels.ERROR)
  return
end

-- Crear comando para setup inicial
vim.api.nvim_create_user_command("OdooSetup", function()
  require("odoo").setup()
end, {
  desc = "Inicializa odoo.nvim con configuración por defecto",
})

-- Auto-setup si se desea (descomentado para lazy loading manual)
-- require("odoo").setup()
