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

### Adaptador 1 – Red Interna
- Nombre de red: `intnet-lab`
- Red aislada para comunicación entre nodos
- Direccionamiento IP estático
- 
### Adaptador 2 – NAT
- Proporciona salida a Internet
- Usado para actualizaciones y descarga de paquetes
- Configurado mediante DHCP



### Tabla de Direccionamiento IP

| Equipo | Interfaz | Dirección IP | Máscara |
|-----|---------|-------------|--------|
| Fedora Server | Red Interna | 192.168.100.10 | /24 |
| Windows Server 2022 | Red Interna | 192.168.100.20 | /24 |
| Ubuntu Client | Red Interna | 192.168.100.30 | /24 |

>  La red interna **no utiliza gateway**, ya que no requiere salida a Internet.

---

### Scripts incluidos:
- `tarea1_diagnostico.sh` → Linux (Fedora)
- `tarea1_diagnostico.ps1` → Windows Server (PowerShell)

---



