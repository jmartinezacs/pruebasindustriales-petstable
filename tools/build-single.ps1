# Genera la versión de UN SOLO ARCHIVO para publicar:
#   index.html            (en la raíz del repositorio: lo que publica Vercel; todo incluido)
#   apple-touch-icon.png  (ícono de 512 px para iPhone y Android; nítido en la pantalla de inicio)
#   sw.js, manifest.webmanifest, notif-badge.png y notif-icon.png (notificaciones push)
#   version.json          (la app lo consulta y ofrece "Actualizar" si cambia APP_VERSION)
# a partir del código fuente en public/. Calcula los hashes de la Content-Security-Policy.
# Uso: powershell -ExecutionPolicy Bypass -File tools\build-single.ps1
param([string]$Src = (Join-Path $PSScriptRoot '..\public'), [string]$Out = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$Src = (Resolve-Path $Src).Path
New-Item -ItemType Directory -Force $Out | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
function Read-Text($rel) { ([IO.File]::ReadAllText((Join-Path $Src $rel), [Text.Encoding]::UTF8)).Replace("`r`n", "`n") }
function B64($rel) { [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Src $rel))) }

# ---------- 1. Empaquetar módulos ES en un script clásico ----------
# Orden de dependencias: cada módulo después de los que importa
$order = @('core', 'modules/exp_comun', 'modules/exp_captura', 'modules/exp_registro', 'modules/exp_ejec', 'modules/exp_eval', 'modules/exp_dict',
           'modules/pruebas', 'modules/dashboard', 'modules/programa', 'modules/insumos', 'modules/catalogos', 'modules/recetas',
           'modules/usuarios', 'modules/bitacora', 'modules/perfil', 'modules/campana', 'app')
$faltan = Get-ChildItem (Join-Path $Src 'js/modules') -Filter *.js | ForEach-Object { "modules/$($_.BaseName)" } | Where-Object { $order -notcontains $_ }
if ($faltan) { throw "Módulos sin incluir en el orden: $($faltan -join ', ')" }
function Resolve-Key([string]$from, [string]$spec) {
  $s = $spec -replace '\.js$', ''
  if ($s.StartsWith('../')) { return $s.Substring(3) }
  $s = $s.Substring(2)
  if ($from.StartsWith('modules/')) { return "modules/$s" }
  return $s
}
$bundle = New-Object Text.StringBuilder
[void]$bundle.Append("(function () {`n'use strict';`nconst __m = {};`n")
foreach ($key in $order) {
  $code = Read-Text("js/$key.js")
  $names = New-Object Collections.Generic.List[string]
  # import X, { a, b } from '...';
  $code = [regex]::Replace($code, "import\s+(\w+)\s*,\s*\{([^}]*)\}\s*from\s*'([^']+)';", [Text.RegularExpressions.MatchEvaluator]{
    param($m) $k = Resolve-Key $key $m.Groups[3].Value; "const $($m.Groups[1].Value) = __m['$k'].default; const {$($m.Groups[2].Value)} = __m['$k'];" })
  # import { a, b } from '...';
  $code = [regex]::Replace($code, "import\s*\{([^}]*)\}\s*from\s*'([^']+)';", [Text.RegularExpressions.MatchEvaluator]{
    param($m) "const {$($m.Groups[1].Value)} = __m['$(Resolve-Key $key $m.Groups[2].Value)'];" })
  # import X from '...';
  $code = [regex]::Replace($code, "import\s+(\w+)\s+from\s*'([^']+)';", [Text.RegularExpressions.MatchEvaluator]{
    param($m) "const $($m.Groups[1].Value) = __m['$(Resolve-Key $key $m.Groups[2].Value)'].default;" })
  if ($code -match '(^|\n)\s*import\s') { throw "Import no convertido en $key" }
  foreach ($m in [regex]::Matches($code, 'export\s+(?:async\s+)?(?:function|class|const|let)\s+(\w+)')) { $names.Add($m.Groups[1].Value) }
  $code = [regex]::Replace($code, 'export\s+((?:async\s+)?(?:function|class|const|let)\s)', '$1')
  $code = $code.Replace('export default ', '__exp.default = ')
  if ($code -match '(^|\n)\s*export\s') { throw "Export no convertido en $key" }
  $assign = if ($names.Count) { "Object.assign(__exp, { $($names -join ', ') });" } else { '' }
  [void]$bundle.Append("`n// ===== $key.js =====`n__m['$key'] = (function () {`nconst __exp = {};`n$code`n$assign`nreturn __exp;`n})();`n")
}
[void]$bundle.Append("})();")
$bundleJs = $bundle.ToString()
if ($bundleJs -match '</script') { throw 'El código contiene </script>' }

# ---------- 2. Recursos incrustados ----------
$css = (Read-Text('css/app.css')) + "`n" + (Read-Text('css/prubind.css'))
$css = $css.Replace("url('/img/logo-petstable.webp')", "url('data:image/webp;base64,$(B64 'img/logo-petstable.webp')')")
if ($css.Contains('/img/')) { throw 'Quedó una referencia a /img/ en el CSS' }
$themeJs = (Read-Text('js/theme-init.js')).Trim()
$configJs = (Read-Text('js/config.js')).Trim()

# Manifiesto como archivo aparte (las notificaciones en iPhone lo exigen al instalar la app).
# Sus íconos apuntan a archivos publicados en la raíz.
$m = Get-Content (Join-Path $Src 'manifest.webmanifest') -Raw -Encoding UTF8 | ConvertFrom-Json
$m.icons = @(
  [ordered]@{ src = '/apple-touch-icon.png?v=3'; sizes = '512x512'; type = 'image/png'; purpose = 'any' },
  [ordered]@{ src = '/notif-icon.png?v=3'; sizes = '192x192'; type = 'image/png'; purpose = 'any' }
)
$manifestJson = $m | ConvertTo-Json -Depth 5

function Sha([string]$t) { 'sha256-' + [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($t))) }
$supa = ([regex]::Match($configJs, 'https://[a-z0-9-]+\.supabase\.co')).Value
if (-not $supa) { throw 'No se encontró SUPABASE_URL en config.js' }
$wss = $supa.Replace('https://', 'wss://')
$csp = "default-src 'self'; script-src 'self' https://cdn.jsdelivr.net '$(Sha $themeJs)' '$(Sha $configJs)' '$(Sha $bundleJs)'; " +
       "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; " +
       "img-src 'self' data: blob: $supa; connect-src 'self' $supa $wss; " +
       "manifest-src 'self'; worker-src 'self'; base-uri 'self'; form-action 'self'; object-src 'none'"
$icon128 = 'data:image/png;base64,' + (B64 'img/app-icon-128.png')
$fav64 = 'data:image/png;base64,' + (B64 'icons/favicon-64.png')

# ---------- 3. Ensamblar HTML ----------
$html = Read-Text('index.html')
function Swap([string]$find, [string]$repl) {
  if (-not $script:html.Contains($find)) { throw "No se encontró en index.html: $find" }
  $script:html = $script:html.Replace($find, $repl)
}
Swap '  <link rel="icon" href="/favicon.ico?v=1" sizes="any">' "  <meta http-equiv=`"Content-Security-Policy`" content=`"$csp`">`n  <link rel=`"icon`" type=`"image/png`" sizes=`"64x64`" href=`"$fav64`">"
Swap "  <link rel=`"icon`" type=`"image/png`" sizes=`"64x64`" href=`"/icons/favicon-64.png?v=3`">`n" ''
Swap '  <link rel="manifest" href="/manifest.webmanifest?v=1">' '  <link rel="manifest" href="/manifest.webmanifest">'
Swap '<img class="app-icon" src="/img/app-icon-128.png"' "<img class=`"app-icon`" src=`"$icon128`""
Swap "  <link rel=`"stylesheet`" href=`"/css/app.css?v=2.0.0`">`n  <link rel=`"stylesheet`" href=`"/css/prubind.css?v=2.0.0`">" "  <style>`n$css</style>"
Swap '  <script src="/js/theme-init.js"></script>' "  <script>$themeJs</script>"
Swap '  <script src="/js/config.js?v=2.0.0"></script>' "  <script>$configJs</script>"
Swap '  <script type="module" src="/js/app.js?v=2.0.0"></script>' "  <script>$bundleJs</script>"
foreach ($ref in @('/css/', '/js/', '/img/', '/icons/', 'favicon.ico')) {
  if ($html.Contains($ref)) { throw "Quedó una referencia externa a $ref" }
}
$html = "<!-- Pruebas industriales · Pet's Table — archivo generado por tools/build-single.ps1. Edita las fuentes en public/ y vuelve a generar. -->`n" + $html
[IO.File]::WriteAllText((Join-Path $Out 'index.html'), $html, $utf8)
Copy-Item (Join-Path $Src 'apple-touch-icon.png') (Join-Path $Out 'apple-touch-icon.png') -Force
# Archivos que no pueden ir dentro del HTML: service worker (avisos push), manifiesto e íconos de los avisos
Copy-Item (Join-Path $Src 'sw.js') (Join-Path $Out 'sw.js') -Force
[IO.File]::WriteAllText((Join-Path $Out 'manifest.webmanifest'), $manifestJson + "`n", $utf8)
# Insignia monocromática (barra de estado de Android) e ícono grande de respaldo
Copy-Item (Join-Path $Src 'img/notif-badge.png') (Join-Path $Out 'notif-badge.png') -Force
Copy-Item (Join-Path $Src 'img/notif-icon.png') (Join-Path $Out 'notif-icon.png') -Force
if ($configJs -notmatch 'APP_VERSION:\s*"([^"]+)"') { throw 'No se encontró APP_VERSION en config.js' }
[IO.File]::WriteAllText((Join-Path $Out 'version.json'), "{`"version`":`"$($Matches[1])`"}`n", $utf8)
Get-Item (@('index.html', 'apple-touch-icon.png', 'sw.js', 'manifest.webmanifest', 'version.json', 'notif-badge.png', 'notif-icon.png') | ForEach-Object { Join-Path $Out $_ }) | ForEach-Object { '{0,-24} {1,10:N0} bytes' -f $_.Name, $_.Length }
