#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Instala el servidor de RustDesk usando Docker y configura el firewall de Windows.
.DESCRIPTION
    Este script automatiza la instalación de un servidor auto-alojado de RustDesk.
    Verifica los prerrequisitos, ofrece instalar Docker, configura el firewall, y lanza los contenedores.
.NOTES
    Autor: Gemini
    Fecha: 2025-09-18
#>

# --- FUNCIONES ---

function Install-Docker {
    Write-Host "Iniciando la instalación de Docker Desktop..." -ForegroundColor Cyan
    Write-Host "Esto puede tardar varios minutos."

    # Habilitar características de Windows necesarias
    Write-Host "Habilitando Hyper-V y la plataforma de Contenedores..."
    dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart
    dism.exe /online /enable-feature /featurename:Containers /all /norestart
    
    # Instalar WSL (Subsistema de Windows para Linux)
    Write-Host "Instalando el Subsistema de Windows para Linux (WSL)..."
    wsl --install -d Ubuntu

    # Descargar Docker Desktop
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-Host "Descargando el instalador de Docker Desktop..."
    Invoke-WebRequest -UseBasicParsing -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $installerPath

    # Instalar Docker Desktop en modo silencioso
    Write-Host "Instalando Docker Desktop... Por favor, espera a que finalice."
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet" -Wait

    # Limpiar el instalador
    Remove-Item $installerPath
}

function Test-Docker {
    try {
        docker info > $null
        return $true
    } catch {
        return $false
    }
}

function Get-HostIpAddress {
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
              Where-Object { $_.InterfaceAlias -notlike 'Loopback*' -and $_.InterfaceAlias -notlike 'vEthernet*' } |
              Select-Object -First 1 |
              ForEach-Object { $_.IPAddress }
        if ($ip) {
            return $ip
        } else {
            $ip = (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString
            return $ip
        }
    } catch {
        Write-Warning "No se pudo determinar automáticamente la dirección IP."
        return $null
    }
}

function Set-FirewallRules {
    Write-Host "Configurando las reglas del Firewall de Windows..." -ForegroundColor Cyan
    $tcpPorts = "21115-21119"
    $udpPorts = "21116"
    $tcpRuleName = "RustDesk Server (TCP)"
    $udpRuleName = "RustDesk Server (UDP)"

    if (-not (Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue)) {
        Write-Host "Creando regla de firewall para TCP en los puertos $tcpPorts..."
        New-NetFirewallRule -DisplayName $tcpRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $tcpPorts
        Write-Host "Regla TCP '$tcpRuleName' creada." -ForegroundColor Green
    } else {
        Write-Host "La regla de firewall TCP '$tcpRuleName' ya existe." -ForegroundColor Yellow
    }

    if (-not (Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue)) {
        Write-Host "Creando regla de firewall para UDP en el puerto $udpPorts..."
        New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Action Allow -Protocol UDP -LocalPort $udpPorts
        Write-Host "Regla UDP '$udpRuleName' creada." -ForegroundColor Green
    } else {
        Write-Host "La regla de firewall UDP '$udpRuleName' ya existe." -ForegroundColor Yellow
    }
}


# --- INICIO DEL SCRIPT ---

Write-Host "Iniciando el instalador del servidor RustDesk para Windows..." -ForegroundColor Cyan

# 1. Verificar y/u ofrecer instalación de Docker
Write-Host "Verificando que Docker esté en ejecución..."
if (-not (Test-Docker)) {
    $choice = Read-Host "Docker no está detectado. ¿Desea instalar Docker Desktop? (Y/n)"
    if ($choice -eq 'y' -or $choice -eq 'Y') {
        Install-Docker
        Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "ACCIÓN REQUERIDA: Docker Desktop ha sido instalado." -ForegroundColor Green
        Write-Host "Por favor, REINICIA TU COMPUTADORA y vuelve a ejecutar este script para completar la instalación de RustDesk Server."
        Write-Host "----------------------------------------------------------------" -ForegroundColor Yellow
        exit
    } else {
        Write-Error "La instalación no puede continuar sin Docker. Saliendo."
        exit 1
    }
}
Write-Host "Docker está listo." -ForegroundColor Green

# 2. Configurar Firewall
Set-FirewallRules

# 3. Obtener la dirección IP
Write-Host "Obteniendo la dirección IP del host..."
$ipAddress = Get-HostIpAddress
if (-not $ipAddress) {
    $ipAddress = Read-Host -Prompt "Por favor, introduce manually la dirección IP de este servidor"
    if (-not $ipAddress) {
        Write-Error "La dirección IP es necesaria para continuar. Saliendo."
        exit 1
    }
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
Write-Host "Iniciando los servicios de RustDesk con docker-compose... (esto puede tardar un momento)"
docker-compose up -d

Write-Host "Esperando a que los servicios se inicien y generen la clave..."
Start-Sleep -Seconds 15

# 6. Mostrar información final
$keyPath = ".\data\id_ed25519.pub"
if (-not (Test-Path $keyPath)) {
    Write-Warning "No se pudo encontrar el archivo de clave pública. Puede que los contenedores aún se estén iniciando."
    Write-Warning "Ejecuta 'docker-compose logs hbbs' para ver el estado."
    exit 1
}

$publicKey = Get-Content -Path $keyPath

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "¡Instalación completada!" -ForegroundColor Green
Write-Host "`nTu servidor RustDesk está funcionando en: $ipAddress"
Write-Host "Las reglas del firewall de Windows han sido configuradas automáticamente." -ForegroundColor Green
Write-Host "`nCopia la siguiente clave pública en tu cliente de RustDesk:"
Write-Host "Clave pública: $publicKey" -ForegroundColor White
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
