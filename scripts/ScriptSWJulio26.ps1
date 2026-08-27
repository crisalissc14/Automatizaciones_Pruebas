<#
.SYNOPSIS
  Pipeline completo de gestión de software:
  1) Resuelve la última versión "oficial" de cada aplicativo (fabricante).
  2) Descarga el instalador oficial a una carpeta temporal.
  3) Valida integridad (hash oficial, cuando el fabricante lo publica) y
     seguridad del instalador con VirusTotal y con Microsoft Defender, y
     revisa su firma digital (Authenticode) de forma informativa.
  4) Se aprueba si AL MENOS UNO de los dos motores (VirusTotal o Defender)
     confirma explícitamente que el archivo está limpio (se tratan como dos
     verificaciones alternativas/redundantes, no es necesario que ambos
     coincidan). Si ninguno de los dos lo valida -> intenta la penúltima
     versión segura registrada en el histórico, dejando la justificación en
     el informe. Si tampoco pasa -> lo marca bloqueado.
  5) Si pasa -> mueve el instalador a la carpeta de entrega (el script NO
     ejecuta la instalación en el equipo; deja el paquete listo y validado).
  6) Mantiene versions_history.json (última / penúltima versión segura por app).
  7) Genera Informe.txt con una tabla y el detalle de cada aplicativo.

.NOTES
  - Compatible con Windows PowerShell 5.1 y PowerShell 7+.
  - Requiere permisos de administrador para invocar MpCmdRun.exe (Defender).
  - Requiere una API key de VirusTotal (variable de entorno VT_API_KEY o parámetro).
  - La API pública de VirusTotal tiene límite de 4 req/min y 32MB por archivo.
    El script respeta ese límite con un limitador de tasa (Wait-VTRateLimit)
    que se aplica a TODAS las llamadas a VT (consulta por hash, subida y cada
    sondeo de análisis), no solo antes de subir archivos. Ante un HTTP 429
    reintenta con espera antes de rendirse. Si tu instalador pesa más de 32MB
    (ej. Android Studio, Docker Desktop), VT rechazará la subida: en ese caso
    el script cae automáticamente a "solo Defender" y lo deja anotado en Notes.
  - Algunos fabricantes (CyberArk EPM, Bizagi Modeler, DCNet) NO exponen una URL
    de descarga directa pública: quedan marcados como "Descarga manual requerida"
    y el pipeline de validación/entrega se omite para ellos.
  - think-cell requiere licencia comercial (solo prueba gratuita limitada), por lo
    que tampoco se automatiza: se marca para gestión manual con el proveedor.
#>

param(
  [string] $VirusTotalApiKey = $env:VT_API_KEY,
  [string] $TempDownloadDir  = "C:\Temp\SoftUpdates",
  [string] $DeliveryDir      = "C:\EntregaMSI",
  [string] $HistoryFile      = ".\versions_history.json",
  [string] $ReportFile       = ".\Informe.txt",
  [string] $InventoryJson    = ".\latest_versions_official.json",
  [switch] $SkipDownload,        # solo generar inventario de versiones, sin descargar/validar
  [switch] $SkipVirusTotal       # útil si no tienes API key a mano; valida solo con Defender
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============================================================
# LÍMITE DE TASA PARA VIRUSTOTAL (API pública: 4 req/min)
# Se aplica antes de CADA llamada HTTP a VT (consulta por hash, subida,
# sondeo de análisis). Antes solo se pausaba antes de subir archivos nuevos,
# por lo que con ~24 aplicativos la sola consulta por hash podía disparar
# HTTP 429 sin control.
# ============================================================
$script:VTLastRequestTime = Get-Date "1970-01-01"
$script:VTMinIntervalSec  = 16   # 4 req/min = 1 cada 15s; se deja margen

function Wait-VTRateLimit {
  $elapsed = (Get-Date) - $script:VTLastRequestTime
  $needed  = $script:VTMinIntervalSec - $elapsed.TotalSeconds
  if ($needed -gt 0) { Start-Sleep -Seconds $needed }
  $script:VTLastRequestTime = Get-Date
}

# Extrae el código HTTP de una excepción de Invoke-RestMethod tanto en
# Windows PowerShell 5.1 (System.Net.WebException) como en PowerShell 7+
# (Microsoft.PowerShell.Commands.HttpResponseException).
function Get-HttpStatusCode {
  param([Parameter(Mandatory)]$ErrorRecord)
  $resp = $ErrorRecord.Exception.Response
  if (-not $resp) { return $null }
  try { return [int]$resp.StatusCode } catch { return $null }
}

# Publishers esperados por aplicativo, para la verificación informativa de
# firma digital (Authenticode). No bloquea la entrega: solo queda anotado en
# el informe para revisión manual, ya que ni VT ni Defender validan por sí
# solos que el instalador venga realmente del fabricante esperado.
$script:ExpectedPublishers = @{
  "Google Chrome (Standalone) - Stable (Win64)" = @("Google LLC")
  "Mozilla Firefox (Standalone) - Latest"       = @("Mozilla Corporation")
  "Visual Studio Code (stable, win32-x64)"      = @("Microsoft Corporation")
  "Git (latest from git-scm.com)"               = @("Johannes Schindelin", "Git for Windows", "Software Freedom Conservancy, Inc.")
  "Node.js (Current)"                           = @("OpenJS Foundation", "Node.js Foundation")
  "Node.js (LTS per official index.json)"       = @("OpenJS Foundation", "Node.js Foundation")
  "Docker Desktop (Windows AMD64)"               = @("Docker Inc")
  "Python (Latest 3.x for Windows)"             = @("Python Software Foundation")
  "Adobe Acrobat Reader (Continuous track - latest)" = @("Adobe")
  "7-Zip"                                       = @("Igor Pavlov")
  "Wireshark"                                   = @("Wireshark Foundation", "Wireshark")
  "PuTTY (64-bit)"                              = @("Simon Tatham")
  "Nmap"                                        = @("Insecure.Com LLC", "Nmap Project", "Nmap.Org")
  "OpenJDK (Eclipse Temurin, LTS más reciente, Windows x64 MSI)" = @("Eclipse Foundation, Inc.", "Eclipse Adoptium")
  "Power Automate for Desktop"                  = @("Microsoft Corporation")
  ".NET SDK (LTS más reciente, win-x64)"        = @("Microsoft Corporation")
  "Visual Studio Professional 2026 (bootstrapper)" = @("Microsoft Corporation")
  "Visual Studio Enterprise 2026 (bootstrapper)"   = @("Microsoft Corporation")
  "Visual Studio Professional 2022 (bootstrapper)" = @("Microsoft Corporation")
  "Visual Studio Enterprise 2022 (bootstrapper)"   = @("Microsoft Corporation")
  "Azure Connected Machine Agent"                = @("Microsoft Corporation")
  ".NET Runtime (LTS más reciente, win-x64)"     = @("Microsoft Corporation")
  "ASP.NET Core Runtime (LTS más reciente, win-x64)" = @("Microsoft Corporation")
  ".NET Hosting Bundle (LTS más reciente)"       = @("Microsoft Corporation")
  "IntelliJ IDEA Community Edition"              = @("JetBrains s.r.o.")
  "JetBrains dotPeek"                            = @("JetBrains s.r.o.")
  "RStudio Desktop"                              = @("Posit Software, PBC", "RStudio, PBC", "RStudio")
  "R for Windows"                                = @("The R Foundation for Statistical Computing", "R Core Team")
  "Figma (desktop)"                              = @("Figma, Inc.", "Figma")
  "Postman"                                      = @("Postman, Inc.", "Postman")
  "Araxis Merge"                                 = @("Araxis Ltd", "Araxis Limited")
}

# Hashes SHA256 "oficiales" publicados directamente por el fabricante (cuando
# están disponibles en la misma respuesta que ya usamos para resolver la
# versión). Se comparan contra el archivo descargado para detectar descargas
# corruptas o manipuladas (MITM/tampering), independientemente de lo que diga
# el antivirus: un hash que no coincide con el oficial nunca debe entregarse.
$script:OfficialHashes = @{}

# ============================================================
# HELPERS BASE (del script original)
# ============================================================

function Get-TextFromUrl {
  param([Parameter(Mandatory)][string]$Url, [hashtable]$Headers = @{})
  if (-not $Headers.ContainsKey("User-Agent")) {
    $Headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-OfficialVersionCheck/1.0"
  }
  $lastError = $null
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
      return (Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60).Content
    } catch {
      $lastError = $_
      if ($attempt -lt 2) { Start-Sleep -Seconds 5 }
    }
  }
  throw $lastError
}

function Get-JsonFromUrl {
  param([Parameter(Mandatory)][string]$Url, [hashtable]$Headers = @{})
  if (-not $Headers.ContainsKey("User-Agent")) {
    $Headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-OfficialVersionCheck/1.0"
  }
  Invoke-RestMethod -Uri $Url -Headers $Headers -MaximumRedirection 10 -TimeoutSec 60
}

# Sube un archivo como multipart/form-data usando System.Net.Http.HttpClient
# directamente (en vez del parámetro -Form de Invoke-RestMethod, que solo
# existe en PowerShell 7+ y no en Windows PowerShell 5.1, la versión que
# trae Windows por defecto). Esto funciona igual en 5.1 y en 7+.
function Send-MultipartFile {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][hashtable]$Headers
  )
  Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

  $httpClient = [System.Net.Http.HttpClient]::new()
  try {
    foreach ($key in $Headers.Keys) {
      $httpClient.DefaultRequestHeaders.TryAddWithoutValidation($key, $Headers[$key]) | Out-Null
    }

    $fileStream = [System.IO.File]::OpenRead($FilePath)
    try {
      $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
      $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")

      $multipartContent = [System.Net.Http.MultipartFormDataContent]::new()
      $multipartContent.Add($fileContent, "file", [System.IO.Path]::GetFileName($FilePath))

      $response = $httpClient.PostAsync($Url, $multipartContent).GetAwaiter().GetResult()
      $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

      if (-not $response.IsSuccessStatusCode) {
        throw "HTTP $([int]$response.StatusCode) subiendo archivo a VirusTotal: $body"
      }
      return ($body | ConvertFrom-Json)
    } finally {
      $fileStream.Dispose()
    }
  } finally {
    $httpClient.Dispose()
  }
}

function Get-LatestGitHubReleaseAsset {
  param(
    [Parameter(Mandatory)][string]$Owner,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$AssetPattern   # regex contra el nombre del asset (ej. instalador x64, excluyendo arm64)
  )
  $url = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  $json = Get-JsonFromUrl -Url $url -Headers @{ "Accept" = "application/vnd.github+json" }
  $ver = $json.tag_name -replace '^v', ''
  $asset = $json.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
  if (-not $asset) { throw "No se encontró ningún asset que coincida con '$AssetPattern' en el release $($json.tag_name) de $Owner/$Repo." }
  [pscustomobject]@{ Version = $ver; DownloadUrl = $asset.browser_download_url; AssetName = $asset.name }
}

function Extract-RegexFirstGroup {
  param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Pattern)
  $m = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $m.Success -or $m.Groups.Count -lt 2) { throw "No match for pattern: $Pattern" }
  $m.Groups[1].Value.Trim()
}

function New-VersionResult {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$LatestVersion = "N/A",
    [string]$Source = "N/A",
    [string]$Notes = ""
  )
  if ([string]::IsNullOrWhiteSpace($LatestVersion)) { $LatestVersion = "N/A" }
  if ([string]::IsNullOrWhiteSpace($Source))       { $Source       = "N/A" }
  [pscustomobject]@{
    Name          = $Name
    LatestVersion = $LatestVersion
    Source        = $Source
    RetrievedUtc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Notes         = $Notes
  }
}

function Safe-Run {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Block, [string]$Source = "N/A")
  if ([string]::IsNullOrWhiteSpace($Source)) { $Source = "N/A" }
  try { & $Block }
  catch { New-VersionResult -Name $Name -LatestVersion "N/A" -Source $Source -Notes ("ERROR: " + $_.Exception.Message) }
}

# ============================================================
# RESOLVERS DE VERSIÓN OFICIAL (del script original)
# ============================================================

function Get-LatestChromeStableWin64 {
  $url = "https://versionhistory.googleapis.com/v1/chrome/platforms/win64/channels/stable/versions/all/releases?order_by=version%20desc&page_size=1"
  $ver = (Get-JsonFromUrl -Url $url).releases[0].version
  New-VersionResult -Name "Google Chrome (Standalone) - Stable (Win64)" -LatestVersion $ver -Source $url
}

function Get-LatestFirefox {
  $url = "https://product-details.mozilla.org/1.0/firefox_versions.json"
  $ver = (Get-JsonFromUrl -Url $url).LATEST_FIREFOX_VERSION
  New-VersionResult -Name "Mozilla Firefox (Standalone) - Latest" -LatestVersion $ver -Source $url
}

function Get-LatestCyberArkEpmAgents {
  $url = "https://docs.cyberark.com/epm/latest/en/content/release%20notes/rn-rollout-status.htm"
  $html = Get-TextFromUrl -Url $url
  $versions = [regex]::Matches($html, "\b([0-9]{2}\.[0-9]{1,2}\.[0-9]{1,3})\b", "IgnoreCase") |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  if (-not $versions -or $versions.Count -eq 0) { throw "No se encontraron versiones en rn-rollout-status.htm." }
  $latest = ($versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
  New-VersionResult -Name "CyberArk EPM - Latest Agent Version (from rollout status)" -LatestVersion $latest -Source $url -Notes "Descarga requiere acceso al Download Center (portal con login)."
}

function Get-LatestKeePass {
  $url = "https://keepass.info/download.html"
  $html = Get-TextFromUrl -Url $url
  $verTail = Extract-RegexFirstGroup -Text $html -Pattern "KeePass\s*2\.(\d+(\.\d+)*)"
  $ver = if ($verTail -match "^2\.") { $verTail } else { "2.$verTail" }
  New-VersionResult -Name "KeePass" -LatestVersion $ver -Source $url
}

function Get-LatestLibreOffice {
  $url = "https://download.documentfoundation.org/libreoffice/stable/"
  $html = Get-TextFromUrl -Url $url
  $versions = [regex]::Matches($html, 'href="([0-9]+\.[0-9]+\.[0-9]+)/"') |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  if (-not $versions -or $versions.Count -eq 0) { throw "No se encontraron carpetas de versión en el índice del mirror oficial." }
  $latest = ($versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
  New-VersionResult -Name "LibreOffice" -LatestVersion $latest -Source $url -Notes "Versión leída directo del índice del mirror oficial (más confiable que la página de marketing, que a veces mezcla varias versiones)."
}

function Get-LatestWinSCP {
  $url = "https://winscp.net/eng/download.php"
  $html = Get-TextFromUrl -Url $url
  $ver = $null
  foreach ($p in @(
      "Download\s+WinSCP\s+([0-9]+\.[0-9]+(\.[0-9]+)*)",
      "WinSCP\s+([0-9]+\.[0-9]+(\.[0-9]+)*)\s+Download",
      "WinSCP\s+([0-9]+\.[0-9]+(\.[0-9]+)*)")) {
    try { $ver = Extract-RegexFirstGroup -Text $html -Pattern $p; if ($ver) { break } } catch {}
  }
  if (-not $ver) { throw "No se pudo extraer versión de la página oficial." }
  New-VersionResult -Name "WinSCP" -LatestVersion $ver -Source $url
}

function Get-LatestWinMerge {
  $r = Get-LatestGitHubReleaseAsset -Owner "WinMerge" -Repo "winmerge" -AssetPattern '-x64-Setup\.exe$'
  New-VersionResult -Name "WinMerge" -LatestVersion $r.Version -Source "https://api.github.com/repos/WinMerge/winmerge/releases/latest"
}

function Get-Latest7Zip {
  $url = "https://www.7-zip.org/download.html"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "Download\s+7-Zip\s+([0-9]+\.[0-9]+)"
  New-VersionResult -Name "7-Zip" -LatestVersion $ver -Source $url
}

function Get-LatestBizagiModeler {
  $url = "https://releasenotes.bizagi.com/en/release-notes/releases/all-releases"
  $html = Get-TextFromUrl -Url $url
  $versions = [regex]::Matches($html, "Modeler\s+version\s+([0-9]+\.[0-9]+)", "IgnoreCase") |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  if (-not $versions -or $versions.Count -eq 0) { throw "No se encontró 'Modeler version x.y'." }
  $latest = ($versions | Sort-Object { [version]($_ + ".0") } -Descending | Select-Object -First 1)
  New-VersionResult -Name "Bizagi Modeler (Latest from Bizagi Release Notes)" -LatestVersion $latest -Source $url -Notes "Descarga requiere portal Bizagi (login)."
}

function Get-LatestSoapUI {
  $url = "https://www.soapui.org/downloads/latest-release/"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "Version\s*([0-9]+\.[0-9]+\.[0-9]+)"
  New-VersionResult -Name "SoapUI (Latest)" -LatestVersion $ver -Source $url
}

function Get-LatestKLite {
  $url = "https://codecguide.com/"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "K-Lite\s+Codec\s+Pack\s+([0-9]+\.[0-9]+\.[0-9]+)"
  New-VersionResult -Name "K-Lite Codec Pack" -LatestVersion $ver -Source $url
}

function Get-LatestNodeJs {
  $url = "https://nodejs.org/dist/index.json"
  $json = Get-JsonFromUrl -Url $url
  function Parse-SemVer([string]$v) { [version]($v.TrimStart("v")) }
  $sorted = @($json) | Sort-Object @{ Expression = { Parse-SemVer $_.version }; Descending = $true }
  $latestCurrent  = $sorted[0].version.TrimStart("v")
  $latestLtsEntry = $sorted | Where-Object { $_.lts -and $_.lts -ne $false } | Select-Object -First 1
  $latestLts      = if ($latestLtsEntry) { $latestLtsEntry.version.TrimStart("v") } else { "N/A" }
  @(
    New-VersionResult -Name "Node.js (Current)" -LatestVersion $latestCurrent -Source $url
    New-VersionResult -Name "Node.js (LTS per official index.json)" -LatestVersion $latestLts -Source $url -Notes "LTS depende del campo 'lts' del index oficial."
  )
}

function Get-LatestDockerDesktopWinAmd64 {
  $url = "https://desktop.docker.com/win/main/amd64/appcast.xml"
  $xmlText = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $xmlText -Pattern 'sparkle:shortVersionString="([^"]+)"'
  New-VersionResult -Name "Docker Desktop (Windows AMD64)" -LatestVersion $ver -Source $url
}

function Get-LatestPythonWindows {
  $url = "https://www.python.org/downloads/windows/"
  $html = Get-TextFromUrl -Url $url
  $py  = Extract-RegexFirstGroup -Text $html -Pattern "Latest\s+Python\s+3\s+Release\s*-\s*Python\s+([0-9]+\.[0-9]+\.[0-9]+)"
  $mgr = Extract-RegexFirstGroup -Text $html -Pattern "Latest\s+Python\s+install\s+manager\s*-\s*Python\s+install\s+manager\s*([0-9]+\.[0-9]+)"
  @(
    New-VersionResult -Name "Python (Latest 3.x for Windows)" -LatestVersion $py -Source $url
    New-VersionResult -Name "Python install manager (Windows)" -LatestVersion $mgr -Source $url -Notes "Formato .msix (no .msi): se instala con Add-AppxPackage o doble clic, no con msiexec. Fuente del paquete: github.com/python/pymanager."
  )
}

function Get-PythonLauncherLocal {
  try {
    $out = & py -V 2>&1
    $ver = Extract-RegexFirstGroup -Text ($out | Out-String) -Pattern "Python\s+([0-9]+\.[0-9]+\.[0-9]+)"
    New-VersionResult -Name "Python Launcher (local py.exe -> reports Python)" -LatestVersion $ver -Source "local:py -V" -Notes "Valida lo instalado localmente."
  } catch {
    New-VersionResult -Name "Python Launcher (local py.exe -> reports Python)" -LatestVersion "N/A" -Source "local:py -V" -Notes "py.exe no disponible o no está en PATH."
  }
}

function Get-DCNetDocumentControlBackoffice {
  $url = "https://dcnet.ec/brochures/DocumentControlBackOffice.pdf"
  New-VersionResult -Name "DCNet Document Control Backoffice" -LatestVersion "N/A" -Source $url -Notes "No hay 'latest version' pública; se obtiene vía portal/soporte del proveedor."
}

function Get-LatestAdobeAcrobatReaderContinuous {
  # Fuente oficial del Acrobat Enterprise Toolkit (más confiable para IT que la
  # página de release notes de consumo), confirmada por el fabricante.
  $url = "https://www.adobe.com/devnet-docs/acrobatetk/tools/ReleaseNotesDC/index.html"
  $html = Get-TextFromUrl -Url $url
  # Adobe cambió su esquema de versión a uno basado en año (ej. 2026.001.21662)
  # en vez del viejo formato de 2 dígitos (ej. 24.003.20269); se acepta 2 a 4
  # dígitos en el primer grupo para cubrir ambos esquemas.
  $versions = [regex]::Matches($html, "\b([0-9]{2,4}\.[0-9]{3}\.[0-9]{5})\b") |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  if (-not $versions -or $versions.Count -eq 0) { throw "No se encontraron versiones en release notes oficiales." }
  $latest = ($versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
  New-VersionResult -Name "Adobe Acrobat Reader (Continuous track - latest)" -LatestVersion $latest -Source $url
}

function Get-LatestAndroidStudio {
  $url = "https://developer.android.com/studio"
  $html = Get-TextFromUrl -Url $url
  $ver = $null
  foreach ($p in @(
      "Android\s+Studio[^0-9]*\|\s*([0-9]{4}\.[0-9]+\.[0-9]+(\.[0-9]+)?)",
      "\b([0-9]{4}\.[0-9]+\.[0-9]+(\.[0-9]+)?)\b")) {
    try { $ver = Extract-RegexFirstGroup -Text $html -Pattern $p; if ($ver) { break } } catch {}
  }
  if (-not $ver) { throw "No se pudo extraer versión (HTML dinámico o cambió el layout)." }
  New-VersionResult -Name "Android Studio (latest shown on official site)" -LatestVersion $ver -Source $url
}

function Get-LatestGitForWindows {
  $r = Get-LatestGitHubReleaseAsset -Owner "git-for-windows" -Repo "git" -AssetPattern '^Git-[\d\.]+-64-bit\.exe$'
  New-VersionResult -Name "Git (latest from git-scm.com)" -LatestVersion $r.Version -Source "https://api.github.com/repos/git-for-windows/git/releases/latest" -Notes "Descarga desde GitHub Releases oficial de git-for-windows/git."
}

function Get-LatestPowerBIDesktop {
  $url = "https://learn.microsoft.com/en-us/power-bi/fundamentals/desktop-change-log"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "Version\s+(2\.[0-9]+\.[0-9]+\.[0-9]+)"
  New-VersionResult -Name "Microsoft Power BI Desktop (latest from change log)" -LatestVersion $ver -Source $url -Notes "Microsoft distribuye un único instalador multi-idioma (no hay versión 'en español' separada); el idioma con el que abre depende de la configuración regional/idioma de Windows del equipo donde se instale, no del archivo descargado."
}

function Get-LatestOpenJDK {
  # Eclipse Temurin (proyecto Adoptium): distribución de referencia de OpenJDK,
  # con API pública estable que incluye checksum SHA256 oficial del instalador.
  $availUrl = "https://api.adoptium.net/v3/info/available_releases"
  $avail = Get-JsonFromUrl -Url $availUrl
  $lts = $avail.most_recent_lts
  $assetsUrl = "https://api.adoptium.net/v3/assets/latest/$lts/hotspot?image_type=jdk&os=windows&architecture=x64"
  $assets = Get-JsonFromUrl -Url $assetsUrl
  $msiAsset = $assets | Where-Object { $_.binary.installer.name -match '\.msi$' } | Select-Object -First 1
  if (-not $msiAsset) { throw "No se encontró paquete MSI de Temurin JDK $lts para Windows x64." }
  $ver = $msiAsset.version.semver
  if ($msiAsset.binary.installer.checksum) {
    $script:OfficialHashes["OpenJDK (Eclipse Temurin, LTS más reciente, Windows x64 MSI)"] = $msiAsset.binary.installer.checksum.ToLower()
  }
  New-VersionResult -Name "OpenJDK (Eclipse Temurin, LTS más reciente, Windows x64 MSI)" -LatestVersion $ver -Source $assetsUrl -Notes "LTS actual: $lts. sha256 oficial (Adoptium): $($msiAsset.binary.installer.checksum)"
}

function Get-LatestPowerAutomateDesktop {
  # Microsoft no publica una URL de descarga directa estable para Power Automate
  # for Desktop: se distribuye vía winget (Microsoft Store package). Se resuelve
  # la versión con el propio winget como fuente de verdad.
  if (-not (Test-WingetAvailable)) { throw "winget no está disponible para resolver la versión de Power Automate for Desktop." }
  $out = (& winget show --id Microsoft.PowerAutomateDesktop --source winget 2>&1 | Out-String)
  # "Version" o "Versión": winget muestra la etiqueta traducida si Windows
  # está configurado en español, y el regex original solo cubría inglés.
  $ver = Extract-RegexFirstGroup -Text $out -Pattern "Versi[oó]n:\s*([0-9]+(?:\.[0-9]+)*)"
  New-VersionResult -Name "Power Automate for Desktop" -LatestVersion $ver -Source "winget show Microsoft.PowerAutomateDesktop" -Notes "Se instala/descarga vía winget; Microsoft no publica una URL de descarga directa pública. Es un único instalador multi-idioma: el idioma con el que abre depende de la configuración regional/idioma de Windows del equipo, no del archivo descargado."
}

function Get-LatestNotepadPlusPlus {
  $r = Get-LatestGitHubReleaseAsset -Owner "notepad-plus-plus" -Repo "notepad-plus-plus" -AssetPattern '^npp\.[\d.]+\.Installer\.x64\.exe$'
  New-VersionResult -Name "Notepad++ (x64)" -LatestVersion $r.Version -Source "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest"
}

function Get-LatestDotNetSdk {
  # Índice oficial de releases de .NET (dotnet/core en GitHub). .NET no publica
  # un .msi independiente para el SDK: usa un bootstrapper .exe oficial que
  # contiene los MSI de los componentes por dentro.
  $indexUrl = "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
  $index = Get-JsonFromUrl -Url $indexUrl
  $ltsChannel = $index.'releases-index' |
    Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
    Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
  if (-not $ltsChannel) { throw "No se encontró un canal LTS activo en releases-index.json." }
  $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
  $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
  $sdkFile = $latestRelease.sdk.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1
  if (-not $sdkFile) { throw "No se encontró instalador win-x64 .exe del SDK de .NET en el canal $($ltsChannel.'channel-version')." }
  New-VersionResult -Name ".NET SDK (LTS más reciente, win-x64)" -LatestVersion $latestRelease.sdk.version -Source $ltsChannel.'releases.json' -Notes "Canal LTS: $($ltsChannel.'channel-version'). .NET no publica .msi independiente para el SDK (bootstrapper .exe oficial)."
}

function Get-LatestVSProfessional2026 {
  # Visual Studio usa un bootstrapper pequeño (pocos MB) que durante la
  # instalación real descarga los workloads seleccionados (GBs) desde
  # internet. Este script valida el bootstrapper, no el payload completo.
  New-VersionResult -Name "Visual Studio Professional 2026 (bootstrapper)" -LatestVersion "18.x (canal Stable)" -Source "https://aka.ms/vs/18/Stable/vs_professional.exe" -Notes "El bootstrapper descarga los workloads seleccionados durante la instalación; VT/Defender solo validan el bootstrapper, no el payload completo descargado después."
}

function Get-LatestVSEnterprise2026 {
  New-VersionResult -Name "Visual Studio Enterprise 2026 (bootstrapper)" -LatestVersion "18.x (canal Stable)" -Source "https://aka.ms/vs/18/Stable/vs_enterprise.exe" -Notes "El bootstrapper descarga los workloads seleccionados durante la instalación; VT/Defender solo validan el bootstrapper, no el payload completo descargado después."
}

function Get-SentinelOneNote {
  # SentinelOne NO publica un instalador público: se descarga desde la consola
  # de administración del tenant (login + Site Token específico por sitio).
  New-VersionResult -Name "SentinelOne (agente)" -LatestVersion "N/A" -Source "https://<tu-tenant>.sentinelone.net" -Notes "Requiere iniciar sesión en la consola de administración de SentinelOne del tenant y descargar el instalador MSI firmado con el Site Token del sitio correspondiente. No existe URL de descarga pública."
}

function Get-TRSuiteNote {
  # TRSuite (trsuite.ch) es software de reportería fiscal FATCA/CRS de pago;
  # la descarga (incluida la prueba de 10 días) se obtiene vía el portal del
  # fabricante, no mediante una URL pública estable.
  New-VersionResult -Name "TRSuite (FATCA/CRS)" -LatestVersion "N/A" -Source "https://www.trsuite.ch/downloads.html" -Notes "Software licenciado; la descarga se obtiene desde el portal del fabricante (trsuite.ch), sin URL pública estable ni API de versión."
}

# ============================================================
# NUEVO: Visual Studio Code y LucenTime Timeline
# ============================================================

function Get-LatestVSCode {
  # API oficial de actualizaciones de VS Code
  $url = "https://update.code.visualstudio.com/api/update/win32-x64/stable/latest"
  $json = Get-JsonFromUrl -Url $url
  # Antes solo se guardaba en Notes como texto; ahora se registra para que
  # Process-Application compare el hash del archivo descargado contra este
  # valor oficial antes de aceptar la descarga.
  if ($json.sha256hash) { $script:OfficialHashes["Visual Studio Code (stable, win32-x64)"] = $json.sha256hash.ToLower() }
  New-VersionResult -Name "Visual Studio Code (stable, win32-x64)" -LatestVersion $json.productVersion -Source $url -Notes "sha256 oficial: $($json.sha256hash)"
}

function Get-LatestLucenTime {
  # Confirmado por el fabricante: URL fija de "latest" (no requiere resolver versión para descargar),
  # y página de historial de versiones para saber qué versión es.
  $url = "https://www.lucensoftware.com/products/timeline/updates"
  try {
    $html = Get-TextFromUrl -Url $url
    $ver = Extract-RegexFirstGroup -Text $html -Pattern "Version:(?:(?!\d)[\s\S]){0,300}?([0-9]+\.[0-9]+\.[0-9]+)"
    New-VersionResult -Name "LucenTime Timeline" -LatestVersion $ver -Source $url
  } catch {
    New-VersionResult -Name "LucenTime Timeline" -LatestVersion "N/A" -Source $url -Notes "No se pudo leer la versión desde la página de historial (cambió el layout), pero la descarga sí funciona vía URL fija 'latest'."
  }
}

function Get-LatestDrawIO {
  $r = Get-LatestGitHubReleaseAsset -Owner "jgraph" -Repo "drawio-desktop" -AssetPattern '^draw\.io-[\d\.]+-windows-installer\.exe$'
  New-VersionResult -Name "draw.io Desktop" -LatestVersion $r.Version -Source "https://api.github.com/repos/jgraph/drawio-desktop/releases/latest"
}

function Get-LatestZuluJDK {
  # Azul Metadata API oficial (sin autenticación), JDK 21 LTS, Windows x64, MSI, build CA (Community)
  $url = "https://api.azul.com/metadata/v1/zulu/packages/?java_version=21&os=windows&arch=x64&archive_type=msi&java_package_type=jdk&javafx_bundled=false&release_status=ga&availability_types=CA&latest=true&page=1&page_size=1"
  $json = Get-JsonFromUrl -Url $url
  if (-not $json -or $json.Count -eq 0) { throw "La API de Azul no devolvió resultados para JDK 21 Windows x64 MSI." }
  $pkg = $json[0]
  $ver = ($pkg.java_version -join ".")
  New-VersionResult -Name "Zulu JDK 21 (Windows x64 MSI)" -LatestVersion $ver -Source $url -Notes "distro_version (build Zulu): $($pkg.distro_version -join '.')"
}

function Get-LatestWireshark {
  $url = "https://www.wireshark.org/update/0/Wireshark/0.0.0/Windows/x86-64/en-US/stable.xml"
  $xmlText = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $xmlText -Pattern 'sparkle:shortVersionString="([^"]+)"'
  New-VersionResult -Name "Wireshark" -LatestVersion $ver -Source $url
}

function Get-LatestILSpy {
  $r = Get-LatestGitHubReleaseAsset -Owner "icsharpcode" -Repo "ILSpy" -AssetPattern '^ILSpy_Installer_(?!.*arm64).*\.msi$'
  New-VersionResult -Name "ILSpy" -LatestVersion $r.Version -Source "https://api.github.com/repos/icsharpcode/ILSpy/releases/latest"
}

function Get-LatestPuTTY {
  # Página oficial de PuTTY: listado del directorio "latest" para Windows 64-bit,
  # que expone el nombre del instalador MSI con la versión en el nombre.
  $url = "https://the.earth.li/~sgtatham/putty/latest/w64/"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "putty-64bit-([0-9]+\.[0-9]+)-installer\.msi"
  New-VersionResult -Name "PuTTY (64-bit)" -LatestVersion $ver -Source $url
}

function Get-LatestNmap {
  # Nmap NO publica instalador .msi para Windows, solo .exe (NSIS) firmado por el proyecto.
  $url = "https://nmap.org/download.html"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern "nmap-([0-9]+\.[0-9]+)-setup\.exe"
  New-VersionResult -Name "Nmap" -LatestVersion $ver -Source $url -Notes "Nmap solo distribuye .exe para Windows (no hay .msi oficial)."
}

function Get-ThinkCellNote {
  # think-cell requiere licencia comercial (solo trial gratuito con límite de tiempo) y no publica
  # un instalador de descarga pública sin cuenta/licencia asociada. No se automatiza por diseño.
  New-VersionResult -Name "think-cell" -LatestVersion "N/A" -Source "https://www.think-cell.com" -Notes "Requiere licencia comercial (solo hay prueba gratuita limitada). Descarga y activación deben hacerse manualmente desde el portal de think-cell con la licencia de la organización."
}

function Get-ACLForWindowsNote {
  # ACL for Windows (Diligent One / HighBond) es software por suscripción: el
  # instalador solo se obtiene tras iniciar sesión en el portal del cliente.
  New-VersionResult -Name "ACL for Windows (Diligent One)" -LatestVersion "N/A" -Source "https://www.diligentoneplatform.com" -Notes "Software por suscripción; el instalador (ACLforWindows*.exe) se descarga desde el portal Diligent One / HighBond tras iniciar sesión con la cuenta de la organización. No hay URL de descarga pública."
}

function Get-TeamMateNote {
  # TeamMate+ / TeamMate Analytics (Wolters Kluwer) es software de auditoría
  # licenciado; la descarga se obtiene desde el portal de soporte del cliente,
  # no mediante una URL pública estable.
  New-VersionResult -Name "TeamMate (Wolters Kluwer)" -LatestVersion "N/A" -Source "https://www.wolterskluwer.com/en/solutions/teammate" -Notes "Software de auditoría licenciado (Wolters Kluwer); la descarga se obtiene desde el portal de soporte del cliente. No hay URL de descarga pública. Confirmar si se refiere a TeamMate+ (workpapers) o TeamMate Analytics."
}

function Get-LatestAESCryptOpenSource {
  $r = Get-LatestGitHubReleaseAsset -Owner "terrapane" -Repo "aescrypt_win" -AssetPattern '(?i)\.(exe|msi)$'
  New-VersionResult -Name "AES Crypt (open-source, GitHub)" -LatestVersion $r.Version -Source "https://api.github.com/repos/terrapane/aescrypt_win/releases/latest" -Notes "Build open-source (GPL) mantenido por terrapane, distinto de la versión comercial de aescrypt.com."
}

function Get-LatestAESCryptCommercial {
  # aescrypt.com distribuye un .zip con aescrypt.exe (no un instalador con
  # asistente); no requiere cuenta para la prueba de 30 días, pero el patrón
  # de URL exacto no está confirmado por el fabricante en una API pública
  # (se extrae por scraping best-effort; verificar si la página cambia).
  New-VersionResult -Name "AES Crypt (comercial, aescrypt.com)" -LatestVersion "latest" -Source "https://www.aescrypt.com/download/" -Notes "Distribución comercial (prueba de 30 días, sin cuenta requerida para descargar); paquete .zip con aescrypt.exe portable, no instalador tradicional. URL exacta resuelta por scraping best-effort."
}

function Get-LatestAngularCli {
  $json = Get-JsonFromUrl -Url "https://registry.npmjs.org/@angular/cli/latest"
  New-VersionResult -Name "Angular CLI (paquete npm)" -LatestVersion $json.version -Source "https://registry.npmjs.org/@angular/cli/latest" -Notes "Se instala con 'npm install -g @angular/cli' (requiere Node.js, ya cubierto en este catálogo). Este script descarga y valida el tarball .tgz oficial publicado en el registro de npm, no un instalador tradicional."
}

function Get-LatestIntelliJIdeaCommunity {
  # API pública oficial de JetBrains (Data Services) para resolver la última versión.
  $url = "https://data.services.jetbrains.com/products/releases?code=IIC&latest=true&type=release"
  $json = Get-JsonFromUrl -Url $url
  $release = $json.IIC[0]
  New-VersionResult -Name "IntelliJ IDEA Community Edition" -LatestVersion $release.version -Source $url
}

function Get-LatestJetBrainsDotPeek {
  $url = "https://data.services.jetbrains.com/products/releases?code=DPK&latest=true&type=release"
  $json = Get-JsonFromUrl -Url $url
  $release = $json.DPK[0]
  New-VersionResult -Name "JetBrains dotPeek" -LatestVersion $release.version -Source $url
}

function Get-LatestGradle {
  $json = Get-JsonFromUrl -Url "https://services.gradle.org/versions/current"
  New-VersionResult -Name "Gradle (bin.zip)" -LatestVersion $json.version -Source "https://services.gradle.org/versions/current" -Notes "Gradle se distribuye como .zip (no hay .exe/.msi oficial)."
}

function Get-LatestRForWindows {
  # Índice oficial de CRAN para el instalador base de R en Windows.
  $url = "https://cran.r-project.org/bin/windows/base/"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern 'href="R-([0-9]+\.[0-9]+\.[0-9]+)-win\.exe"'
  New-VersionResult -Name "R for Windows" -LatestVersion $ver -Source $url
}

function Get-LatestRStudioDesktop {
  $url = "https://posit.co/download/rstudio-desktop/"
  $html = Get-TextFromUrl -Url $url
  $ver = Extract-RegexFirstGroup -Text $html -Pattern 'RStudio-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)\.exe'
  New-VersionResult -Name "RStudio Desktop" -LatestVersion $ver -Source $url -Notes "Edición open-source gratuita (existe una edición Pro/comercial aparte)."
}

function Get-LatestAzureConnectedMachineAgent {
  New-VersionResult -Name "Azure Connected Machine Agent" -LatestVersion "latest" -Source "https://aka.ms/AzureConnectedMachineAgent" -Notes "URL fija oficial de Microsoft (Azure Arc) que siempre resuelve al MSI más reciente; no expone un número de versión antes de descargar."
}

function Get-LatestDotNetAspNetCoreRuntime {
  $indexUrl = "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
  $index = Get-JsonFromUrl -Url $indexUrl
  $ltsChannel = $index.'releases-index' |
    Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
    Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
  if (-not $ltsChannel) { throw "No se encontró un canal LTS activo en releases-index.json." }
  $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
  $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
  $file = $latestRelease.'aspnetcore-runtime'.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1
  if (-not $file) { throw "No se encontró instalador win-x64 .exe de ASP.NET Core Runtime en el canal $($ltsChannel.'channel-version')." }
  New-VersionResult -Name "ASP.NET Core Runtime (LTS más reciente, win-x64)" -LatestVersion $latestRelease.'aspnetcore-runtime'.'version-display' -Source $ltsChannel.'releases.json' -Notes "Canal LTS: $($ltsChannel.'channel-version')."
}

function Get-LatestDotNetRuntime {
  $indexUrl = "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
  $index = Get-JsonFromUrl -Url $indexUrl
  $ltsChannel = $index.'releases-index' |
    Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
    Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
  if (-not $ltsChannel) { throw "No se encontró un canal LTS activo en releases-index.json." }
  $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
  $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
  $file = $latestRelease.runtime.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1
  if (-not $file) { throw "No se encontró instalador win-x64 .exe del .NET Runtime en el canal $($ltsChannel.'channel-version')." }
  New-VersionResult -Name ".NET Runtime (LTS más reciente, win-x64)" -LatestVersion $latestRelease.runtime.version -Source $ltsChannel.'releases.json' -Notes "Canal LTS: $($ltsChannel.'channel-version')."
}

function Get-LatestDotNetHostingBundle {
  $indexUrl = "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
  $index = Get-JsonFromUrl -Url $indexUrl
  $ltsChannel = $index.'releases-index' |
    Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
    Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
  if (-not $ltsChannel) { throw "No se encontró un canal LTS activo en releases-index.json." }
  $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
  $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
  $file = $latestRelease.'aspnetcore-runtime'.files | Where-Object { $_.name -match '(?i)hosting.*\.exe$' } | Select-Object -First 1
  if (-not $file) { throw "No se encontró el .NET Hosting Bundle en el canal $($ltsChannel.'channel-version')." }
  New-VersionResult -Name ".NET Hosting Bundle (LTS más reciente)" -LatestVersion $latestRelease.'aspnetcore-runtime'.'version-display' -Source $ltsChannel.'releases.json' -Notes "Canal LTS: $($ltsChannel.'channel-version'). Incluye el módulo ASP.NET Core para IIS."
}

function Get-LatestVSProfessional2022 {
  New-VersionResult -Name "Visual Studio Professional 2022 (bootstrapper)" -LatestVersion "17.x (canal release)" -Source "https://aka.ms/vs/17/release/vs_professional.exe" -Notes "El bootstrapper descarga los workloads seleccionados durante la instalación; VT/Defender solo validan el bootstrapper, no el payload completo descargado después."
}

function Get-LatestVSEnterprise2022 {
  New-VersionResult -Name "Visual Studio Enterprise 2022 (bootstrapper)" -LatestVersion "17.x (canal release)" -Source "https://aka.ms/vs/17/release/vs_enterprise.exe" -Notes "El bootstrapper descarga los workloads seleccionados durante la instalación; VT/Defender solo validan el bootstrapper, no el payload completo descargado después."
}

function Get-LatestAraxisMerge {
  # Araxis publica soporte oficial de winget; se resuelve la versión con el propio winget.
  if (-not (Test-WingetAvailable)) { throw "winget no está disponible para resolver la versión de Araxis Merge." }
  $out = (& winget show --id Araxis.Merge --source winget 2>&1 | Out-String)
  # "Version" o "Versión": winget muestra la etiqueta traducida si Windows
  # está configurado en español, y el regex original solo cubría inglés.
  $ver = Extract-RegexFirstGroup -Text $out -Pattern "Versi[oó]n:\s*([0-9]+(?:\.[0-9]+)*)"
  New-VersionResult -Name "Araxis Merge" -LatestVersion $ver -Source "winget show Araxis.Merge"
}

function Get-LatestNvmWindows {
  $r = Get-LatestGitHubReleaseAsset -Owner "coreybutler" -Repo "nvm-windows" -AssetPattern '^nvm-setup\.exe$'
  New-VersionResult -Name "nvm-windows" -LatestVersion $r.Version -Source "https://api.github.com/repos/coreybutler/nvm-windows/releases/latest"
}

function Get-LatestFigma {
  # Figma se autoactualiza y no publica un número de versión previo a la
  # descarga; la URL de "latest" es estable y confirmada por el fabricante.
  New-VersionResult -Name "Figma (desktop)" -LatestVersion "latest" -Source "https://desktop.figma.com/win/FigmaSetup.exe" -Notes "Instalador autoactualizable; Figma no publica número de versión antes de descargar."
}

function Get-LatestPostman {
  New-VersionResult -Name "Postman" -LatestVersion "latest" -Source "https://dl.pstmn.io/download/latest/win64" -Notes "Instalador autoactualizable; Postman no publica número de versión antes de descargar."
}

# ============================================================
# RESOLUCIÓN DE URL DE DESCARGA DIRECTA POR APP
# Cada resolver recibe la versión resuelta y devuelve la URL del instalador
# oficial, o $null si no hay patrón de descarga directa conocido (portal/login).
# ============================================================

$script:DownloadResolvers = @{

  "Google Chrome (Standalone) - Stable (Win64)" = { param($v)
    "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi" }

  "Mozilla Firefox (Standalone) - Latest" = { param($v)
    "https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=es-MX" }  # MSI oficial en español latam (confirmado por firefox.com/es-ES/download/all/desktop-release/win64-msi/es-MX/)

  "KeePass" = { param($v)
    "https://sourceforge.net/projects/keepass/files/KeePass%202.x/$v/KeePass-$v-Setup.exe/download" }

  "LibreOffice" = { param($v)
    "https://download.documentfoundation.org/libreoffice/stable/$v/win/x86_64/LibreOffice_${v}_Win_x86-64.msi" }

  "WinSCP" = { param($v)
    "https://winscp.net/download/WinSCP-$v-Setup.exe" }

  "WinMerge" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "WinMerge" -Repo "winmerge" -AssetPattern '-x64-Setup\.exe$').DownloadUrl }

  "7-Zip" = { param($v)
    $vNoDot = $v -replace "\.", ""
    "https://www.7-zip.org/a/7z${vNoDot}-x64.exe" }

  "SoapUI (Latest)" = { param($v)
    "https://dl.eviware.com/soapuios/$v/SoapUI-x64-$v.exe" }

  "Node.js (Current)" = { param($v) "https://nodejs.org/dist/v$v/node-v$v-x64.msi" }
  "Node.js (LTS per official index.json)" = { param($v) "https://nodejs.org/dist/v$v/node-v$v-x64.msi" }

  "Docker Desktop (Windows AMD64)" = { param($v)
    "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" }

  "Python (Latest 3.x for Windows)" = { param($v)
    "https://www.python.org/ftp/python/$v/python-$v-amd64.exe" }

  "Git (latest from git-scm.com)" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "git-for-windows" -Repo "git" -AssetPattern '^Git-[\d\.]+-64-bit\.exe$').DownloadUrl }

  "Visual Studio Code (stable, win32-x64)" = { param($v)
    "https://update.code.visualstudio.com/latest/win32-x64/stable" }

  # Android Studio y Power BI Desktop NO están aquí: se resuelven vía winget ($script:WingetIds)
  # porque el fabricante no publica un patrón de URL directa predecible.
  "Adobe Acrobat Reader (Continuous track - latest)" = { param($v)
    $vNoDot = $v -replace "\.", ""
    "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/$vNoDot/AcroRdrDCx64${vNoDot}_es_MX.exe" }  # es_MX (español latam); si Adobe cambió el sufijo de idioma tras el rebranding 2026, verificar
  "K-Lite Codec Pack" = { param($v)
    $vNoDot = $v -replace "\.", ""
    "https://files2.codecguide.com/K-Lite_Codec_Pack_${vNoDot}_Standard.exe" }  # patrón oficial confirmado (variante Standard)
  "CyberArk EPM - Latest Agent Version (from rollout status)" = { param($v) $null }
  "Bizagi Modeler (Latest from Bizagi Release Notes)" = { param($v) $null }
  "DCNet Document Control Backoffice" = { param($v) $null }

  "LucenTime Timeline" = { param($v)
    "https://img.lucensoftware.com/website/content/download/install/latest/LucenTimeline.exe" }  # URL fija oficial de "latest", no depende de la versión

  "draw.io Desktop" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "jgraph" -Repo "drawio-desktop" -AssetPattern '^draw\.io-[\d\.]+-windows-installer\.exe$').DownloadUrl }

  "Zulu JDK 21 (Windows x64 MSI)" = { param($v)
    $url = "https://api.azul.com/metadata/v1/zulu/packages/?java_version=21&os=windows&arch=x64&archive_type=msi&java_package_type=jdk&javafx_bundled=false&release_status=ga&availability_types=CA&latest=true&page=1&page_size=1"
    $json = Get-JsonFromUrl -Url $url
    $json[0].download_url }

  "Wireshark" = { param($v)
    "https://2.na.dl.wireshark.org/win64/Wireshark-$v-x64.exe" }

  "ILSpy" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "icsharpcode" -Repo "ILSpy" -AssetPattern '^ILSpy_Installer_(?!.*arm64).*\.msi$').DownloadUrl }

  "PuTTY (64-bit)" = { param($v)
    "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-$v-installer.msi" }

  "Nmap" = { param($v)
    "https://nmap.org/dist/nmap-$v-setup.exe" }

  "OpenJDK (Eclipse Temurin, LTS más reciente, Windows x64 MSI)" = { param($v)
    $avail = Get-JsonFromUrl -Url "https://api.adoptium.net/v3/info/available_releases"
    $lts = $avail.most_recent_lts
    $assets = Get-JsonFromUrl -Url "https://api.adoptium.net/v3/assets/latest/$lts/hotspot?image_type=jdk&os=windows&architecture=x64"
    ($assets | Where-Object { $_.binary.installer.name -match '\.msi$' } | Select-Object -First 1).binary.installer.link }

  "Notepad++ (x64)" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "notepad-plus-plus" -Repo "notepad-plus-plus" -AssetPattern '^npp\.[\d.]+\.Installer\.x64\.exe$').DownloadUrl }

  ".NET SDK (LTS más reciente, win-x64)" = { param($v)
    $index = Get-JsonFromUrl -Url "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
    $ltsChannel = $index.'releases-index' |
      Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
      Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
    $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
    $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
    ($latestRelease.sdk.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1).url }

  "Visual Studio Professional 2026 (bootstrapper)" = { param($v)
    "https://aka.ms/vs/18/Stable/vs_professional.exe" }

  "Visual Studio Enterprise 2026 (bootstrapper)" = { param($v)
    "https://aka.ms/vs/18/Stable/vs_enterprise.exe" }

  "Python install manager (Windows)" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "python" -Repo "pymanager" -AssetPattern '(?i)\.msix$').DownloadUrl }

  "SentinelOne (agente)" = { param($v) $null }   # sin URL pública: requiere consola del tenant + Site Token
  "TRSuite (FATCA/CRS)" = { param($v) $null }    # software licenciado, descarga vía portal del fabricante
  "ACL for Windows (Diligent One)" = { param($v) $null }   # software por suscripción, sin URL pública
  "TeamMate (Wolters Kluwer)" = { param($v) $null }        # software de auditoría licenciado, portal de cliente

  "AES Crypt (open-source, GitHub)" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "terrapane" -Repo "aescrypt_win" -AssetPattern '(?i)\.(exe|msi)$').DownloadUrl }

  "AES Crypt (comercial, aescrypt.com)" = { param($v)
    $html = Get-TextFromUrl -Url "https://www.aescrypt.com/download/"
    $m = [regex]::Match($html, 'href="([^"]*[Ww]indows[^"]*\.zip)"')
    if (-not $m.Success) { throw "No se pudo extraer el link de descarga de Windows desde aescrypt.com/download/ (verificar manualmente)." }
    $href = $m.Groups[1].Value
    # La página puede usar un link relativo (ej. "/files/x.zip"); si no trae
    # el dominio completo, se completa con la base del sitio.
    if ($href -notmatch '^https?://') { $href = "https://www.aescrypt.com" + (if ($href.StartsWith('/')) { $href } else { "/$href" }) }
    $href }

  "Angular CLI (paquete npm)" = { param($v)
    (Get-JsonFromUrl -Url "https://registry.npmjs.org/@angular/cli/latest").dist.tarball }

  "IntelliJ IDEA Community Edition" = { param($v)
    $json = Get-JsonFromUrl -Url "https://data.services.jetbrains.com/products/releases?code=IIC&latest=true&type=release"
    $json.IIC[0].downloads.windows.link }

  "JetBrains dotPeek" = { param($v)
    $json = Get-JsonFromUrl -Url "https://data.services.jetbrains.com/products/releases?code=DPK&latest=true&type=release"
    $json.DPK[0].downloads.windows.link }

  "Gradle (bin.zip)" = { param($v)
    $json = Get-JsonFromUrl -Url "https://services.gradle.org/versions/current"
    $json.downloadUrl }

  "R for Windows" = { param($v)
    "https://cran.r-project.org/bin/windows/base/R-$v-win.exe" }

  "RStudio Desktop" = { param($v)
    "https://download1.rstudio.org/electron/windows/RStudio-$v.exe" }

  "Azure Connected Machine Agent" = { param($v)
    "https://aka.ms/AzureConnectedMachineAgent" }

  ".NET Runtime (LTS más reciente, win-x64)" = { param($v)
    $index = Get-JsonFromUrl -Url "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
    $ltsChannel = $index.'releases-index' |
      Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
      Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
    $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
    $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
    ($latestRelease.runtime.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1).url }

  "ASP.NET Core Runtime (LTS más reciente, win-x64)" = { param($v)
    $index = Get-JsonFromUrl -Url "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
    $ltsChannel = $index.'releases-index' |
      Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
      Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
    $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
    $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
    ($latestRelease.'aspnetcore-runtime'.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -match '\.exe$' } | Select-Object -First 1).url }

  ".NET Hosting Bundle (LTS más reciente)" = { param($v)
    $index = Get-JsonFromUrl -Url "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json"
    $ltsChannel = $index.'releases-index' |
      Where-Object { $_.'release-type' -eq 'lts' -and $_.'support-phase' -eq 'active' } |
      Sort-Object { [version]$_.'channel-version' } -Descending | Select-Object -First 1
    $releases = Get-JsonFromUrl -Url $ltsChannel.'releases.json'
    $latestRelease = $releases.releases | Sort-Object { [datetime]$_.'release-date' } -Descending | Select-Object -First 1
    ($latestRelease.'aspnetcore-runtime'.files | Where-Object { $_.name -match '(?i)hosting.*\.exe$' } | Select-Object -First 1).url }

  "Visual Studio Professional 2022 (bootstrapper)" = { param($v)
    "https://aka.ms/vs/17/release/vs_professional.exe" }

  "Visual Studio Enterprise 2022 (bootstrapper)" = { param($v)
    "https://aka.ms/vs/17/release/vs_enterprise.exe" }

  "nvm-windows" = { param($v)
    (Get-LatestGitHubReleaseAsset -Owner "coreybutler" -Repo "nvm-windows" -AssetPattern '^nvm-setup\.exe$').DownloadUrl }

  "Figma (desktop)" = { param($v)
    "https://desktop.figma.com/win/FigmaSetup.exe" }

  "Postman" = { param($v)
    "https://dl.pstmn.io/download/latest/win64" }

  "think-cell" = { param($v) $null }   # requiere licencia comercial, no publica instalador de descarga pública sin cuenta
}

function Get-InstallerDownloadUrl {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version)
  if ($script:DownloadResolvers.ContainsKey($Name)) {
    return (& $script:DownloadResolvers[$Name] $Version)
  }
  return $null
}

function Test-WingetAvailable {
  try { $null = & winget --version 2>&1; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

# Apps que se resuelven vía winget (Windows Package Manager) en lugar de una URL directa,
# porque el fabricante no publica un patrón de descarga predecible.
$script:WingetIds = @{
  "Android Studio (latest shown on official site)"       = "Google.AndroidStudio"
  "Microsoft Power BI Desktop (latest from change log)"  = "Microsoft.PowerBI"
  "Power Automate for Desktop"                            = "Microsoft.PowerAutomateDesktop"
  "Araxis Merge"                                          = "Araxis.Merge"
}

# Idioma preferido (código winget/BCP-47) para apps sin MSI/URL directa que se
# resuelven vía winget, SOLO para paquetes cuyo manifest realmente publica
# instaladores distintos por idioma. Si el manifest no publica ese idioma,
# Download-InstallerViaWinget reintenta automáticamente sin --locale.
# NOTA: Power BI Desktop y Power Automate for Desktop se sacaron de este mapa
# porque Microsoft los distribuye como un único instalador multi-idioma (no
# hay una versión "en español" distinta que descargar); el idioma con el que
# arrancan depende de la configuración regional/idioma de Windows en el
# equipo donde se instalan, no del archivo descargado. Pasarles --locale no
# tenía ningún efecto real (siempre bajaba el mismo archivo).
$script:WingetLocale = @{}

function Download-InstallerViaWinget {
  param(
    [Parameter(Mandatory)][string]$WingetId,
    [Parameter(Mandatory)][string]$DestDir,
    [string]$Version,   # opcional: para reintentar una versión específica (penúltima segura)
    [string]$Locale     # opcional: idioma preferido (ej. "es-MX"); se relaja si el paquete no lo publica
  )
  Ensure-Directory -Path $DestDir
  $subDir = Join-Path $DestDir ($WingetId -replace "[^a-zA-Z0-9\.\-]", "_")
  Ensure-Directory -Path $subDir

  function Invoke-WingetDownload {
    param([string[]]$ArgsList)
    $output = & winget @ArgsList 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
  }

  $baseArgs = @("download", "--id", $WingetId, "--source", "winget", "-d", $subDir,
                "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")

  # Se intenta primero con la combinación más específica (versión + idioma) y
  # se va relajando ante fallos: el manifest de winget del paquete puede no
  # publicar esa versión exacta, o no publicar ese idioma en particular.
  $attempts = @()
  if ($Version -and $Locale) { $attempts += , ($baseArgs + @("--version", $Version, "--locale", $Locale)) }
  if ($Locale)                { $attempts += , ($baseArgs + @("--locale", $Locale)) }
  if ($Version)                { $attempts += , ($baseArgs + @("--version", $Version)) }
  $attempts += , $baseArgs

  $result = $null
  foreach ($argSet in $attempts) {
    $result = Invoke-WingetDownload -ArgsList $argSet
    if ($result.ExitCode -eq 0) { break }
  }

  if ($result.ExitCode -ne 0) {
    throw "winget download falló para $WingetId (exit $($result.ExitCode)): $($result.Output -join ' ')"
  }

  $installer = Get-ChildItem -Path $subDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in ".exe", ".msi" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

  if (-not $installer) { throw "winget no dejó un instalador .exe/.msi visible en $subDir." }
  return $installer.FullName
}

function Get-InstallerFile {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$TempDir
  )
  if ($script:WingetIds.ContainsKey($Name)) {
    if (-not (Test-WingetAvailable)) { throw "winget no está disponible en este equipo (instala 'App Installer' desde Microsoft Store)." }
    $locale = if ($script:WingetLocale.ContainsKey($Name)) { $script:WingetLocale[$Name] } else { $null }
    return Download-InstallerViaWinget -WingetId $script:WingetIds[$Name] -DestDir $TempDir -Version $Version -Locale $locale
  }
  $url = Get-InstallerDownloadUrl -Name $Name -Version $Version
  if (-not $url) { return $null }
  return Download-Installer -Name $Name -Url $url -DestDir $TempDir -Version $Version
}

# ============================================================
# DESCARGA
# ============================================================

function Ensure-Directory { param([string]$Path) if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

# Borra un archivo temporal reintentando si el primer intento falla. Justo
# después de escanearlo, Defender (u otro proceso) puede retener un candado
# breve sobre el archivo; con -ErrorAction SilentlyContinue ese fallo antes
# quedaba en silencio y el archivo se quedaba huérfano en la carpeta
# temporal. Devuelve $true si terminó borrado, $false si no se pudo.
function Remove-TempFileSafely {
  param([Parameter(Mandatory)][string]$FilePath, [int]$MaxAttempts = 3, [int]$DelaySeconds = 3)
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      Remove-Item -Path $FilePath -Force -ErrorAction Stop
      return $true
    } catch {
      if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $DelaySeconds }
    }
  }
  return (-not (Test-Path $FilePath))
}

function Get-Sha256Hash { param([string]$FilePath) (Get-FileHash -Algorithm SHA256 -Path $FilePath).Hash.ToLower() }

# Compara el hash SHA256 del archivo descargado contra el hash oficial
# publicado por el fabricante (cuando está disponible, ej. VS Code). Un hash
# que no coincide indica descarga corrupta o manipulada y se descarta de
# inmediato, sin importar lo que diga después el antivirus.
function Test-OfficialHashMatch {
  param([Parameter(Mandatory)][string]$AppName, [Parameter(Mandatory)][string]$LocalFilePath)
  if (-not $script:OfficialHashes.ContainsKey($AppName)) { return $null }
  $expected = $script:OfficialHashes[$AppName]
  if (-not $expected) { return $null }
  $actual = Get-Sha256Hash -FilePath $LocalFilePath
  return [pscustomobject]@{ Match = ($actual -eq $expected); Expected = $expected; Actual = $actual }
}

$script:ExtensionOverrides = @{
  "Mozilla Firefox (Standalone) - Latest" = ".msi"   # la URL de descarga es un query string sin extensión visible
}

function Download-Installer {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestDir,
    [Parameter(Mandatory)][string]$Version
  )
  Ensure-Directory -Path $DestDir
  $ext = [System.IO.Path]::GetExtension($Url.Split("?")[0])
  if ($script:ExtensionOverrides.ContainsKey($Name)) { $ext = $script:ExtensionOverrides[$Name] }
  if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".exe" }
  $safeName = ($Name -replace "[^a-zA-Z0-9\.\-]", "_")
  $destPath = Join-Path $DestDir "$safeName`_$Version$ext"

  Invoke-WebRequest -Uri $Url -OutFile $destPath -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 300 `
    -Headers @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell-OfficialVersionCheck/1.0" }

  if (-not (Test-Path $destPath) -or (Get-Item $destPath).Length -eq 0) {
    throw "Descarga vacía o falló para $Name."
  }
  return $destPath
}

# ============================================================
# VALIDACIÓN: VIRUSTOTAL (API v3)
# ============================================================

function Invoke-VirusTotalCheck {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    # OJO: NO marcar como Mandatory. En PowerShell, un parámetro [string]
    # Mandatory rechaza una cadena vacía ("") con el error "Cannot bind
    # argument... because it is an empty string" ANTES de que se ejecute el
    # cuerpo de la función — así que el chequeo de abajo (IsNullOrWhiteSpace)
    # nunca llegaba a correr cuando VT_API_KEY no estaba configurada. Esto
    # rompía TODO el pipeline: la excepción no se atrapaba aquí ni en
    # Test-InstallerSafety, y abortaba antes de que Defender llegara a
    # escanear nada, bloqueando el 100% de las apps sin importar Defender.
    [string]$ApiKey
  )

  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "Sin API key de VirusTotal (VT_API_KEY no configurada)." }
  }

  $hash = Get-Sha256Hash -FilePath $FilePath
  $headers = @{ "x-apikey" = $ApiKey }
  $reportUrl = "https://www.virustotal.com/api/v3/files/$hash"

  # 1) Buscar reporte existente por hash, respetando el límite de 4 req/min
  #    y reintentando ante HTTP 429 en vez de degradar silenciosamente a
  #    "no verificado" (que antes se dejaba pasar igual que "limpio").
  $report = $null
  $notFound = $false
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    Wait-VTRateLimit
    try {
      $report = Invoke-RestMethod -Uri $reportUrl -Headers $headers -Method Get -TimeoutSec 60
      break
    } catch {
      $code = Get-HttpStatusCode -ErrorRecord $_
      if ($code -eq 404) { $notFound = $true; break }
      if ($code -eq 429 -and $attempt -lt 3) { Start-Sleep -Seconds 30; continue }
      return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "VT error consultando hash (HTTP $code): $($_.Exception.Message)" }
    }
  }

  if ($report) {
    $stats = $report.data.attributes.last_analysis_stats
    $malicious = [int]$stats.malicious + [int]$stats.suspicious
    return [pscustomobject]@{
      Checked = $true
      Passed  = ($malicious -eq 0)
      Detail  = "VT (hash existente): malicious=$($stats.malicious) suspicious=$($stats.suspicious) harmless=$($stats.harmless)"
    }
  }

  if (-not $notFound) {
    return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "VT no devolvió reporte tras reintentos (rate limit persistente); revisar manualmente." }
  }

  # 2) No existe reporte previo -> subir archivo (límite 32MB API pública)
  $sizeMB = (Get-Item $FilePath).Length / 1MB
  if ($sizeMB -gt 32) {
    return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "Archivo de $([math]::Round($sizeMB,1))MB excede el límite de 32MB de la API pública de VT; se omite VT, se usa solo Defender." }
  }

  try {
    Wait-VTRateLimit
    $uploadUrl = "https://www.virustotal.com/api/v3/files"
    $uploadResp = Send-MultipartFile -Url $uploadUrl -FilePath $FilePath -Headers $headers
    $analysisId = $uploadResp.data.id

    $analysisUrl = "https://www.virustotal.com/api/v3/analyses/$analysisId"
    $status = "queued"
    $attempts = 0
    while ($status -ne "completed" -and $attempts -lt 10) {
      Start-Sleep -Seconds 20
      Wait-VTRateLimit
      $analysis = Invoke-RestMethod -Uri $analysisUrl -Headers $headers -Method Get -TimeoutSec 60
      $status = $analysis.data.attributes.status
      $attempts++
    }

    if ($status -ne "completed") {
      return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "VT no completó el análisis en el tiempo de espera; revisar manualmente el análisis $analysisId." }
    }

    $stats = $analysis.data.attributes.stats
    $malicious = [int]$stats.malicious + [int]$stats.suspicious
    return [pscustomobject]@{
      Checked = $true
      Passed  = ($malicious -eq 0)
      Detail  = "VT (subido/analizado): malicious=$($stats.malicious) suspicious=$($stats.suspicious) harmless=$($stats.harmless)"
    }
  }
  catch {
    return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "VT error subiendo/analizando: $($_.Exception.Message)" }
  }
}

# ============================================================
# VALIDACIÓN: MICROSOFT DEFENDER
# ============================================================

function Invoke-DefenderScan {
  param([Parameter(Mandatory)][string]$FilePath)

  $mpCmdRun = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
  if (-not (Test-Path $mpCmdRun)) {
    return [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "MpCmdRun.exe no encontrado en $mpCmdRun." }
  }

  try {
    $output = & $mpCmdRun -Scan -ScanType 3 -File $FilePath 2>&1
    $exitCode = $LASTEXITCODE

    # Confirmar además contra amenazas detectadas recientemente sobre esta ruta
    # NOTA: se fuerza @(...) porque bajo Set-StrictMode, si la pipeline no
    # devuelve nada, $threats queda en $null y $null.Count lanza error
    # ("no se encuentra la propiedad Count"). @(...) garantiza siempre un array.
    $threats = @()
    try { $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.Resources -match [regex]::Escape($FilePath) }) } catch {}

    $passed = ($exitCode -eq 0) -and ($threats.Count -eq 0)
    [pscustomobject]@{
      Checked = $true
      Passed  = $passed
      Detail  = "Defender exitCode=$exitCode, amenazas_detectadas=$($threats.Count)"
    }
  }
  catch {
    [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "Defender error: $($_.Exception.Message)" }
  }
}

function Get-AuthenticodeInfo {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$ExpectedPublishers = @()
  )
  try {
    $sig = Get-AuthenticodeSignature -FilePath $FilePath
    $publisher = $null
    if ($sig.SignerCertificate) {
      $m = [regex]::Match($sig.SignerCertificate.Subject, "CN=([^,]+)")
      if ($m.Success) { $publisher = $m.Groups[1].Value.Trim('"') }
    }
    $validStatus  = ($sig.Status -eq [System.Management.Automation.SignatureStatus]::Valid)
    $publisherOk  = $true
    if ($ExpectedPublishers.Count -gt 0) {
      $publisherOk = [bool]($publisher -and (@($ExpectedPublishers | Where-Object { $publisher -like "*$_*" })).Count -gt 0)
    }
    [pscustomobject]@{
      Checked        = $true
      Status         = $sig.Status.ToString()
      Publisher      = if ($publisher) { $publisher } else { "N/A" }
      MatchesTrusted = ($validStatus -and $publisherOk)
    }
  } catch {
    [pscustomobject]@{ Checked = $false; Status = "N/A"; Publisher = "N/A"; MatchesTrusted = $null }
  }
}

function Test-InstallerSafety {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$Name,
    [string]$ApiKey,
    [switch]$SkipVT
  )

  $vt = if ($SkipVT) {
    [pscustomobject]@{ Checked = $false; Passed = $null; Detail = "VT omitido por parámetro -SkipVirusTotal." }
  } else {
    Invoke-VirusTotalCheck -FilePath $FilePath -ApiKey $ApiKey
  }
  $defender = Invoke-DefenderScan -FilePath $FilePath

  $expectedPublishers = if ($script:ExpectedPublishers.ContainsKey($Name)) { $script:ExpectedPublishers[$Name] } else { @() }
  $sig = Get-AuthenticodeInfo -FilePath $FilePath -ExpectedPublishers $expectedPublishers

  # Regla de aprobación (definida junto al equipo): BASTA con que UNO de los
  # dos motores confirme explícitamente que el archivo está limpio; VT y
  # Defender se tratan como dos verificaciones alternativas/redundantes, no
  # hace falta que ambos coincidan. Solo se bloquea si NINGUNO de los dos
  # pudo confirmarlo limpio (ambos en falla, o ambos sin verificar).
  # La firma digital (Authenticode) es solo informativa: no bloquea la
  # entrega, queda anotada en el informe para revisión manual.
  $overallPass = ($vt.Passed -eq $true) -or ($defender.Passed -eq $true)

  $vtResult  = if (-not $vt.Checked)       { "N/D" } elseif ($vt.Passed)       { "OK" } else { "FALLÓ" }
  $defResult = if (-not $defender.Checked) { "N/D" } elseif ($defender.Passed) { "OK" } else { "FALLÓ" }
  $sigResult = if (-not $sig.Checked) { "N/D" }
               elseif ($sig.MatchesTrusted) { "OK" }
               elseif ($sig.Status -eq "Valid") { "PUBLISHER?" }
               else { "SIN FIRMA" }

  [pscustomobject]@{
    Passed          = $overallPass
    VTResult        = $vtResult
    DefenderResult  = $defResult
    SignatureResult = $sigResult
    VTDetail        = $vt.Detail
    DefenderDetail  = $defender.Detail
    SignatureDetail = "Publisher: $($sig.Publisher) | Estado firma: $($sig.Status)"
  }
}

# ============================================================
# HISTORIAL DE VERSIONES SEGURAS
# ============================================================

function Get-VersionsHistory {
  param([string]$Path)
  if (Test-Path $Path) {
    try { return (Get-Content -Path $Path -Raw | ConvertFrom-Json) } catch { return [pscustomobject]@{} }
  }
  return [pscustomobject]@{}
}

function Save-VersionsHistory {
  param([Parameter(Mandatory)]$History, [Parameter(Mandatory)][string]$Path)
  $History | ConvertTo-Json -Depth 8 | Out-File -FilePath $Path -Encoding UTF8
}

function Update-HistoryEntry {
  param([Parameter(Mandatory)]$History, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$SafeVersion, [string]$SafeHash = $null)

  $existing = $History.PSObject.Properties[$Name]
  if ($existing) {
    $current = $existing.Value
    if ($current.LatestSafe -ne $SafeVersion) {
      $current.PreviousSafe     = $current.LatestSafe
      $current.PreviousSafeHash = $current.LatestSafeHash
      $current.LatestSafe       = $SafeVersion
      $current.LatestSafeHash   = $SafeHash
    }
  } else {
    $History | Add-Member -MemberType NoteProperty -Name $Name -Value ([pscustomobject]@{
      LatestSafe       = $SafeVersion
      LatestSafeHash   = $SafeHash
      PreviousSafe     = $null
      PreviousSafeHash = $null
    })
  }
  return $History
}

# ============================================================
# ORQUESTACIÓN: procesar un aplicativo (descarga + validación + entrega)
# ============================================================

function Process-Application {
  param(
    [Parameter(Mandatory)][pscustomobject]$VersionResult,
    [Parameter(Mandatory)]$History,
    [Parameter(Mandatory)][string]$TempDir,
    [Parameter(Mandatory)][string]$DeliveryDir,
    [string]$ApiKey,
    [switch]$SkipVT
  )

  # Aplicativos que NO tienen descarga directa pública (requieren portal/login
  # del fabricante). No cuenta como "bloqueado por seguridad": es una limitación
  # de acceso, no un fallo de validación.
  $script:ManualDownloadApps = @(
    "CyberArk EPM - Latest Agent Version (from rollout status)",
    "Bizagi Modeler (Latest from Bizagi Release Notes)",
    "DCNet Document Control Backoffice",
    "think-cell",
    "SentinelOne (agente)",
    "TRSuite (FATCA/CRS)",
    "ACL for Windows (Diligent One)",
    "TeamMate (Wolters Kluwer)"
  )

  $name = $VersionResult.Name
  $status = [pscustomobject]@{
    Name             = $name
    RequestedVersion = $VersionResult.LatestVersion
    DeliveredVersion = $null
    Hash             = $null
    State            = "❌ Bloqueado (no validado)"
    VTResult         = "N/D"
    DefenderResult   = "N/D"
    SignatureResult  = "N/D"
    Detail           = ""
  }

  if ($name -in $script:ManualDownloadApps) {
    $status.State  = "🟨 Descarga manual (portal/login)"
    $status.Detail = "Este aplicativo no publica una URL de descarga directa pública; requiere descarga manual desde el portal del fabricante. $($VersionResult.Notes)"
    return $status
  }

  if ($VersionResult.LatestVersion -eq "N/A") {
    $status.Detail = "Sin versión oficial resuelta: $($VersionResult.Notes)"
    return $status
  }

  # Limpieza defensiva: si una corrida anterior quedó interrumpida (cierre de
  # la ventana, Ctrl+C, corte de energía) antes de mover/borrar el archivo de
  # este aplicativo, puede haber quedado huérfano en la carpeta temporal.
  # Se borra antes de empezar para no acumular versiones viejas.
  $safeNamePrefix = ($name -replace "[^a-zA-Z0-9\.\-]", "_")
  Get-ChildItem -Path $TempDir -Filter "$safeNamePrefix`_*" -File -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-TempFileSafely -FilePath $_.FullName | Out-Null }

  # --- Intento 1: última versión (URL directa o winget, según la app) ---
  try {
    $file = Get-InstallerFile -Name $name -Version $VersionResult.LatestVersion -TempDir $TempDir
    if (-not $file) {
      $status.State  = "🟨 Descarga manual (portal/login)"
      $status.Detail = "Sin patrón de URL directa ni paquete winget disponible para esta app."
      return $status
    }

    $hashCheck = Test-OfficialHashMatch -AppName $name -LocalFilePath $file
    if ($hashCheck -and -not $hashCheck.Match) {
      $status.Detail = "Última versión ($($VersionResult.LatestVersion)) descartada: el SHA256 no coincide con el oficial publicado por el fabricante (posible descarga corrupta o manipulada). Esperado=$($hashCheck.Expected) Obtenido=$($hashCheck.Actual)"
      if (-not (Remove-TempFileSafely -FilePath $file)) {
        $status.Detail += " || ADVERTENCIA: no se pudo borrar el archivo temporal (posible bloqueo de otro proceso); queda en $file, bórralo manualmente."
      }
      $file = $null
    }

    if ($file) {
      $check = Test-InstallerSafety -FilePath $file -Name $name -ApiKey $ApiKey -SkipVT:$SkipVT
      if ($check.Passed) {
        $fileHash = Get-Sha256Hash -FilePath $file
        Ensure-Directory -Path $DeliveryDir
        Move-Item -Path $file -Destination (Join-Path $DeliveryDir (Split-Path $file -Leaf)) -Force
        $History = Update-HistoryEntry -History $History -Name $name -SafeVersion $VersionResult.LatestVersion -SafeHash $fileHash
        $status.State           = "✅ Última versión entregada"
        $status.DeliveredVersion = $VersionResult.LatestVersion
        $status.Hash            = $fileHash
        $status.VTResult        = $check.VTResult
        $status.DefenderResult  = $check.DefenderResult
        $status.SignatureResult = $check.SignatureResult
        $status.Detail          = "VT: $($check.VTDetail) | Defender: $($check.DefenderDetail) | Firma: $($check.SignatureDetail)"
        return $status
      } else {
        $status.VTResult        = $check.VTResult
        $status.DefenderResult  = $check.DefenderResult
        $status.SignatureResult = $check.SignatureResult
        $status.Detail = "Última versión ($($VersionResult.LatestVersion)) bloqueada: ni VirusTotal ni Defender la validaron como segura. VT: $($check.VTDetail) | Defender: $($check.DefenderDetail)"
        if (-not (Remove-TempFileSafely -FilePath $file)) {
          $status.Detail += " || ADVERTENCIA: no se pudo borrar el archivo temporal (posible bloqueo de otro proceso, ej. Defender); queda en $file, bórralo manualmente."
        }
      }
    }
  } catch {
    $status.Detail = "Error descargando/validando última versión: $($_.Exception.Message)"
  }

  # --- Intento 2: penúltima versión segura conocida (histórico) ---
  $histEntry = $History.PSObject.Properties[$name]
  $previousSafe = if ($histEntry -and $histEntry.Value.PreviousSafe) { $histEntry.Value.PreviousSafe }
                  elseif ($histEntry -and $histEntry.Value.LatestSafe -ne $VersionResult.LatestVersion) { $histEntry.Value.LatestSafe }
                  else { $null }

  if ($previousSafe) {
    try {
      $file2 = Get-InstallerFile -Name $name -Version $previousSafe -TempDir $TempDir
      if (-not $file2) {
        $status.Detail += " || No hay forma de descargar la penúltima versión (manual)."
      } else {
        $check2 = Test-InstallerSafety -FilePath $file2 -Name $name -ApiKey $ApiKey -SkipVT:$SkipVT
        if ($check2.Passed) {
          $fileHash2 = Get-Sha256Hash -FilePath $file2
          Ensure-Directory -Path $DeliveryDir
          Move-Item -Path $file2 -Destination (Join-Path $DeliveryDir (Split-Path $file2 -Leaf)) -Force
          $status.State           = "⚠️ Penúltima versión entregada (última bloqueada)"
          $status.DeliveredVersion = $previousSafe
          $status.Hash            = $fileHash2
          $status.VTResult        = $check2.VTResult
          $status.DefenderResult  = $check2.DefenderResult
          $status.SignatureResult = $check2.SignatureResult
          $status.Detail += " || Penúltima ($previousSafe) validada OK: VT: $($check2.VTDetail) | Defender: $($check2.DefenderDetail) | Firma: $($check2.SignatureDetail)"
          return $status
        } else {
          $status.Detail += " || Penúltima ($previousSafe) también falló: VT: $($check2.VTDetail) | Defender: $($check2.DefenderDetail)"
          if (-not (Remove-TempFileSafely -FilePath $file2)) {
            $status.Detail += " || ADVERTENCIA: no se pudo borrar el archivo temporal de la penúltima versión (posible bloqueo de otro proceso); queda en $file2, bórralo manualmente."
          }
        }
      }
    } catch {
      $status.Detail += " || Error con penúltima versión: $($_.Exception.Message)"
    }
  } else {
    $status.Detail += " || No hay penúltima versión segura registrada todavía en el histórico (se completará tras la primera entrega exitosa de esta app)."
  }

  return $status
}

# ============================================================
# INFORME
# ============================================================

function Write-Informe {
  param([Parameter(Mandatory)][array]$Statuses, [Parameter(Mandatory)][string]$Path)

  $sorted = $Statuses | Sort-Object Name

  # --- Resumen ---
  $okLatest   = @($sorted | Where-Object { $_.State -like "✅*" }).Count
  $okPrevious = @($sorted | Where-Object { $_.State -like "⚠️*" }).Count
  $manual     = @($sorted | Where-Object { $_.State -like "🟨*" }).Count
  $blocked    = @($sorted | Where-Object { $_.State -like "❌*" }).Count

  # --- Preparar filas de la tabla ---
  $rows = foreach ($s in $sorted) {
    [pscustomobject]@{
      Aplicativo = $s.Name
      Estado     = $s.State
      Version    = if ($s.DeliveredVersion) { $s.DeliveredVersion } else { $s.RequestedVersion }
      VT         = $s.VTResult
      Defender   = $s.DefenderResult
      Firma      = $s.SignatureResult
      Hash       = if ($s.Hash) { $s.Hash } else { "—" }
    }
  }

  # --- Calcular anchos de columna ---
  $wName  = [Math]::Max(10, ($rows | ForEach-Object { $_.Aplicativo.Length } | Measure-Object -Maximum).Maximum)
  $wState = [Math]::Max(6,  ($rows | ForEach-Object { $_.Estado.Length }     | Measure-Object -Maximum).Maximum)
  $wVer   = [Math]::Max(8,  ($rows | ForEach-Object { $_.Version.Length }    | Measure-Object -Maximum).Maximum)
  $wVT    = [Math]::Max(2,  ($rows | ForEach-Object { $_.VT.Length }         | Measure-Object -Maximum).Maximum)
  $wDef   = [Math]::Max(8,  ($rows | ForEach-Object { $_.Defender.Length }   | Measure-Object -Maximum).Maximum)
  $wSig   = [Math]::Max(5,  ($rows | ForEach-Object { $_.Firma.Length }      | Measure-Object -Maximum).Maximum)
  $wHash  = 64

  function Pad-Right { param([string]$Text, [int]$Width) $Text.PadRight($Width) }

  $sep = "+" + ("-" * ($wName+2)) + "+" + ("-" * ($wState+2)) + "+" + ("-" * ($wVer+2)) + "+" + ("-" * ($wVT+2)) + "+" + ("-" * ($wDef+2)) + "+" + ("-" * ($wSig+2)) + "+" + ("-" * ($wHash+2)) + "+"

  $lines = @()
  $lines += "INFORME DE DESCARGA Y VALIDACIÓN DE SOFTWARE"
  $lines += "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $lines += "======================================================"
  $lines += ""
  $lines += "RESUMEN"
  $lines += "  Total de aplicativos evaluados : $($sorted.Count)"
  $lines += "  ✅ Última versión entregada     : $okLatest"
  $lines += "  ⚠️ Versión anterior entregada   : $okPrevious"
  $lines += "  🟨 Descarga manual (portal)     : $manual"
  $lines += "  ❌ Bloqueado por seguridad      : $blocked"
  $lines += ""
  $lines += "Nota: 'entregado' significa que el instalador pasó el filtro de seguridad y quedó"
  $lines += "listo en la carpeta de entrega; este script NO ejecuta la instalación en el equipo."
  $lines += ""
  $lines += "Nota: 🟨 no es un fallo de seguridad, son apps sin descarga directa pública o que"
  $lines += "requieren licencia (CyberArk EPM, Bizagi Modeler, DCNet, think-cell): se gestionan a mano."
  $lines += ""
  $lines += "Nota: se aprueba si VirusTotal O Defender confirman que el archivo está limpio (no"
  $lines += "hace falta que ambos coincidan). La columna Firma (Authenticode) es informativa y"
  $lines += "no bloquea la entrega: OK = firma válida del publisher esperado, PUBLISHER? = firma"
  $lines += "válida pero de un publisher distinto al esperado, SIN FIRMA = sin firma válida,"
  $lines += "N/D = no se pudo verificar."
  $lines += ""
  $lines += "TABLA DE APLICATIVOS"
  $lines += $sep
  $lines += "| " + (Pad-Right "Aplicativo" $wName) + " | " + (Pad-Right "Estado" $wState) + " | " + (Pad-Right "Versión" $wVer) + " | " + (Pad-Right "VT" $wVT) + " | " + (Pad-Right "Defender" $wDef) + " | " + (Pad-Right "Firma" $wSig) + " | " + (Pad-Right "SHA256" $wHash) + " |"
  $lines += $sep
  foreach ($r in $rows) {
    $lines += "| " + (Pad-Right $r.Aplicativo $wName) + " | " + (Pad-Right $r.Estado $wState) + " | " + (Pad-Right $r.Version $wVer) + " | " + (Pad-Right $r.VT $wVT) + " | " + (Pad-Right $r.Defender $wDef) + " | " + (Pad-Right $r.Firma $wSig) + " | " + (Pad-Right $r.Hash $wHash) + " |"
  }
  $lines += $sep
  $lines += ""
  $lines += "DETALLE POR APLICATIVO"
  $lines += "------------------------------------------------------"
  foreach ($s in $sorted) {
    $lines += ""
    $lines += "Aplicativo: $($s.Name)"
    $lines += "  Estado:             $($s.State)"
    $lines += "  Versión solicitada: $($s.RequestedVersion)"
    $lines += "  Versión entregada:  $(if ($s.DeliveredVersion) { $s.DeliveredVersion } else { '—' })"
    $lines += "  VirusTotal:         $($s.VTResult)"
    $lines += "  Defender:           $($s.DefenderResult)"
    $lines += "  Firma (Authenticode): $($s.SignatureResult)"
    $lines += "  SHA256:             $(if ($s.Hash) { $s.Hash } else { '—' })"
    $lines += "  Detalle:            $($s.Detail)"
  }
  $lines | Out-File -FilePath $Path -Encoding UTF8
}

# ============================================================
# RUN — Resolución de versiones
# ============================================================

$results = @()
$results += Safe-Run -Name "Google Chrome (Standalone) - Stable (Win64)" -Source "https://versionhistory.googleapis.com/" -Block { Get-LatestChromeStableWin64 }
$results += Safe-Run -Name "Mozilla Firefox (Standalone) - Latest"        -Source "https://product-details.mozilla.org/" -Block { Get-LatestFirefox }
$results += Safe-Run -Name "CyberArk EPM - Latest Agent Version"          -Source "https://docs.cyberark.com/epm/latest/en/content/release%20notes/rn-rollout-status.htm" -Block { Get-LatestCyberArkEpmAgents }
$results += Safe-Run -Name "KeePass"                                      -Source "https://keepass.info/download.html" -Block { Get-LatestKeePass }
$results += Safe-Run -Name "LibreOffice"                                  -Source "https://www.libreoffice.org/download/download-libreoffice/" -Block { Get-LatestLibreOffice }
$results += Safe-Run -Name "WinSCP"                                       -Source "https://winscp.net/eng/download.php" -Block { Get-LatestWinSCP }
$results += Safe-Run -Name "WinMerge"                                     -Source "https://winmerge.org/downloads/?lang=en" -Block { Get-LatestWinMerge }
$results += Safe-Run -Name "7-Zip"                                        -Source "https://www.7-zip.org/download.html" -Block { Get-Latest7Zip }
$results += Safe-Run -Name "Bizagi Modeler"                               -Source "https://releasenotes.bizagi.com/en/release-notes/releases/all-releases" -Block { Get-LatestBizagiModeler }
$results += Safe-Run -Name "SoapUI"                                       -Source "https://www.soapui.org/downloads/latest-release/" -Block { Get-LatestSoapUI }
$results += Safe-Run -Name "K-Lite Codec Pack"                            -Source "https://codecguide.com/" -Block { Get-LatestKLite }
$results += Safe-Run -Name "Node.js"                                      -Source "https://nodejs.org/dist/index.json" -Block { Get-LatestNodeJs }
$results += Safe-Run -Name "Docker Desktop (Windows AMD64)"               -Source "https://desktop.docker.com/win/main/amd64/appcast.xml" -Block { Get-LatestDockerDesktopWinAmd64 }
$results += Safe-Run -Name "Python (Windows)"                             -Source "https://www.python.org/downloads/windows/" -Block { Get-LatestPythonWindows }
$results += Get-PythonLauncherLocal
$results += Get-DCNetDocumentControlBackoffice
$results += Safe-Run -Name "Adobe Acrobat Reader"                         -Source "https://helpx.adobe.com/acrobat/release-note/release-notes-acrobat-reader.html" -Block { Get-LatestAdobeAcrobatReaderContinuous }
$results += Safe-Run -Name "Android Studio"                               -Source "https://developer.android.com/studio" -Block { Get-LatestAndroidStudio }
$results += Safe-Run -Name "Git"                                          -Source "https://git-scm.com/install/windows" -Block { Get-LatestGitForWindows }
$results += Safe-Run -Name "Microsoft Power BI Desktop"                   -Source "https://learn.microsoft.com/en-us/power-bi/fundamentals/desktop-change-log" -Block { Get-LatestPowerBIDesktop }
$results += Safe-Run -Name "Visual Studio Code"                           -Source "https://update.code.visualstudio.com/api/update/win32-x64/stable/latest" -Block { Get-LatestVSCode }
$results += Get-LatestLucenTime
$results += Safe-Run -Name "draw.io Desktop"                              -Source "https://api.github.com/repos/jgraph/drawio-desktop/releases/latest" -Block { Get-LatestDrawIO }
$results += Safe-Run -Name "Zulu JDK 21 (Windows x64 MSI)"                 -Source "https://api.azul.com/metadata/v1/zulu/packages/" -Block { Get-LatestZuluJDK }
$results += Safe-Run -Name "Wireshark"                                    -Source "https://www.wireshark.org/download.html" -Block { Get-LatestWireshark }
$results += Safe-Run -Name "ILSpy"                                        -Source "https://api.github.com/repos/icsharpcode/ILSpy/releases/latest" -Block { Get-LatestILSpy }
$results += Safe-Run -Name "PuTTY (64-bit)"                               -Source "https://the.earth.li/~sgtatham/putty/latest/w64/" -Block { Get-LatestPuTTY }
$results += Safe-Run -Name "Nmap"                                         -Source "https://nmap.org/download.html" -Block { Get-LatestNmap }
$results += Safe-Run -Name "OpenJDK (Eclipse Temurin)"                    -Source "https://api.adoptium.net/v3/info/available_releases" -Block { Get-LatestOpenJDK }
$results += Safe-Run -Name "Power Automate for Desktop"                   -Source "winget show Microsoft.PowerAutomateDesktop" -Block { Get-LatestPowerAutomateDesktop }
$results += Safe-Run -Name "Notepad++ (x64)"                              -Source "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest" -Block { Get-LatestNotepadPlusPlus }
$results += Safe-Run -Name ".NET SDK"                                     -Source "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json" -Block { Get-LatestDotNetSdk }
$results += Safe-Run -Name "Visual Studio Professional 2026"              -Source "https://aka.ms/vs/18/Stable/vs_professional.exe" -Block { Get-LatestVSProfessional2026 }
$results += Safe-Run -Name "Visual Studio Enterprise 2026"                -Source "https://aka.ms/vs/18/Stable/vs_enterprise.exe" -Block { Get-LatestVSEnterprise2026 }
$results += Get-SentinelOneNote
$results += Get-TRSuiteNote
$results += Get-ACLForWindowsNote
$results += Get-TeamMateNote
$results += Safe-Run -Name "AES Crypt (open-source)"                      -Source "https://api.github.com/repos/terrapane/aescrypt_win/releases/latest" -Block { Get-LatestAESCryptOpenSource }
$results += Safe-Run -Name "AES Crypt (comercial)"                        -Source "https://www.aescrypt.com/download/" -Block { Get-LatestAESCryptCommercial }
$results += Safe-Run -Name "Angular CLI"                                  -Source "https://registry.npmjs.org/@angular/cli/latest" -Block { Get-LatestAngularCli }
$results += Safe-Run -Name "IntelliJ IDEA Community Edition"              -Source "https://data.services.jetbrains.com/products/releases?code=IIC" -Block { Get-LatestIntelliJIdeaCommunity }
$results += Safe-Run -Name "JetBrains dotPeek"                            -Source "https://data.services.jetbrains.com/products/releases?code=DPK" -Block { Get-LatestJetBrainsDotPeek }
$results += Safe-Run -Name "Gradle"                                       -Source "https://services.gradle.org/versions/current" -Block { Get-LatestGradle }
$results += Safe-Run -Name "R for Windows"                                -Source "https://cran.r-project.org/bin/windows/base/" -Block { Get-LatestRForWindows }
$results += Safe-Run -Name "RStudio Desktop"                              -Source "https://posit.co/download/rstudio-desktop/" -Block { Get-LatestRStudioDesktop }
$results += Get-LatestAzureConnectedMachineAgent
$results += Safe-Run -Name ".NET Runtime"                                 -Source "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json" -Block { Get-LatestDotNetRuntime }
$results += Safe-Run -Name "ASP.NET Core Runtime"                         -Source "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json" -Block { Get-LatestDotNetAspNetCoreRuntime }
$results += Safe-Run -Name ".NET Hosting Bundle"                          -Source "https://raw.githubusercontent.com/dotnet/core/main/release-notes/releases-index.json" -Block { Get-LatestDotNetHostingBundle }
$results += Safe-Run -Name "Visual Studio Professional 2022"              -Source "https://aka.ms/vs/17/release/vs_professional.exe" -Block { Get-LatestVSProfessional2022 }
$results += Safe-Run -Name "Visual Studio Enterprise 2022"                -Source "https://aka.ms/vs/17/release/vs_enterprise.exe" -Block { Get-LatestVSEnterprise2022 }
$results += Safe-Run -Name "Araxis Merge"                                 -Source "winget show Araxis.Merge" -Block { Get-LatestAraxisMerge }
$results += Safe-Run -Name "nvm-windows"                                  -Source "https://api.github.com/repos/coreybutler/nvm-windows/releases/latest" -Block { Get-LatestNvmWindows }
$results += Get-LatestFigma
$results += Get-LatestPostman
$results += Get-ThinkCellNote

$results | Sort-Object Name | Format-Table -AutoSize
$results | Sort-Object Name | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 $InventoryJson
Write-Host "`nInventario de versiones guardado en: $InventoryJson`n"

if ($SkipDownload) {
  Write-Host "SkipDownload activo: no se descarga ni valida nada. Fin del script."
  return
}

# ============================================================
# RUN — Descarga, validación, entrega e informe
# ============================================================

Ensure-Directory -Path $TempDownloadDir
Ensure-Directory -Path $DeliveryDir

$history = Get-VersionsHistory -Path $HistoryFile

$statuses = @()
foreach ($r in $results) {
  Write-Host "Procesando: $($r.Name) ..."
  $st = Process-Application -VersionResult $r -History $history -TempDir $TempDownloadDir -DeliveryDir $DeliveryDir -ApiKey $VirusTotalApiKey -SkipVT:$SkipVirusTotal
  $statuses += $st
}

Save-VersionsHistory -History $history -Path $HistoryFile
Write-Informe -Statuses $statuses -Path $ReportFile

Write-Host "`nInforme generado en: $ReportFile"
Write-Host "Histórico de versiones seguras actualizado en: $HistoryFile"
$statuses | Sort-Object Name | Format-Table Name, State, RequestedVersion, DeliveredVersion, VTResult, DefenderResult, SignatureResult -AutoSize
