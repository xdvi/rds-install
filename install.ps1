#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Instala el servidor de RustDesk usando Docker en Windows.
.DESCRIPTION
    Este script automatiza la instalación de un servidor auto-alojado de RustDesk.
    Verifica los prerrequisitos, configura el entorno y lanza los contenedores necesarios.
.NOTES
    Autor: Gemini
    Fecha: 2025-09-18
#>

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
            # Fallback for other scenarios
            $ip = (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString
            return $ip
        }
    } catch {
        Write-Warning "No se pudo determinar automáticamente la dirección IP."
        return $null
    }
}

# --- INICIO DEL SCRIPT ---

Write-Host "Iniciando el instalador del servidor RustDesk para Windows..." -ForegroundColor Cyan

# 1. Verificar prerrequisitos
Write-Host "Verificando que Docker esté en ejecución..."
if (-not (Test-Docker)) {
    Write-Error "Docker no parece estar en ejecución o no está instalado. Por favor, inicia Docker Desktop y vuelve a intentarlo."
    exit 1
}
Write-Host "Docker está listo." -ForegroundColor Green

# 2. Obtener la dirección IP
Write-Host "Obteniendo la dirección IP del host..."
$ipAddress = Get-HostIpAddress
if (-not $ipAddress) {
    $ipAddress = Read-Host -Prompt "Por favor, introduce manualmente la dirección IP de este servidor"
    if (-not $ipAddress) {
        Write-Error "La dirección IP es necesaria para continuar. Saliendo."
        exit 1
    }
}
Write-Host "La IP del servidor se ha establecido en: $ipAddress" -ForegroundColor Green

# 3. Crear el archivo docker-compose.yml
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

# 4. Iniciar los servicios
Write-Host "Iniciando los servicios de RustDesk con docker-compose... (esto puede tardar un momento)"
docker-compose up -d

Write-Host "Esperando a que los servicios se inicien y generen la clave..."
Start-Sleep -Seconds 15

# 5. Mostrar información final
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
Write-Host "Asegúrate de que los puertos TCP 21115-21119 y UDP 21116 están abiertos en tu firewall."
Write-Host "`nCopia la siguiente clave pública en tu cliente de RustDesk:"
Write-Host "Clave pública: $publicKey" -ForegroundColor White
Write-Host "`n----------------------------------------------------------------" -ForegroundColor Yellow
