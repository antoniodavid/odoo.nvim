# 🐍 odoo.nvim

> Convierte Neovim en un IDE completo para **todas las versiones de Odoo** con configuración Zero-Config
> Soporta proyectos **estándar** y **Doodba** (Docker)

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white)
![Odoo](https://img.shields.io/badge/Odoo-714B67?style=for-the-badge&logo=odoo&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)

## ✨ Características

- **🔌 Zero-Config**: Detecta automáticamente proyectos Odoo estándar y Doodba
- **📦 Multi-Versión**: Soporta Odoo 8.0 a 18.0+ con detección automática
- **🐳 Soporte Doodba**: Integración completa con Docker y estructura Tecnativa/Copier
- **🧠 LSP Inteligente**: Inyecta configuración en Pyright/Basedpyright automáticamente
- **📦 Stubs Tipados**: Descarga automática desde [odoo-ide/odoo-stubs](https://github.com/odoo-ide/odoo-stubs)
- **🔧 Generación Dinámica**: Genera stubs con `stubgen` para versiones sin soporte
- **🧭 Navegación XML→Python**: Salta de vistas XML a definiciones Python con `gd`
- **🔍 Búsqueda Integrada**: Usa Telescope para búsquedas rápidas
- **🐳 Comandos Docker**: Controla contenedores directamente desde Neovim

## 📦 Versiones Soportadas

| Versión | Python | Stubs | Estado |
|---------|--------|-------|--------|
| 18.0 | 3.12 | ✅ | Completo |
| 17.0 | 3.10 | ✅ | Completo |
| 16.0 | 3.10 | ✅ | Completo |
| 15.0 | 3.8 | ✅ | Completo |
| 14.0 | 3.8 | ✅ | Completo |
| 13.0 | 3.6 | ✅ | Completo |
| 12.0 | 3.6 | ✅ | Completo |
| 11.0 | 3.5 | 🔧 | stubgen |
| 10.0 | 2.7 | 🔧 | stubgen |
| 9.0 | 2.7 | 🔧 | stubgen |
| 8.0 | 2.7 | 🔧 | stubgen |

> 🔧 = Puedes generar stubs dinámicamente con `:OdooGenerateStubs`

## 📋 Requisitos

- Neovim >= 0.9.0
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
- [pyright](https://github.com/microsoft/pyright) o [basedpyright](https://github.com/DetachHead/basedpyright)
- Git (para descarga de stubs)

### Para generación dinámica de stubs

- mypy (`pip install mypy`)

### Para proyectos Doodba

- Docker
- docker-compose (o `docker compose`)

### Opcionales (Recomendados)

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - Búsquedas avanzadas
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - Parsing XML preciso

## 📦 Instalación

### Con [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tu-usuario/odoo.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-telescope/telescope.nvim", -- opcional
    "nvim-treesitter/nvim-treesitter", -- opcional
  },
  ft = { "python", "xml" },
  cmd = {
    "OdooDownloadStubs",
    "OdooInfo",
    "OdooHealth",
    "OdooGotoModel",
    "OdooDockerUp",
  },
  opts = {},
}
```

### Configuración completa

```lua
{
  "tu-usuario/odoo.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  event = "VeryLazy",
  config = function()
    require("odoo").setup({
      -- Gestión de Stubs (desde odoo-ide/odoo-stubs)
      stubs = {
        repo = "https://github.com/odoo-ide/odoo-stubs",
        branch = nil, -- nil = auto-detectar según versión
        auto_download = true,
        fallback_branch = "16.0",
        -- Generación dinámica con stubgen
        generate = {
          enabled = false,
          use_inspect = true, -- Mejor calidad pero requiere importar módulos
        },
      },

      -- Configuración de LSP
      lsp = {
        auto_inject = true,
        server = "pyright", -- o "basedpyright"
        analysis = {
          typeCheckingMode = "basic", -- off, basic, standard, strict
        },
      },

      -- Navegación
      navigation = {
        use_telescope = true,
        xml_goto_definition = true,
        keymaps = {
          goto_definition = "gd",
          goto_xml_id = "gx",
          goto_model = "gm",
        },
      },

      -- Detección de proyectos
      detection = {
        markers = { "odoo-bin", "__manifest__.py", "__openerp__.py" },
        -- Marcadores de Doodba (estructura Tecnativa/Copier)
        doodba_markers = {
          "odools.toml",
          "tasks.py",
          "common.yaml",
          "devel.yaml",
          ".copier-answers.yml",
        },
        auto_detect = true,
      },

      -- Versión
      version = {
        auto_detect = true, -- Detectar automáticamente
        default = "16.0", -- Fallback si no se detecta
      },

      -- Doodba/Docker
      doodba = {
        enabled = true,
        docker_service = "odoo",
        auto_detect_service = true,
      },
    })
  end,
}
```

## 🔍 Detección Automática de Versión

El plugin detecta la versión de Odoo automáticamente buscando en:

1. **odools.toml** - Configuración de proyectos Doodba modernos
2. **common.yaml / devel.yaml** - Archivos Docker de Doodba
3. **release.py** - Archivo oficial de versión de Odoo
4. **docker-compose.yml** - Imagen de Docker usada
5. **.copier-answers.yml** - Configuración de Doodba/Copier
6. **requirements.txt** - Dependencias Python
7. **.env** - Variables de entorno

Si no se detecta, usa la versión configurada en `version.default`.

## 🐳 Soporte Doodba

El plugin detecta automáticamente proyectos Doodba (estructura Tecnativa/Copier) buscando:

- `odools.toml` - Configuración de herramientas Odoo
- `tasks.py` - Tareas invoke de Doodba
- `common.yaml` / `devel.yaml` / `prod.yaml` - Docker compose
- `.copier-answers.yml` - Respuestas de Copier

### Estructura de Doodba soportada

```
proyecto-doodba/
├── common.yaml              # Docker compose común
├── devel.yaml               # Docker compose desarrollo
├── docker-compose.yml       # → symlink a devel.yaml
├── prod.yaml                # Docker compose producción
├── test.yaml                # Docker compose tests
├── odools.toml              # Configuración de odools
├── tasks.py                 # Tareas invoke
├── .copier-answers.yml      # Respuestas de Copier
├── setup-devel.yaml
├── odoo/
│   ├── auto/
│   │   └── addons/          # ← Addons descargados
│   ├── custom/
│   │   ├── src/             # ← Addons custom
│   │   ├── build.d/
│   │   ├── conf.d/
│   │   ├── dependencies/
│   │   ├── entrypoint.d/
│   │   └── ssh/
│   ├── Dockerfile
│   └── odoo.conf
└── private/                 # ← Addons privados (opcional)
```

### Comandos Docker

| Comando | Descripción |
|---------|-------------|
| `:OdooDockerUp[!]` | Inicia contenedores (`!` para rebuild) |
| `:OdooDockerDown` | Detiene contenedores |
| `:OdooDockerRestart [service]` | Reinicia servicio de Odoo |
| `:OdooDockerShell` | Abre bash en el contenedor de Odoo |
| `:OdooDockerOdooShell` | Abre `odoo shell` en el contenedor |
| `:OdooDockerLogs [n]` | Muestra logs (últimas n líneas) |
| `:OdooDockerStatus` | Muestra estado de contenedores |
| `:OdooDockerBuild[!]` | Construye contenedores (`!` para --no-cache) |
| `:OdooDockerExec {cmd}` | Ejecuta comando en contenedor |
| `:OdooUpdateModule {mod}` | Actualiza módulo con `-u` |

## 📦 Gestión de Stubs

### Stubs Pre-generados (odoo-ide/odoo-stubs)

Los stubs tipados vienen del repositorio oficial [odoo-ide/odoo-stubs](https://github.com/odoo-ide/odoo-stubs) y se organizan por versión:

```
~/.local/share/nvim/odoo-stubs/
├── 12.0/
│   └── odoo-stubs/
├── 14.0/
│   └── odoo-stubs/
├── 16.0/
│   └── odoo-stubs/
└── 17.0/
    └── odoo-stubs/
```

### Generación Dinámica con stubgen

Para versiones sin stubs pre-generados o para módulos custom, puedes generar stubs dinámicamente usando `stubgen` de mypy:

```vim
" Generar stubs para el Odoo del proyecto actual
:OdooGenerateStubs

" Generar para un path específico
:OdooGenerateStubs /path/to/odoo

" Forzar regeneración
:OdooGenerateStubs!
```

Los stubs generados se guardan en `~/.local/share/nvim/odoo-stubs/generated-{version}/`.

> **Nota**: stubgen genera stubs "borrador" que pueden requerir ajustes manuales para máxima precisión. Para mejor calidad, los stubs pre-generados son preferibles.

### Comandos de Stubs

| Comando | Descripción |
|---------|-------------|
| `:OdooDownloadStubs [version]` | Descarga stubs (auto-detecta versión si no se especifica) |
| `:OdooDownloadStubs!` | Fuerza actualización |
| `:OdooDownloadAllStubs` | Descarga stubs para todas las versiones |
| `:OdooRemoveStubs [version]` | Elimina stubs (todos si no se especifica versión) |
| `:OdooStubsInfo` | Muestra información de stubs instalados |
| `:OdooGenerateStubs [path]` | Genera stubs dinámicamente con stubgen |

## 🎮 Comandos Generales

| Comando | Descripción |
|---------|-------------|
| `:OdooInfo` | Muestra estado completo del plugin |
| `:OdooHealth` | Ejecuta diagnóstico |
| `:OdooLspReload` | Recarga configuración LSP |
| `:OdooLspInfo` | Muestra configuración LSP actual |
| `:OdooGotoModel {model}` | Navega a definición de modelo |
| `:OdooGotoXmlId {xml_id}` | Navega a XML ID |
| `:OdooGotoField {field}` | Navega a definición de campo |
| `:OdooGeneratePyrightConfig` | Genera pyrightconfig.json |

## ⌨️ Keymaps

En archivos **XML** dentro de proyectos Odoo:

| Keymap | Acción |
|--------|--------|
| `gd` | Ir a definición (modelo, campo, o XML ID según contexto) |
| `gm` | Ir al modelo del contexto actual |
| `gx` | Ir a XML ID |

### Elementos navegables en XML

- `model="res.partner"` → Salta a la clase Python con `_name = 'res.partner'`
- `<field name="name"/>` → Salta a la definición del campo en Python
- `ref="base.main_company"` → Salta al registro XML con ese ID

## ⚙️ Configuración de Pyright

El plugin inyecta automáticamente la configuración de Pyright incluyendo:

- **stubPath**: Apuntando a los stubs de la versión correcta
- **extraPaths**: Todos los directorios de addons detectados
- **pythonVersion**: Según la versión de Odoo (3.6-3.12)
- **diagnosticSeverityOverrides**: Ajustados para tolerar meta-programación de Odoo

```lua
require("lspconfig").pyright.setup({
  -- odoo.nvim inyectará todo automáticamente
})
```

## 🩺 Diagnóstico

Ejecuta `:checkhealth odoo` para verificar:
- Versión de Neovim
- Dependencias instaladas
- stubgen disponible (para generación dinámica)
- Docker y docker-compose (para Doodba)
- Stubs instalados por versión
- Tipo de proyecto y versión detectada
- Configuración de LSP activa
- Estado de contenedores Docker

## 📁 Estructura del Plugin

```
odoo.nvim/
├── lua/odoo/
│   ├── init.lua       # Punto de entrada principal
│   ├── config.lua     # Configuración y versiones
│   ├── util.lua       # Utilidades y detección
│   ├── stubs.lua      # Gestión de stubs + stubgen
│   ├── lsp.lua        # Integración con LSP
│   ├── navigation.lua # Navegación XML→Python
│   ├── docker.lua     # Integración Docker/Doodba
│   └── health.lua     # :checkhealth
├── plugin/odoo.lua    # Carga automática
├── doc/odoo.nvim.txt  # Documentación :help
└── README.md
```

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Por favor:

1. Fork el repositorio
2. Crea una rama feature (`git checkout -b feature/amazing-feature`)
3. Commit tus cambios (`git commit -m 'Add amazing feature'`)
4. Push a la rama (`git push origin feature/amazing-feature`)
5. Abre un Pull Request

## 📝 Roadmap

- [x] Soporte para proyectos Doodba (estructura Tecnativa/Copier)
- [x] Comandos Docker integrados
- [x] Soporte multi-versión (8.0 - 18.0+)
- [x] Detección automática de versión
- [x] Stubs desde odoo-ide/odoo-stubs
- [x] Generación dinámica con stubgen
- [ ] Snippets para modelos, campos y vistas
- [ ] Previsualización de vistas XML
- [ ] Autocompletado de XML IDs
- [ ] Generador de módulos
- [ ] Integración con debugger (debugpy)

## 📚 Referencias

- [odoo-ide/odoo-stubs](https://github.com/odoo-ide/odoo-stubs) - Stubs tipados oficiales
- [mypy stubgen](https://mypy.readthedocs.io/en/stable/stubgen.html) - Generación automática de stubs
- [Doodba](https://github.com/Tecnativa/doodba) - Docker + Odoo Base

## 📄 Licencia

MIT © 2024

---

<p align="center">
  Hecho con ❤️ para la comunidad Odoo
</p>
