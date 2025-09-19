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

  # 2. Descargar e instalar Docker Engine
  Write-Host "Descargando el instalador de Docker Engine..." -ForegroundColor Cyan
  $installerUrl = "https://download.docker.com/win/static/stable/x86_64/docker-24.0.7.zip"
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

  # 3. Instalar Docker Compose v2 como plugin
  Write-Host "Instalando el plugin Docker Compose v2..." -ForegroundColor Cyan
  $composePluginDir = "C:\ProgramData\Docker\cli-plugins"
  if (-not (Test-Path $composePluginDir)) { New-Item -ItemType Directory -Path $composePluginDir -Force }
  $composeUrl = "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-windows-x86_64.exe"
  $composePath = "$composePluginDir\docker-compose.exe"
  Invoke-WebRequest -Uri $composeUrl -OutFile $composePath

  # Limpiar archivos temporales
  Remove-Item $installerPath -Force
  Remove-Item "$env:TEMP\docker" -Recurse -Force

  Write-Host "Instalación de Docker y Compose finalizada. Intentando iniciar el servicio..." -ForegroundColor Green
  Start-Service Docker -ErrorAction SilentlyContinue
}

function Test-Docker {
  try {
    docker info > $null; return $true
  }
  catch {
    return $false
  }
}

function Get-HostIpAddress {
  try {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | Where-Object { $_.InterfaceAlias -notlike 'Loopback*' -and $_.InterfaceAlias -notlike 'vEthernet*' } | Select-Object -First 1 | ForEach-Object { $_.IPAddress }
    if ($ip) { return $ip }
    else { return (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString }
  }
  catch {
    Write-Warning "No se pudo determinar automáticamente la dirección IP."; return $null
  }
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

# 2. Configurar Firewall
Set-FirewallRules

# 3. Obtener la dirección IP
Write-Host "Obteniendo la dirección IP del host..."
$ipAddress = Get-HostIpAddress
if (-not $ipAddress) {
  $ipAddress = Read-Host -Prompt "Por favor, introduce manualmente la dirección IP de este servidor"
  if (-not $ipAddress) { Write-Error "La dirección IP es necesaria para continuar. Saliendo."; exit 1 }
}
Write-Host "La IP del servidor se ha establecido en: $ipAddress" -ForegroundColor Green

# 4. Crear el archivo docker-compose.yml
$composeContent = @"
version: '3'
services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server
    command: hbbs -r ${ipAddress}:21117
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
    image: rustdesk/rustdesk-server
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

# 5. Iniciar los servicios
Write-Host "Iniciando los servicios de RustDesk con docker compose..."
docker compose up -d
Start-Sleep -Seconds 15

# 6. Mostrar información final
$keyPath = ".\data\id_ed25519.pub"
if (-not (Test-Path $keyPath)) {
  Write-Warning "No se pudo encontrar el archivo de clave pública. Revisa los logs con 'docker compose logs hbbs'"; exit 1
}
$publicKey = Get-Content -Path $keyPath

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "¡Instalación completada!" -ForegroundColor Green
Write-Host "`nTu servidor RustDesk está funcionando en: $ipAddress"
Write-Host "Las reglas del firewall de Windows han sido configuradas automáticamente." -ForegroundColor Green
Write-Host "`nCopia la siguiente clave pública en tu cliente de RustDesk:"
Write-Host "Clave pública: $publicKey" -ForegroundColor White
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
