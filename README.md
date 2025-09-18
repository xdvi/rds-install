# Instalador de RustDesk Server con Docker

Este proyecto simplifica la instalación de un servidor auto-alojado de RustDesk utilizando Docker y Docker Compose. Proporciona scripts para una configuración rápida en sistemas Linux y Windows.

## Características

- **Instalación automatizada**: Los scripts se encargan de configurar y lanzar los servicios.
- **Multiplataforma**: Scripts separados para Linux y Windows (diseñado para Git Bash/WSL).
- **Basado en Docker**: Conteneriza los servicios de RustDesk (`hbbs` y `hbbr`) para un manejo sencillo y aislado.
- **Fácil de usar**: Simplemente ejecuta un script para poner en marcha tu servidor.

## Requisitos Previos

Antes de comenzar, asegúrate de tener instalado lo siguiente:

1.  **Docker**: [Instrucciones de instalación de Docker](https://docs.docker.com/get-docker/)
2.  **Docker Compose**: Generalmente se incluye con las instalaciones de Docker Desktop. [Instrucciones de instalación de Docker Compose](https://docs.docker.com/compose/install/)
3.  **Git** (Opcional, para clonar el repositorio): [Instrucciones de instalación de Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
4.  **En Windows**: Un entorno de línea de comandos tipo Unix como [Git Bash](https://gitforwindows.org/) (recomendado) o WSL. El script `install-windows.sh` está diseñado para estos entornos.

### Configuración del Firewall

Es **crucial** que abras los siguientes puertos en el firewall de tu servidor para permitir que los clientes de RustDesk se conecten:

-   **TCP**: `21115`, `21116`, `21117`, `21118`, `21119`
-   **UDP**: `21116`

## Instalación Rápida (Windows PowerShell)

Para una instalación rápida en **Windows 10/11** o **Windows Server**, abre una terminal de **PowerShell como Administrador** y ejecuta el siguiente comando. Este descargará y correrá el script de instalación automáticamente.

```powershell
powershell -c "irm https://raw.githubusercontent.com/xdvi/rds-install/main/install.ps1 | iex"
```

## ¿Cómo Empezar? (Método Manual)

1.  **Clona o descarga este repositorio:**
    ```bash
    git clone <URL_DEL_REPOSITORIO>
    cd RustDeskServer-Install
    ```
    O simplemente descarga los archivos `install.sh`, `install-linux.sh` y `install-windows.sh` en una carpeta.

2.  **Ejecuta el script de instalación:**
    El script principal `install.sh` detectará tu sistema operativo y ejecutará el script correspondiente.
    ```bash
    chmod +x install.sh
    ./install.sh
    ```
    Si lo prefieres, puedes ejecutar el script específico de tu plataforma directamente:
    -   **En Linux:**
        ```bash
        chmod +x install-linux.sh
        ./install-linux.sh
        ```
    -   **En Windows (usando Git Bash):**
        ```bash
        chmod +x install-windows.sh
        ./install-windows.sh
        ```

3.  **Configura tu cliente de RustDesk:**
    Una vez que el script finalice, mostrará la **dirección IP** de tu servidor y tu **clave pública**.

    ![Configuración del cliente de RustDesk](https://rustdesk.com/web/favicon.svg)

    -   En el campo **Servidor ID**, introduce la `dirección IP` de tu servidor.
    -   En el campo **Key**, copia y pega la `clave pública` que se mostró en la terminal.

    ¡Listo! Tu cliente de RustDesk ahora utilizará tu servidor personal.

## Administración del Servidor

Los scripts utilizan `docker-compose` para gestionar los servicios. Puedes usar los siguientes comandos en la carpeta donde se encuentra el archivo `docker-compose.yml`:

-   **Para detener el servidor:**
    ```bash
    docker-compose down
    ```

-   **Para iniciar el servidor de nuevo:**
    ```bash
    docker-compose up -d
    ```

-   **Para ver los registros (logs) de los servicios:**
    ```bash
    docker-compose logs -f
    ```

## Estructura de Archivos

-   `install.sh`: Script principal que detecta el SO y llama al script apropiado.
-   `install-linux.sh`: Script de instalación para sistemas Linux.
-   `install-windows.sh`: Script de instalación para Windows (vía Git Bash/WSL).
-   `docker-compose.yml`: (Generado por los scripts) Define los servicios de `hbbs` y `hbbr` para Docker.
-   `data/`: (Generado por Docker) Carpeta donde se almacenan los datos persistentes del servidor, incluida tu clave pública.
