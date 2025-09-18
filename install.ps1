#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Instala el servidor de RustDesk usando Docker en Windows (Escritorio o Server).
.DESCRIPTION
    Este script automatiza la instalación de un servidor auto-alojado de RustDesk.
    Detecta la versión de Windows para ofrecer el instalador de Docker adecuado, configura el firewall, y lanza los contenedores.
.NOTES
    Autor: Gemini
    Fecha: 2025-09-18
#>

# --- FUNCIONES ---

function Install-Docker-Desktop {
    Write-Host "Iniciando la instalación de Docker Desktop..." -ForegroundColor Cyan
    Write-Host "Esto puede tardar varios minutos."
    Write-Host "Habilitando Hyper-V, WSL y la plataforma de Contenedores..."
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart
    dism.exe /online /enable-feature /featurename:Containers /all /norestart
    wsl --install -d Ubuntu

    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-Host "Descargando el instalador de Docker Desktop..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $installerPath

    Write-Host "Instalando Docker Desktop... Por favor, espera a que finalice."
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet" -Wait
    Remove-Item $installerPath
}

function Install-Docker-Server {
    Write-Host "Iniciando la instalación de Docker Engine para Windows Server..." -ForegroundColor Cyan
    
    Write-Host "Instalando el proveedor DockerMsftProvider desde PSGallery..."
    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force -AllowClobber

    Write-Host "Instalando el paquete de Docker..."
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force -Confirm:$false

    Write-Host "Docker Engine se ha instalado."
}

function Test-Docker {
    try {
        docker info > $null; return $true
    } catch {
        return $false
    }
}

function Get-HostIpAddress {
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | Where-Object { $_.InterfaceAlias -notlike 'Loopback*' -and $_.InterfaceAlias -notlike 'vEthernet*' } | Select-Object -First 1 | ForEach-Object { $_.IPAddress }
        if ($ip) { return $ip }
        else { return (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString }
    } catch {
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
    } else { Write-Host "La regla de firewall TCP '$tcpRuleName' ya existe." -ForegroundColor Yellow }

    if (-not (Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $udpPorts
        Write-Host "Regla UDP '$udpRuleName' creada." -ForegroundColor Green
    } else { Write-Host "La regla de firewall UDP '$udpRuleName' ya existe." -ForegroundColor Yellow }
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
        } else {
            Install-Docker-Desktop
        }

        Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "ACCIÓN REQUERIDA: La instalación de Docker ha finalizado." -ForegroundColor Green
        Write-Host "Por favor, REINICIA TU COMPUTADORA y vuelve a ejecutar este script para completar la instalación de RustDesk Server."
        Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
        exit
    } else {
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
Write-Host "Iniciando los servicios de RustDesk con docker-compose..."
docker-compose up -d
Start-Sleep -Seconds 15

# 6. Mostrar información final
$keyPath = ".\data\id_ed25519.pub"
if (-not (Test-Path $keyPath)) {
    Write-Warning "No se pudo encontrar el archivo de clave pública. Revisa los logs con 'docker-compose logs hbbs'"; exit 1
}
$publicKey = Get-Content -Path $keyPath

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "¡Instalación completada!" -ForegroundColor Green
Write-Host "`nTu servidor RustDesk está funcionando en: $ipAddress"
Write-Host "Las reglas del firewall de Windows han sido configuradas automáticamente." -ForegroundColor Green
Write-Host "`nCopia la siguiente clave pública en tu cliente de RustDesk:"
Write-Host "Clave pública: $publicKey" -ForegroundColor White
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
