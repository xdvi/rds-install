#!/bin/bash

# Detectar el sistema operativo
OS="$(uname -s)"

case "${OS}" in
    Linux*)     machine=Linux;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${OS}"
esac

echo "Sistema operativo detectado: ${machine}"

if [ "${machine}" == "Linux" ]; then
    echo "Ejecutando script de instalación para Linux..."
    chmod +x ./install-linux.sh
    ./install-linux.sh
elif [ "${machine}" == "MinGw" ] || [ "${machine}" == "Cygwin" ]; then
    echo "Ejecutando script de instalación para Windows..."
    chmod +x ./install-windows.sh
    ./install-windows.sh
else
    echo "Sistema operativo no compatible. Por favor, ejecute el script apropiado (install-linux.sh o install-windows.sh) manualmente."
    exit 1
fi
