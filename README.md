# 🚀 Administración de Sistemas  
## Automatización y Gestión de Servicios de Red

Este repositorio implementa un **ecosistema de automatización para despliegue, configuración y aseguramiento de servicios de red** en entornos híbridos. La solución integra **Linux Fedora Server** y **Windows Server 2022**, aplicando principios de modularización, administración remota y separación de responsabilidades.

El sistema permite configurar servicios críticos de infraestructura (SSH, DNS y DHCP) mediante scripts organizados en módulos reutilizables, diseñados para operar en entornos de servidor reales sin interfaz física.

---

## 🧩 Arquitectura del Sistema

La arquitectura sigue un enfoque **modular y desacoplado**, donde:

- La lógica de negocio se encapsula en módulos reutilizables.
- Los scripts principales funcionan únicamente como orquestadores.
- La administración del sistema se realiza de forma remota vía SSH.
- El diseño cumple principios de refactorización y buenas prácticas de administración de sistemas.

---

## 📂 Estructura del Proyecto

### 🐧 `/linux` — Automatización para Fedora Server

Contiene los scripts de despliegue y configuración para el nodo Linux.

**Archivo principal**

- `main.sh`  
  Orquestador del sistema. Proporciona interfaz de usuario basada en menú e invoca los módulos funcionales.

**Directorio `modules/`**

- `core_utils.sh`  
  Funciones base del sistema: validación de privilegios root, manejo de errores y registro de eventos.

- `ssh_functions.sh`  
  Instalación, configuración y aseguramiento del servicio OpenSSH.

- `dns_functions.sh`  
  Biblioteca modular para configuración del servicio DNS.

- `dhcp_functions.sh`  
  Biblioteca modular para configuración del servicio DHCP.

---

### 🪟 `/windows` — Automatización para Windows Server 2022

Contiene la automatización basada en PowerShell para la administración del nodo Windows.

**Archivo principal**

- `Main.ps1`  
  Script de entrada con interfaz de consola que coordina la ejecución de módulos.

**Directorio `modules/`**

- `CoreUtils.ps1`  
  Validación de privilegios de Administrador y utilidades del sistema.

- `SSHFunctions.ps1`  
  Instalación de OpenSSH, configuración del servicio y reglas de Firewall.

- `DNSFunctions.ps1`  
  Gestión modular del rol DNS en Windows Server.

- `DHCPFunctions.ps1`  
  Gestión modular del rol DHCP en Windows Server.

---

### 📄 `/docs` — Documentación Técnica

- `arquitectura.md`  
  Análisis técnico del proceso de refactorización y comparativa estructural.

- `guia_ssh.md`  
  Manual de administración remota tras la deshabilitación del acceso físico.

---

## 🛠️ Principios de Desarrollo Aplicados

### Modularización (DRY)
Ninguna operación de configuración se repite. Las tareas reutilizables se implementan como funciones.

### Encapsulamiento
Los scripts principales no contienen lógica de configuración directa; únicamente coordinan módulos.

### Administración Headless
El sistema está diseñado para operar sin acceso físico una vez habilitado SSH, simulando un entorno de servidor productivo.

### Separación de Responsabilidades
Interfaz de usuario, lógica de negocio y utilidades del sistema están desacopladas.

---

## 🚀 Instalación y Uso

### 1️⃣ Clonar el repositorio

```bash
git clone https://github.com/GerardoVAZNAV7/Administracion_Sistemas.git
cd Administracion_Sistemas
```

---

### 2️⃣ Ejecución en Linux

Otorgar permisos y ejecutar el orquestador:

```bash
chmod +x linux/main.sh
sudo ./linux/main.sh
```

---

### 3️⃣ Ejecución en Windows

Ejecutar PowerShell como Administrador y lanzar el script:

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\windows\Main.ps1
```

---

## 🌐 Administración Remota del Sistema

Una vez configurado el servicio SSH, la administración del sistema se realiza exclusivamente de forma remota.

**Conexiones de ejemplo**

```bash
ssh administrador@192.168.100.10   # Nodo Linux
ssh administrador@192.168.100.20   # Nodo Windows
```

Tras este punto, el acceso físico a las máquinas virtuales deja de ser necesario.

---

## 🎯 Objetivos del Proyecto

- Automatizar despliegue de servicios de red en entornos híbridos.
- Aplicar principios de ingeniería de software a la administración de sistemas.
- Simular infraestructura de servidor real administrada remotamente.
- Implementar arquitectura modular mantenible y escalable.