# 🔐 Práctica: RBAC + MFA en Windows Server 2022 (Sin GUI)
### Guía Completa de Implementación — Paso a Paso

> **Entorno:** Windows Server 2022 Core (sin interfaz gráfica) + Cliente Windows 10 Pro  
> **Objetivo:** Implementar RBAC con 4 roles delegados, FGPP, auditoría de eventos y MFA con Google Authenticator.

---

## 📋 Tabla de Contenidos

1. [Resumen de Scripts y Orden de Ejecución](#1-resumen-de-scripts-y-orden-de-ejecución)
2. [Preparación del Entorno](#2-preparación-del-entorno)
3. [Script 01 — Crear Estructura de Active Directory](#3-script-01--crear-estructura-de-active-directory)
4. [Script 02 — Configurar Delegación y ACLs](#4-script-02--configurar-delegación-y-acls-rbac)
5. [Script 03 — Fine-Grained Password Policy](#5-script-03--fine-grained-password-policy-fgpp)
6. [Script 04 — Hardening de Auditoría](#6-script-04--hardening-de-auditoría)
7. [Script 05 — Script de Monitoreo de Eventos](#7-script-05--script-de-monitoreo-de-eventos)
8. [Script 06 — Instalación y Configuración de MFA](#8-script-06--instalación-y-configuración-de-mfa)
9. [Script 07 — Verificación de los 5 Tests](#9-script-07--verificación-de-los-5-tests)
10. [Pasos Manuales Obligatorios](#10-pasos-manuales-obligatorios)
11. [Resolución de Problemas Comunes](#11-resolución-de-problemas-comunes)
12. [Evidencias Requeridas para el Reporte](#12-evidencias-requeridas-para-el-reporte)

---

## 1. Resumen de Scripts y Orden de Ejecución

Ejecuta los scripts **en este orden exacto** desde PowerShell en el servidor:

| # | Archivo | Qué hace | Dónde ejecutar |
|---|---------|----------|----------------|
| 1 | `01_Crear_Estructura_AD.ps1` | Crea OUs, grupos de seguridad, usuarios admin y usuarios de prueba | Servidor (como Domain Admin) |
| 2 | `02_Configurar_Delegacion_ACL.ps1` | Asigna permisos granulares con `dsacls` para los 4 roles RBAC | Servidor (como Domain Admin) |
| 3 | `03_Configurar_FGPP.ps1` | Crea políticas de contraseña diferenciadas (12 chars admins / 8 chars usuarios) | Servidor (como Domain Admin) |
| 4 | `04_Configurar_Auditoria.ps1` | Habilita `auditpol` y crea GPO de auditoría | Servidor (como Domain Admin) |
| 5 | `05_Script_Monitoreo_Eventos.ps1` | Extrae los 10 últimos eventos de acceso denegado y los exporta a .txt y .csv | Servidor (cualquier momento) |
| 6 | `06_Instalar_MFA_WinOTP.ps1` | Instala WinOTP, genera secretos TOTP, configura bloqueo 3 intentos/30 min | Servidor (como Administrator) |
| 7 | `07_Verificar_Tests.ps1` | Verifica automáticamente los 5 tests de la práctica | Servidor (como Domain Admin) |

---

## 2. Preparación del Entorno

### 2.1 Acceder al servidor sin GUI

Desde tu cliente Windows 10, conéctate al servidor por PowerShell Remoting o RDP:

```powershell
# Opción A: PowerShell Remoting
Enter-PSSession -ComputerName 192.168.X.X -Credential (Get-Credential)

# Opción B: RDP (aunque no tenga GUI completa, el Server Core sí admite RDP básico)
mstsc /v:192.168.X.X
```

### 2.2 Copiar los scripts al servidor

Desde tu cliente Windows 10, copia la carpeta de scripts al servidor:

```powershell
# Desde el cliente Windows 10 (PowerShell)
$Session = New-PSSession -ComputerName 192.168.X.X -Credential (Get-Credential)

# Copiar todos los scripts
Copy-Item -Path "C:\practica-rbac-mfa\*" -Destination "C:\Scripts\" -ToSession $Session -Recurse

# Cerrar sesión de copia
Remove-PSSession $Session
```

### 2.3 Verificar que Active Directory está instalado

En el servidor, ejecuta:

```powershell
# Verificar que el rol AD DS está instalado
Get-WindowsFeature -Name AD-Domain-Services

# Verificar que el módulo de AD está disponible
Import-Module ActiveDirectory
Get-ADDomain
```

Si el dominio no está configurado aún, primero debes promover el servidor como Controlador de Dominio:

```powershell
# Instalar el rol (si no está instalado)
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promover como DC (NUEVO DOMINIO - ajusta el nombre)
Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "SafeMode123!" -AsPlainText -Force) `
    -InstallDns `
    -Force
# El servidor se reiniciará automáticamente
```

### 2.4 Establecer política de ejecución de scripts

```powershell
# Permitir ejecución de scripts locales
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

---

## 3. Script 01 — Crear Estructura de Active Directory

**Archivo:** `01_Crear_Estructura_AD.ps1`

### ¿Qué hace este script?

- Crea las **Unidades Organizativas (OU)**: `Cuates`, `NoCuates`, `AdminsDelegados`, `GruposSeguridad`
- Crea una sub-OU `UsuariosTest` dentro de `Cuates` para las pruebas
- Crea **4 grupos de seguridad** correspondientes a cada rol RBAC
- Crea el grupo `GRP_AdminsPrivilegio` para aplicar la FGPP de 12 caracteres
- Crea los **4 usuarios administradores delegados** con sus contraseñas iniciales
- Crea **4 usuarios de prueba** en las OUs Cuates y NoCuates

### Cómo ejecutarlo

```powershell
cd C:\Scripts
.\01_Crear_Estructura_AD.ps1
```

### Verificar que funcionó

```powershell
# Ver las OUs creadas
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName

# Ver los usuarios creados
Get-ADUser -Filter * -SearchBase "OU=AdminsDelegados,DC=lab,DC=local" | Select-Object Name, SamAccountName, Enabled

# Ver los grupos creados
Get-ADGroup -Filter { Name -like "GRP_*" } | Select-Object Name, GroupScope
```

### Credenciales creadas

| Usuario | Contraseña inicial | Rol |
|---------|-------------------|-----|
| `admin_identidad` | `P@ssw0rd.Admin2024!` | IAM Operator |
| `admin_storage` | `P@ssw0rd.Admin2024!` | Storage Operator |
| `admin_politicas` | `P@ssw0rd.Admin2024!` | GPO Compliance |
| `admin_auditoria` | `P@ssw0rd.Admin2024!` | Security Auditor |
| `usuario.cuate1` | `User1234!` | Prueba (OU Cuates) |
| `usuario.cuate2` | `User1234!` | Prueba (OU Cuates) |
| `usuario.nocuate1` | `User1234!` | Prueba (OU NoCuates) |
| `usuario.nocuate2` | `User1234!` | Prueba (OU NoCuates) |

> ⚠️ **Nota:** La contraseña `P@ssw0rd.Admin2024!` tiene 20 caracteres, cumple la FGPP de 12 caracteres mínimo.

---

## 4. Script 02 — Configurar Delegación y ACLs (RBAC)

**Archivo:** `02_Configurar_Delegacion_ACL.ps1`

### ¿Qué hace este script?

Configura los **permisos granulares** de cada rol usando la herramienta `dsacls` (Discretionary ACL tool para Active Directory):

#### ROL 1 — `admin_identidad` (IAM Operator)
Se le conceden sobre `OU=Cuates` y `OU=NoCuates`:
- `CC;user` → Crear objetos de usuario (CreateChild)
- `DC;user` → Eliminar objetos de usuario (DeleteChild)
- `WP;telephoneNumber;user` → Modificar teléfono
- `WP;mail;user` → Modificar correo
- `WP;physicalDeliveryOfficeName;user` → Modificar oficina
- `CA;Reset Password;user` → Restablecer contraseñas
- `WP;lockoutTime;user` y `WP;userAccountControl;user` → Desbloquear cuentas

#### ROL 2 — `admin_storage` (Storage Operator)
**DENEGACIÓN CRÍTICA** en todas las OUs:
- `DENY CA;Reset Password;user` → **NO puede** resetear contraseñas (esto valida el Test 1)

#### ROL 3 — `admin_politicas` (GPO Compliance)
- Lectura en todo el dominio (`GR` sobre `$DomainDN`)
- Escritura sobre `groupPolicyContainer` en `CN=Policies,CN=System`
- Permiso `gpLink` y `gpOptions` sobre OUs (para vincular/desvincular GPOs)

#### ROL 4 — `admin_auditoria` (Security Auditor)
- Lectura global en el dominio (`GR`)
- Agregado al grupo `Event Log Readers` (acceso a Visor de Eventos)

### Cómo ejecutarlo

```powershell
.\02_Configurar_Delegacion_ACL.ps1
```

### Verificar que funcionó

```powershell
# Ver los ACLs aplicados en OU=Cuates
(Get-Acl "AD:OU=Cuates,DC=lab,DC=local").Access | 
    Where-Object { $_.IdentityReference -like "*admin_*" } |
    Format-Table IdentityReference, ActiveDirectoryRights, AccessControlType -AutoSize

# También puedes usar dsacls para ver
dsacls "OU=Cuates,DC=lab,DC=local"
```

> ⚠️ **Importante:** El símbolo `/I:S` en dsacls significa "Inherit to Sub-objects" (hereda a objetos dentro de la OU). El `/I:T` significa "hereda a todos los objetos" incluyendo la OU misma.

---

## 5. Script 03 — Fine-Grained Password Policy (FGPP)

**Archivo:** `03_Configurar_FGPP.ps1`

### ¿Qué hace este script?

Crea dos políticas de contraseña distintas (que reemplazan la Default Domain Policy para grupos específicos):

| Política | Grupo Aplicado | Min. Chars | Bloqueo | Prioridad |
|----------|---------------|------------|---------|-----------|
| `PSO_AdminsPrivilegiados` | `GRP_AdminsPrivilegio` | **12** | 3 intentos / 30 min | **10** (más alta) |
| `PSO_UsuariosEstandar` | Referencia general | **8** | 5 intentos / 15 min | 50 (más baja) |

> 📌 **Cómo funciona la prioridad:** El número de `Precedence` más **bajo** tiene **mayor prioridad**. Si un usuario pertenece a dos grupos con PSO, gana el de precedencia más baja (10 < 50).

### Cómo ejecutarlo

```powershell
.\03_Configurar_FGPP.ps1
```

Al final del script se ejecuta automáticamente el **Test 2**: intenta poner una contraseña de 8 caracteres a `admin_identidad`. Debe mostrar:
```
[CORRECTO] La contraseña de 8 caracteres fue RECHAZADA para admin_identidad.
```

### Verificar manualmente

```powershell
# Ver las PSOs creadas
Get-ADFineGrainedPasswordPolicy -Filter * | Format-Table Name, Precedence, MinPasswordLength

# Ver a quién aplica cada PSO
Get-ADFineGrainedPasswordPolicySubject -Identity "PSO_AdminsPrivilegiados"

# Ver qué PSO aplica a un usuario específico
Get-ADUserResultantPasswordPolicy -Identity "admin_identidad"
```

---

## 6. Script 04 — Hardening de Auditoría

**Archivo:** `04_Configurar_Auditoria.ps1`

### ¿Qué hace este script?

Habilita las categorías de auditoría usando `auditpol` (herramienta de línea de comandos para políticas de auditoría):

| Categoría | Éxito | Fallo | Para qué sirve |
|-----------|-------|-------|----------------|
| Logon | ✅ | ✅ | Detectar inicios de sesión fallidos (ID 4625) |
| Credential Validation | ✅ | ✅ | Validación de credenciales Kerberos/NTLM |
| User Account Management | ✅ | ✅ | Cambios en cuentas de usuario |
| Directory Service Access | ✅ | ✅ | Acceso a objetos de AD |
| Directory Service Changes | ✅ | ✅ | Modificaciones en AD |
| File System | ✅ | ✅ | Acceso a archivos (para FSRM) |
| Audit Policy Change | ✅ | ✅ | Si alguien modifica la política de auditoría |

También crea una GPO llamada `GPO_HardeningAuditoria` y la vincula al dominio, configurando el Security Log con un tamaño máximo de 50 MB.

### Cómo ejecutarlo

```powershell
.\04_Configurar_Auditoria.ps1
```

### Verificar que funcionó

```powershell
# Ver el estado de las auditorías habilitadas
auditpol /get /category:*

# Ver el estado específico de Logon
auditpol /get /subcategory:"Logon"
```

---

## 7. Script 05 — Script de Monitoreo de Eventos

**Archivo:** `05_Script_Monitoreo_Eventos.ps1`

### ¿Qué hace este script?

Extrae del **Visor de Eventos (Event Log)** los últimos 10 eventos de acceso denegado, buscando tres tipos de eventos:

| Event ID | Significado |
|----------|-------------|
| **4625** | Inicio de sesión fallido (contraseña incorrecta, cuenta bloqueada, etc.) |
| **4656** | Se solicitó acceso a un objeto pero fue denegado |
| **4740** | Cuenta de usuario bloqueada por exceso de intentos fallidos |

El script exporta los resultados a dos archivos:
- `C:\AuditLogs\AccesosDenegados_FECHA.txt` → Formato legible para el reporte
- `C:\AuditLogs\AccesosDenegados_FECHA.csv` → Formato tabla para análisis

### Cómo ejecutarlo

```powershell
# Se puede ejecutar en cualquier momento, incluso como admin_auditoria
.\05_Script_Monitoreo_Eventos.ps1

# Verificar que los archivos se crearon
Get-ChildItem C:\AuditLogs\
```

> 💡 **Consejo:** Para que el reporte tenga eventos interesantes, primero genera algunos intentos fallidos (contraseña incorrecta varias veces) y luego ejecuta el script.

---

## 8. Script 06 — Instalación y Configuración de MFA

**Archivo:** `06_Instalar_MFA_WinOTP.ps1`

### ¿Qué hace este script?

Este es el más complejo. Lo que hace:

1. **Descarga e instala WinOTP Credential Provider** — software que agrega un campo extra en la pantalla de login de Windows para el código TOTP
2. **Genera secretos TOTP únicos** para cada usuario administrador (Base32, compatible con Google Authenticator)
3. **Guarda los secretos** en el registro de Windows bajo `HKLM:\SOFTWARE\WinOTP\Users\`
4. **Verifica** que la FGPP tiene el bloqueo de 3 intentos / 30 minutos

### Cómo ejecutarlo

```powershell
.\06_Instalar_MFA_WinOTP.ps1
```

### ⚠️ Paso manual crítico después del script

Después de ejecutar el script, debes:

**1. Anotar los secretos TOTP generados** (están en `C:\MFA_Setup\TOTP_Secrets.txt`)

```powershell
# Ver los secretos generados
Get-Content C:\MFA_Setup\TOTP_Secrets.txt
```

**2. Configurar Google Authenticator en tu teléfono**

Para cada usuario administrador:
1. Abre **Google Authenticator** en tu móvil
2. Toca el **+** (agregar cuenta)
3. Selecciona **"Ingresar clave de configuración"**
4. Nombre de cuenta: `admin_identidad@lab.local` (o el que corresponda)
5. Clave: pega el **secreto Base32** del archivo `TOTP_Secrets.txt`
6. Tipo: **Basado en tiempo**
7. Toca **Agregar**

**3. Reiniciar el servidor** para que el Credential Provider tome efecto

```powershell
Restart-Computer -Force
```

**4. Si WinOTP no está disponible — Alternativa con WinOTP Standalone**

Si el descargador automático falla, descarga manualmente:
- **WinOTP:** https://github.com/nicowillis/WinOTP
- **Alternativa:** "PrivacyIDEA" o "NetIQ Advanced Authentication Free Edition"

Para instalación manual desde el cliente Windows 10:
```powershell
# Copiar el instalador al servidor
Copy-Item "C:\Descargas\WinOTP-Setup.msi" -Destination "\\SERVER\C$\MFA_Setup\"

# Instalar remotamente
Invoke-Command -ComputerName SERVER -ScriptBlock {
    msiexec /i "C:\MFA_Setup\WinOTP-Setup.msi" /qn /norestart ALLUSERS=1
}
```

### Cómo funciona el MFA técnicamente

```
[Usuario ingresa Usuario + Contraseña]
           ↓
[Windows llama al Credential Provider (WinOTP)]
           ↓
[WinOTP solicita el código TOTP de 6 dígitos]
           ↓
[WinOTP genera el código esperado con el secreto almacenado + tiempo actual]
           ↓
[Compara: código ingresado == código esperado?]
    SI → LSASS procede con el login
    NO → Cuenta suma 1 intento fallido
         Si llegó a 3 → LOCKOUT por 30 minutos
```

---

## 9. Script 07 — Verificación de los 5 Tests

**Archivo:** `07_Verificar_Tests.ps1`

### ¿Qué hace este script?

Ejecuta verificaciones automáticas para los 5 tests requeridos y muestra un resumen de PASS/FAIL al final.

```powershell
.\07_Verificar_Tests.ps1
```

---

## 10. Pasos Manuales Obligatorios

Algunos pasos **no pueden automatizarse** porque requieren iniciar sesión con diferentes usuarios. Aquí están descritos en detalle:

---

### 🧪 Test 1: Verificación de Delegación (acción manual)

**Desde tu cliente Windows 10:**

**Acción A — admin_identidad (debe funcionar):**
```powershell
# Abre una ventana de PowerShell como admin_identidad
runas /user:LAB\admin_identidad powershell

# Dentro de PowerShell como admin_identidad:
Import-Module ActiveDirectory
Set-ADAccountPassword -Identity "usuario.cuate1" `
    -NewPassword (ConvertTo-SecureString "NewPass2024!" -AsPlainText -Force) `
    -Reset

# Resultado esperado: NO hay error → contraseña cambiada exitosamente
Get-ADUser usuario.cuate1 -Properties PasswordLastSet | Select Name, PasswordLastSet
```

**Acción B — admin_storage (debe fallar):**
```powershell
# Abre PowerShell como admin_storage
runas /user:LAB\admin_storage powershell

# Dentro de PowerShell como admin_storage:
Import-Module ActiveDirectory
Set-ADAccountPassword -Identity "usuario.cuate1" `
    -NewPassword (ConvertTo-SecureString "NewPass2024!" -AsPlainText -Force) `
    -Reset

# Resultado esperado: ERROR de acceso denegado
# "Access is denied" o "Insufficient access rights to perform the operation"
```

📸 **Toma capturas comparativas de ambos resultados para el reporte.**

---

### 🧪 Test 2: FGPP (acción manual en ADUC)

Desde tu cliente Windows 10 con las **Remote Server Administration Tools (RSAT)** instaladas:

```powershell
# Instalar RSAT si no está instalado
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

Luego:
1. Abre **Active Directory Users and Computers** (dsa.msc)
2. Navega a `OU=AdminsDelegados`
3. Clic derecho en `admin_identidad` → **Reset Password**
4. Ingresa una contraseña de 8 caracteres como `Test1234`
5. **Resultado esperado:** Error de complejidad/longitud

📸 **Captura del mensaje de error.**

---

### 🧪 Test 3: Flujo MFA (acción en la pantalla de login)

1. Cierra sesión completamente en el servidor (o usa RDP desde el cliente)
2. En la pantalla de login, después de ingresar usuario y contraseña, aparecerá un **campo adicional** para el código de Google Authenticator
3. Abre **Google Authenticator** en tu móvil → copia el código de 6 dígitos
4. Ingresa el código en el campo adicional
5. Login exitoso

📸 **Captura de:**
- La pantalla de login con el campo de código MFA
- Tu móvil mostrando el código de Google Authenticator

---

### 🧪 Test 4: Bloqueo por MFA fallido

1. En la pantalla de login, ingresa usuario y contraseña correctos
2. En el campo de código MFA, ingresa `000000` (incorrecto)
3. Repite **3 veces**
4. Verifica el bloqueo desde el servidor:

```powershell
# Verificar estado de cuenta bloqueada
Get-ADUser admin_identidad -Properties LockedOut, BadLogonCount, BadPasswordTime | 
    Select-Object Name, LockedOut, BadLogonCount, BadPasswordTime

# Resultado esperado: LockedOut = True
```

Para **desbloquear** después de verificar:
```powershell
Unlock-ADAccount -Identity admin_identidad
Write-Host "Cuenta desbloqueada manualmente."
```

📸 **Captura del resultado de Get-ADUser mostrando `LockedOut = True`.**

---

### 🧪 Test 5: Reporte de Auditoría

```powershell
# Ejecutar el script de monitoreo
.\05_Script_Monitoreo_Eventos.ps1

# Ver el archivo generado
Get-Content C:\AuditLogs\AccesosDenegados_*.txt | more
```

📸 **Adjunta el contenido del archivo .txt en el reporte.**

---

## 11. Resolución de Problemas Comunes

### ❌ "El cmdlet no se reconoce" al usar Get-ADUser

**Causa:** El módulo de Active Directory no está cargado.  
**Solución:**
```powershell
Import-Module ActiveDirectory
# O instalar RSAT en el cliente:
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

### ❌ dsacls devuelve error "Access is denied"

**Causa:** No estás ejecutando PowerShell como Domain Admin.  
**Solución:**
```powershell
# Verificar usuario actual
whoami
# Abrir PowerShell como Domain Admin explícitamente
runas /user:LAB\Administrator powershell
```

### ❌ La FGPP no aplica al usuario

**Causa:** El usuario no está en el grupo `GRP_AdminsPrivilegio`.  
**Solución:**
```powershell
# Verificar membresía
Get-ADGroupMember "GRP_AdminsPrivilegio" | Select-Object Name

# Agregar si falta
Add-ADGroupMember -Identity "GRP_AdminsPrivilegio" -Members "admin_identidad"

# Ver qué PSO está aplicando
Get-ADUserResultantPasswordPolicy -Identity "admin_identidad"
```

### ❌ El script de monitoreo no encuentra eventos

**Causa:** La auditoría no ha generado eventos todavía, o el Security Log está vacío.  
**Solución:**
```powershell
# Generar intentos fallidos artificiales (desde otra ventana)
for ($i = 0; $i -lt 5; $i++) {
    $cred = New-Object System.Net.NetworkCredential("usuario.cuate1", "WrongPass")
    $ldap = New-Object DirectoryServices.DirectoryEntry("LDAP://localhost", "usuario.cuate1", "WrongPass")
    $ldap.RefreshCache()
}
# Espera unos segundos y ejecuta el script de monitoreo
```

### ❌ WinOTP no aparece en la pantalla de login

**Causa:** El Credential Provider no se registró correctamente o no se reinició.  
**Solución:**
```powershell
# Verificar que está en el registro
Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" |
    Get-ChildItem | Format-List

# Forzar reinicio
Restart-Computer -Force
```

### ❌ El bloqueo de cuenta no ocurre después de 3 intentos MFA

**Causa:** La PSO de bloqueo no aplica correctamente.  
**Solución:**
```powershell
# Verificar la PSO de admins
Get-ADFineGrainedPasswordPolicy "PSO_AdminsPrivilegiados" | 
    Select-Object LockoutThreshold, LockoutDuration, LockoutObservationWindow

# Si está mal, corregir:
Set-ADFineGrainedPasswordPolicy "PSO_AdminsPrivilegiados" `
    -LockoutThreshold 3 `
    -LockoutDuration (New-TimeSpan -Minutes 30) `
    -LockoutObservationWindow (New-TimeSpan -Minutes 30)
```

---

## 12. Evidencias Requeridas para el Reporte

| Test | Evidencia requerida | Dónde obtenerla |
|------|--------------------|--------------------|
| Test 1A | Captura de PowerShell mostrando éxito al resetear contraseña como `admin_identidad` | Consola como admin_identidad |
| Test 1B | Captura del error "Acceso Denegado" al resetear como `admin_storage` | Consola como admin_storage |
| Test 2 | Captura del error de complejidad en ADUC al intentar 8 chars en `admin_identidad` | Active Directory Users & Computers |
| Test 3 | Foto/captura de la pantalla de login con campo MFA + foto del móvil con Google Auth | Pantalla de login del servidor |
| Test 4 | Captura de `Get-ADUser admin_identidad` mostrando `LockedOut: True` | PowerShell en el servidor |
| Test 5 | El archivo `C:\AuditLogs\AccesosDenegados_FECHA.txt` completo | Resultado de Script 05 |

---

## 📁 Estructura de Archivos Generados

```
C:\
├── Scripts\
│   ├── 01_Crear_Estructura_AD.ps1
│   ├── 02_Configurar_Delegacion_ACL.ps1
│   ├── 03_Configurar_FGPP.ps1
│   ├── 04_Configurar_Auditoria.ps1
│   ├── 05_Script_Monitoreo_Eventos.ps1
│   ├── 06_Instalar_MFA_WinOTP.ps1
│   └── 07_Verificar_Tests.ps1
│
├── AuditLogs\
│   ├── AccesosDenegados_YYYY-MM-DD_HH-mm-ss.txt   ← Reporte legible
│   └── AccesosDenegados_YYYY-MM-DD_HH-mm-ss.csv   ← Reporte tabla
│
└── MFA_Setup\
    ├── TOTP_Secrets.txt   ← Secretos TOTP (¡guardar y eliminar después!)
    └── WinOTP-Setup.msi   ← Instalador
```

---

*Práctica generada para Windows Server 2022 Core + Windows 10 Pro*  
*Dominio de ejemplo: `lab.local` (NetBIOS: `LAB`) — ajusta según tu entorno*
