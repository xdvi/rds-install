#!/bin/bash

# --- Script de instalación de RustDesk Server para Windows (usando Git Bash o similar) ---

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Verificar prerrequisitos (Docker y Docker Compose)
echo "Verificando prerrequisitos..."
if ! command_exists docker; then
    echo "Error: Docker no está instalado. Por favor, instálalo (ej. Docker Desktop) antes de continuar."
    exit 1
fi

if ! command_exists docker-compose; then
    echo "Error: docker-compose no está instalado. Generalmente viene con Docker Desktop."
    exit 1
fi

echo "Prerrequisitos cumplidos."

# 2. Obtener la dirección IP del host
# Intenta obtener la IP de la interfaz Ethernet por defecto. Puede necesitar ajustes.
IP_ADDR=$(ipconfig | findstr /i "IPv4 Address" | findstr /v "127.0.0.1" | awk '{print $NF}' | head -n 1)

if [ -z "$IP_ADDR" ]; then
    echo "Error: No se pudo obtener la dirección IP del host."
    read -p "Por favor, introduce la IP manualmente: " IP_ADDR
    if [ -z "$IP_ADDR" ]; then
        exit 1
    fi
fi

echo "La dirección IP del servidor es: ${IP_ADDR}"

# 3. Crear el archivo docker-compose.yml
echo "Creando el archivo docker-compose.yml..."

cat << EOF > docker-compose.yml
version: '3'

services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server
    command: hbbs -r ${IP_ADDR}:21117
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
EOF

echo "docker-compose.yml creado con éxito."

# 4. Iniciar los contenedores de Docker
echo "Iniciando los servicios de RustDesk Server con Docker Compose..."
docker-compose up -d

echo "Esperando a que los servicios se inicien..."
sleep 10 # Damos un poco más de tiempo en Windows

# 5. Mostrar la clave pública
echo "----------------------------------------------------------------"
echo "Instalación completada."
echo ""
echo "Tu servidor RustDesk está funcionando en: ${IP_ADDR}"
echo "Asegúrate de que los puertos 21115-21119 están abiertos en tu firewall de Windows."
echo ""
echo "Copia la siguiente clave pública en tu cliente de RustDesk:"
echo "Clave pública:"
cat ./data/id_ed25519.pub
echo ""
echo "----------------------------------------------------------------"
