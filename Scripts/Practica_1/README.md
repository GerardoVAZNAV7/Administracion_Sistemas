# Práctica 1 – Entorno de Red Virtualizado y Diagnóstico Inicial

##  Descripción General
En esta práctica se implementa un entorno de red virtualizado compuesto por **tres nodos funcionales**, con el objetivo de garantizar la **comunicación bidireccional**, el **aislamiento de red** y la **preparación de los sistemas operativos para tareas de automatización y diagnóstico**.

El laboratorio fue desarrollado utilizando un hipervisor de virtualización y sistemas operativos de servidor y cliente, cumpliendo con los lineamientos técnicos establecidos.

---

##  Infraestructura del Laboratorio

### Hipervisor
- **VirtualBox**

### Nodos Implementados
| Nodo | Sistema Operativo | Rol |
|----|------------------|----|
| Nodo 1 | Fedora Server | Servidor Linux (CLI) |
| Nodo 2 | Windows Server 2022 | Servidor Windows |
| Nodo 3 | Ubuntu Desktop | Cliente |

---

##  Configuración de Red

Cada máquina virtual cuenta con **dos adaptadores de red**:

### Adaptador 1 – NAT
- Proporciona salida a Internet
- Usado para actualizaciones y descarga de paquetes
- Configurado mediante DHCP

### Adaptador 2 – Red Interna
- Nombre de red: `intnet-lab`
- Red aislada para comunicación entre nodos
- Direccionamiento IP estático

### Tabla de Direccionamiento IP

| Equipo | Interfaz | Dirección IP | Máscara |
|-----|---------|-------------|--------|
| Fedora Server | Red Interna | 192.168.100.10 | /24 |
| Windows Server 2022 | Red Interna | 192.168.100.20 | /24 |
| Ubuntu Client | Red Interna | 192.168.100.30 | /24 |

>  La red interna **no utiliza gateway**, ya que no requiere salida a Internet.

---

##  Actividades Realizadas

### ✔ Configuración Inicial
- Asignación de nombres de host descriptivos
- Actualización de paquetes del sistema
- Ajuste de interfaces de red
- Verificación de ruteo correcto

### ✔ Snapshots
- Se creó una instantánea denominada **Estado Base** en cada máquina virtual
- Permite restaurar el sistema a un punto estable inicial

### ✔ Pruebas de Conectividad
- Comunicación bidireccional mediante `ping` entre los tres nodos
- Validación completa de la red interna aislada

--

##  Scripts de Diagnóstico

Se desarrollaron scripts para mostrar información básica del sistema:

### Información mostrada:
- Nombre del equipo
- Dirección IP activa
- Espacio en disco disponible

### Scripts incluidos:
- `tarea1_diagnostico.sh` → Linux (Fedora)
- `tarea1_diagnostico.ps1` → Windows Server (PowerShell)

---



