function Install-Docker-Server {
  Write-Host "Iniciando la instalación de Docker Engine para Windows Server..." -ForegroundColor Cyan

  # 1. Habilitar la característica de Contenedores (y reiniciar SOLO si es necesario)
  if (-not (Get-WindowsFeature -Name Containers -ErrorAction SilentlyContinue).Installed) {
    Write-Host "Habilitando la característica 'Containers' de Windows..." -ForegroundColor Yellow
    $feature = Install-WindowsFeature -Name Containers
    if ($feature.RestartNeeded) {
      Write-Host "ACCIÓN REQUERIDA: La característica 'Containers' ha sido instalada y REQUIERE UN REINICIO." -ForegroundColor Yellow
      Restart-Computer -Force
    }
  }
  Write-Host "La característica 'Containers' ya está habilitada." -ForegroundColor Green

  # 2. Descargar e instalar Docker Engine (actualiza a versión más reciente; verifica en https://download.docker.com/win/static/stable/x86_64/)
  Write-Host "Descargando el instalador de Docker Engine..." -ForegroundColor Cyan
  $installerUrl = "https://download.docker.com/win/static/stable/x86_64/docker-27.2.0.zip"  # Actualizado; cambia si hay newer
  $installerPath = "$env:TEMP\docker.zip"
  Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

  Write-Host "Extrayendo y instalando Docker..." -ForegroundColor Cyan
  Expand-Archive -Path $installerPath -DestinationPath "$env:TEMP\docker" -Force
  $dockerExePath = "$env:TEMP\docker\docker\dockerd.exe"
  if (Test-Path $dockerExePath) {
    $installDir = "C:\Program Files\Docker"
    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir }
    Copy-Item -Path "$env:TEMP\docker\docker\*" -Destination $installDir -Recurse -Force

    $existingPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($existingPath -notlike "*$installDir*") {
        Write-Host "Añadiendo Docker al PATH del sistema..." -ForegroundColor Cyan
        $newPath = $existingPath + ";" + $installDir
        [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
        $env:Path = $newPath
    }

    Write-Host "Registrando Docker como servicio..." -ForegroundColor Cyan
    & "$installDir\dockerd.exe" --register-service
    Start-Service Docker
  } else {
    Write-Error "No se pudo extraer el ejecutable de Docker. Verifica la URL de descarga."; exit 1
  }

  # Limpiar archivos temporales
  Remove-Item $installerPath -Force
  Remove-Item "$env:TEMP\docker" -Recurse -Force

  Write-Host "Instalación de Docker finalizada. Intentando iniciar el servicio..." -ForegroundColor Green
  Start-Service Docker -ErrorAction SilentlyContinue
}

function Install-Docker-Desktop {
  Write-Host "Iniciando la instalación de Docker Desktop para Windows..." -ForegroundColor Cyan

  # Descargar el instalador (actualiza si necesario; verifica en https://www.docker.com/products/docker-desktop/)
  $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
  $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
  Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

  # Ejecutar el instalador (incluye Compose; no necesita standalone)
  Write-Host "Ejecutando el instalador de Docker Desktop..." -ForegroundColor Cyan
  Start-Process -Wait -FilePath $installerPath -ArgumentList "install", "--quiet"

  Write-Host "Instalación de Docker Desktop completada." -ForegroundColor Green
}

function Test-Docker {
  try {
    docker info > $null; return $true
  }
  catch {
    return $false
  }
}

function Test-DockerCompose {
  try {
    docker-compose --version > $null; return $true
  }
  catch {
    return $false
  }
}

function Get-PublicIP {
    param (
        [string[]]$Services = @(
            "https://api.ipify.org",
            "https://ifconfig.me",
            "https://checkip.amazonaws.com",
            "https://ipinfo.io/ip",
            "https://ident.me"
        )
    )

    foreach ($service in $Services) {
        try {
            $ip = Invoke-RestMethod -Uri $service -TimeoutSec 5
            if ($ip) {
                return $ip.Trim()
            }
        } catch {
            Write-Verbose "No se pudo obtener la IP desde $service"
        }
    }

    throw "No se pudo obtener la IP pública desde los servicios configurados."
}

function Set-FirewallRules {
  Write-Host "Configurando las reglas del Firewall de Windows..." -ForegroundColor Cyan
  $tcpPorts = "21115-21119"; $udpPorts = "21116"
  $tcpRuleName = "RustDesk Server (TCP)"; $udpRuleName = "RustDesk Server (UDP)"

  if (-not (Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $tcpRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $tcpPorts
    Write-Host "Regla TCP '$tcpRuleName' creada." -ForegroundColor Green
  }
  else { Write-Host "La regla de firewall TCP '$tcpRuleName' ya existe." -ForegroundColor Yellow }

  if (-not (Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $udpPorts
    Write-Host "Regla UDP '$udpRuleName' creada." -ForegroundColor Green
  }
  else { Write-Host "La regla de firewall UDP '$udpRuleName' ya existe." -ForegroundColor Yellow }
}

# --- INICIO DEL SCRIPT ---

Write-Host "Iniciando el instalador del servidor RustDesk para Windows..." -ForegroundColor Cyan

# 1. Verificar y/u ofrecer instalación de Docker
if (-not (Test-Docker)) {
  $choice = Read-Host "Docker no está detectado. ¿Desea intentar instalarlo ahora? (Y/n)"
  if ($choice -eq 'y' -or $choice -eq 'Y') {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $isServer = $osInfo.ProductType -ne 1 # 1 = Workstation, 2 = DC, 3 = Server

    if ($isServer) {
      Install-Docker-Server
    }
    else {
      Install-Docker-Desktop
      Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
      Write-Host "ACCIÓN REQUERIDA: La instalación de Docker Desktop ha finalizado." -ForegroundColor Green
      Write-Host "Por favor, REINICIA TU COMPUTADORA y vuelve a ejecutar este script."
      Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
      exit
    }

    # Volver a comprobar si Docker se está ejecutando después de la instalación
    if (-not (Test-Docker)) {
      Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
      Write-Host "ADVERTENCIA: La instalación de Docker finalizó, pero el servicio no se está ejecutando." -ForegroundColor Yellow
      Write-Host "Es posible que se necesite un reinicio manual. Por favor, reinicia y vuelve a ejecutar el script."
      Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
      exit
    }

    Write-Host "Docker se ha instalado y se está ejecutando correctamente. Continuando..." -ForegroundColor Green

  }
  else {
    Write-Error "La instalación no puede continuar sin Docker. Saliendo."; exit 1
  }
}
Write-Host "Docker está listo." -ForegroundColor Green

# 2. Verificar e instalar Docker Compose si es necesario
if (-not (Test-DockerCompose)) {
  Write-Warning "Docker Compose no está detectado. Intentando instalarlo para Windows Server..."
  $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
  $isServer = $osInfo.ProductType -ne 1 # 1 = Workstation, 2 = DC, 3 = Server

  if ($isServer) {
      # Instalar Docker Compose solo para Server (Desktop lo incluye)
      Write-Host "Instalando Docker Compose (standalone)..." -ForegroundColor Cyan
      $composeUrl = ""
      try {
          Write-Host "Buscando la última versión de Docker Compose..." -ForegroundColor Cyan
          $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/docker/compose/releases/latest"
          $version = $latestRelease.tag_name
          if ($version) {
              Write-Host "Última versión encontrada: $version" -ForegroundColor Green
              $composeUrl = "https://github.com/docker/compose/releases/download/$version/docker-compose-windows-x86_64.exe"
          }
      } catch {
          Write-Warning "No se pudo obtener la última versión de Docker Compose. Se usará una versión estable conocida."
      }

      if (-not $composeUrl) {
          # URL de fallback si falla la API
          $composeUrl = "https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-windows-x86_64.exe"
      }

      $composePath = "C:\Program Files\Docker\docker-compose.exe"
      Write-Host "Descargando Docker Compose desde $composeUrl..." -ForegroundColor Cyan
      try {
          Invoke-WebRequest -Uri $composeUrl -OutFile $composePath -ErrorAction Stop
      } catch {
          Write-Error "Falló la descarga de docker-compose.exe. Comprueba tu conexión a internet y la URL: $composeUrl"; exit 1
      }

      if (-not (Test-Path $composePath)) {
          Write-Error "El archivo docker-compose.exe no se encontró en la ruta esperada después de la descarga. Saliendo."; exit 1
      }

      # Verificar que docker-compose sea ejecutable
      try {
        $composeVersion = & $composePath --version
        Write-Host "Docker Compose instalado correctamente: $composeVersion" -ForegroundColor Green
      } catch {
        Write-Error "No se pudo ejecutar docker-compose.exe. Verifica permisos y compatibilidad."; exit 1
      }
  } else {
      # En Windows Desktop, Docker Compose viene con Docker Desktop. Si no está, hay un problema mayor.
      Write-Error "Docker Compose no está instalado. Por favor, reinstala o repara tu instalación de Docker Desktop."; exit 1
  }
}
Write-Host "Docker Compose está listo." -ForegroundColor Green

# 3. Configurar Firewall
Set-FirewallRules

# 4. Obtener la dirección del servidor
$serverAddress = ""
Write-Host "
Configuración de la dirección pública del servidor." -ForegroundColor Cyan
$choice = Read-Host "¿Detectar IP pública automáticamente? (Y/n)"

if ($choice -eq 'n' -or $choice -eq 'N') {
    # Modo Manual
    $serverAddress = Read-Host "Introduce la IP pública o dominio del servidor"
} else {
    # Modo Automático (por defecto)
    Write-Host "Detectando IP pública..." -ForegroundColor Cyan
    try {
        $serverAddress = Get-PublicIP
        Write-Host "IP pública detectada: $serverAddress" -ForegroundColor Green
    } catch {
        Write-Warning "Falló la detección automática de IP. Por favor, introduce la dirección manualmente."
        $serverAddress = Read-Host "Introduce la IP pública o dominio del servidor"
    }
}

if (-not $serverAddress) { Write-Error "La dirección del servidor es necesaria para continuar. Saliendo."; exit 1 }
Write-Host "La dirección del servidor se ha establecido en: $serverAddress" -ForegroundColor Green

# 5. Crear el archivo docker-compose.yml (sin -r; auto-detect)
$composeContent = @"
version: '3'
services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server:latest
    command: hbbs
    volumes:
      - ./data:/root
    ports:
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21118:21118
    networks:
      - rustdesk-net
    depends_on:
      - hbbr
    restart: unless-stopped
  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:latest
    command: hbbr
    volumes:
      - ./data:/root
    ports:
      - 21117:21117
      - 21119:21119
    networks:
      - rustdesk-net
    restart: unless-stopped
networks:
  rustdesk-net:
    driver: bridge
"@
Write-Host "Creando archivo docker-compose.yml..."
Set-Content -Path "docker-compose.yml" -Value $composeContent
Write-Host "docker-compose.yml creado." -ForegroundColor Green

# 6. Iniciar los servicios
Write-Host "Iniciando los servicios de RustDesk con docker-compose..."
docker-compose up -d
Start-Sleep -Seconds 30  # Aumentado para dar tiempo a generar claves

# 7. Verificar y mostrar información final
$keyPath = ".\data\id_ed25519.pub"
if (Test-Path $keyPath) {
  $publicKey = Get-Content -Path $keyPath
} else {
  Write-Warning "No se pudo encontrar el archivo de clave pública. Revisa los logs:"
  docker-compose logs hbbs
  exit 1
}

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "¡Instalación completada!" -ForegroundColor Green
Write-Host "`nTu servidor RustDesk está funcionando en: $serverAddress"
Write-Host "Configura en el cliente: ID server = $serverAddress:21116, Relay server = $serverAddress:21117"
Write-Host "Las reglas del firewall de Windows han sido configuradas automáticamente." -ForegroundColor Green
Write-Host "`nCopia la siguiente clave pública en tu cliente de RustDesk:"
Write-Host "Clave pública: $publicKey" -ForegroundColor White
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Si hay problemas de conexión, verifica 'docker-compose logs hbbs' y asegúrate de que los ports estén forwarded en tu router." -ForegroundColor Yellow