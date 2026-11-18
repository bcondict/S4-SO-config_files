# Documentación de Configuración de Servidor Ubuntu (Proyecto Sistemas Operativos)

Este documento detalla paso a paso la instalación, configuración de red, acceso remoto, compartición de archivos y seguridad aplicados en una máquina virtual con **Ubuntu Server** utilizando **VirtualBox**.

---

## 1. Arquitectura y Entorno Base

- **Hipervisor:** Oracle VM VirtualBox
- **Sistema Operativo Invitado:** Ubuntu Server
- **Usuario del Sistema:** `vmjesus`
- **Modo de Red del Hipervisor:** Adaptador Puente (_Bridged Adapter_) conectado a la interfaz inalámbrica del equipo anfitrión (red móvil compartida).

---

## 2. Configuración de Red e IP Estática (Netplan)

Para permitir que otros equipos de la red local se comuniquen directamente con el servidor sin el aislamiento propio de NAT, se configuró el adaptador de red de la máquina virtual en **Adaptador Puente**.

### Parámetros de Red Identificados

- **Dirección IP Estática del Servidor:** `10.104.14.100/24`
- **Puerta de Enlace (Gateway):** `10.104.14.88`
- **Servidores DNS:** `8.8.8.8`, `1.1.1.1`
- **Interfaz de Red:** `enp0s3`

### Archivo de Configuración (`/etc/netplan/00-installer-config.yaml`)

Se editó el archivo de Netplan utilizando la sintaxis moderna de rutas (`routes`):

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: no
      addresses:
        - 10.104.14.100/24
      routes:
        - to: default
          via: 10.104.14.88
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

### Comandos de Aplicación y Verificación

```bash
sudo netplan apply
sudo systemctl restart systemd-networkd
ip a
ping -c 4 8.8.8.8
```

---

## 3. Instalación y Configuración de Acceso Remoto (SSH)

Para administrar el servidor de forma remota desde la terminal del equipo anfitrión, se instaló y habilitó el servidor OpenSSH.

### Instalación y Activación

```bash
sudo apt update && sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```

### Verificación de Estado y Conexión

```bash
# Verificar servicio en el servidor
sudo systemctl status ssh

# Conectar desde el equipo anfitrión (Windows/Linux/macOS)
ssh vmjesus@10.104.14.100
```

---

## 4. Implementación del Servidor de Archivos (Samba)

Se configuró Samba para compartir un directorio accesible desde clientes Windows en la misma red local.

### Instalación del Paquete

```bash
sudo apt update && sudo apt install samba -y
```

### Creación del Directorio y Asignación de Permisos

Se creó la carpeta compartida en el directorio del usuario y se le asignaron permisos abiertos de lectura y escritura para evitar bloqueos de acceso desde Windows:

```bash
mkdir -p /home/vmjesus/compartida
sudo chmod -R 0777 /home/vmjesus/compartida
sudo chown -R nobody:nogroup /home/vmjesus/compartida
```

### Configuración del Recurso en `/etc/samba/smb.conf`

Se añadió el siguiente bloque al final del archivo de configuración de Samba:

```ini
[compartida]
  path = /home/vmjesus/compartida
  browsable = yes
  writable = yes
  guest ok = yes
  read only = no
  create mask = 0777
  directory mask = 0777
```

### Creación de Usuario Samba y Reinicio del Servicio

```bash
sudo smbpasswd -a vmjesus
sudo systemctl restart smbd nmbd
```

### Acceso desde el Cliente Windows

1. Presionar `Windows + R`.
2. Escribir la ruta UNC del recurso compartido: `\\10.104.14.100\compartida`

---

## 5. Configuración del Cortafuegos (UFW)

Para proteger el servidor permitiendo únicamente el tráfico necesario para la administración remota y la transferencia de archivos, se configuró el firewall UFW (_Uncomplicated Firewall_):

```bash
# Permitir tráfico SSH
sudo ufw allow OpenSSH

# Permitir tráfico de Samba
sudo ufw allow samba

# Habilitar el cortafuegos
sudo ufw enable

# Verificar reglas activas
sudo ufw status
```

---

## 6. Resumen de Resolución de Problemas (Troubleshooting)

Durante el despliegue se resolvieron los siguientes incidentes técnicos:

1. **`Destination Host Unreachable` con IP estática:** Se resolvió cambiando el adaptador de red de _NAT_ a _Adaptador Puente_ en VirtualBox, verificando la puerta de enlace real de la red móvil (`10.104.14.88`) y reemplazando la directiva obsoleta `gateway4` por el bloque `routes` en Netplan.
2. **Error de credenciales y permisos en Windows al acceder a Samba:** Se solucionó limpiando las credenciales almacenadas en caché en el _Administrador de credenciales_ de Windows, configurando un usuario dedicado con `smbpasswd`, aplicando permisos `0777` con propietario `nobody:nogroup` en Linux y añadiendo las máscaras `create mask` y `directory mask` en `smb.conf`.

# Ubuntu Server Project — Technical Documentation

**Author:** `<your name>`
**Course:** `<course name>`
**Date:** `<date>`
**Server hostname:** `<hostname>`
**Server static IP:** `<ip-address>`

---

## 7. Configuración de pruevas de conectividad, seguridad y recuperación de información

Los scripts de validación:

| Script                 | Purpose                                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `server_test.sh`       | Verificación integral del estado: operatividad, cortafuegos, conectividad, seguridad y comprobación de la recuperación        |
| `backup_compartida.sh` | Copia de seguridad automatizada del recurso compartido «compartida», con prueba de recuperación de extremo a extremo opcional |

---

### 7.1 Backups Automatizados

Script: `/usr/local/bin/backup_compartida.sh`

- **Origen:** `/home/vmjesus/compartida`
- **Destino:** `/backup/compartida/backup_<timestamp>/`
- **Método:** `rsync` (incremental, `--delete`)
- **Retención:** backups older than 7 days are deleted
- **Log:** `/var/log/backup_compartida.log`
- **Programado:** Diario a las 02:30 via root crontab

Crontab entry:

```
30 2 * * * /usr/local/bin/backup_compartida.sh
```

---

## 8. Test Scripts

### 8.1 `server_test.sh` — Conjunto completo de validación

Ubicado en: `/usr/local/bin/server_test.sh`.

#### What it checks

| Section             | Checks                                                                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. Operabilidad** | Tiempo de actividad, carga, memoria, uso del disco, estado de `ssh` y `smbd`                                                                                                          |
| **2. Firewall**     | UFW activo, volcado de reglas, políticas predeterminadas; puertos SSH y Samba permitidos                                                                                              |
| **3. Connectidad**  | Direcciones IP, ruta predeterminada, puertos en escucha, conexiones TCP locales, alcanzabilidad de la puerta de enlace                                                                |
| **4. Securidad**    | Inicio de sesión SSH como root deshabilitado, intento de acceso SSH como root denegado, acceso anónimo a Samba denegado, política de cortafuegos                                      |
| **5. Recovery**     | Se ha encontrado una copia de seguridad existente; la copia de seguridad no está vacía; el archivo de muestra es recuperable; el contenido restaurado coincide con el archivo activo. |

#### Como Ejecutarlo

```bash
sudo chmod +x /usr/local/bin/server_test.sh
sudo /usr/local/bin/server_test.sh
```

El script debe ejecutarse con `sudo`, ya que lee el estado de UFW, intenta iniciar sesión por SSH como usuario root y comprueba los permisos de las copias de seguridad.

#### Formato de salida

Cada verificación imprime una línea:

- `[PASS]` — verificación exitosa

- `[WARN]` — problema no crítico; se recomienda revisar

- `[FAIL]` — verificación fallida; se requiere acción

Al final, un resumen muestra los conteos totales y el script finaliza con:

- `0` si todas las verificaciones críticas pasaron

- `1` si ocurrió algún `FAIL`

#### Variables de configuración (inicio del script)

```bash
COMPARTIDA_DIR="/srv/samba/compartida"
SAMBA_USER="vmjesus"
SSH_PORT=22
SAMBA_PORT=445
BACKUP_ROOT="/backup/compartida"
```

Edítalas si tu configuración es diferente.

#### Ejemplo de salida (extracto)

```
==================================================
2. FIREWALL CONFIGURATION (UFW)
==================================================
--- UFW Status ---
Status: active
[PASS] UFW is active
...
==================================================
 SUMMARY
==================================================
PASS: 24
WARN: 2
FAIL: 0

RESULT: All critical checks passed.
```

### 8.2 `backup_compartida.sh` — Prueba de Respaldo y Recuperación

Ubicado en `/usr/local/bin/backup_compartida.sh`.

#### Modos

| Comando                                | Comportamiento                                                                                                                         |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `backup_compartida.sh`                 | Ejecuta un respaldo normal con `rsync`, aplica retención                                                                               |
| `backup_compartida.sh --test-recovery` | Ejecuta un respaldo y luego realiza una prueba completa de recuperación (crear archivo → respaldar → eliminar → restaurar → verificar) |

#### Cómo ejecutar

```bash
sudo chmod +x /usr/local/bin/backup_compartida.sh

# Respaldo normal
sudo /usr/local/bin/backup_compartida.sh

# Prueba de recuperación
sudo /usr/local/bin/backup_compartida.sh --test-recovery
```

#### Registro (Log)

Toda la salida se añade a `/var/log/backup_compartida.log`. Visualízalo con:

```bash
sudo tail -f /var/log/backup_compartida.log
```

#### Variables de configuración

```bash
SOURCE_DIR="/home/vmjesus/compartida"
BACKUP_ROOT="/backup/compartida"
SAMBA_USER="vmjesus"
LOG_FILE="/var/log/backup_compartida.log"
RETENTION_DAYS=7
```

---

## 9. Procedimiento de Pruebas (Paso a Paso)

Este procedimiento genera evidencia para las **pruebas de conectividad, seguridad y recuperación de datos**.

### 9.1 Pruebas de Conectividad

1. Desde una máquina cliente, confirma que el servidor es accesible:

   ```bash
   ping <server-ip>
   ping 10.104.14.100
   ```

2. Confirma que los servicios están expuestos:

   ```bash
   nmap -p 22,445 <server-ip>10.104.14.100
   nmap -p 22,445 10.104.14.100
   ```

   Esperado: puertos 22 y 445 abiertos.

3. Conéctate vía SSH:

   ```bash
   ssh <user>@<server-ip>
   ssh vmjesus@10.104.14.100
   ```

4. Accede al recurso compartido Samba desde un cliente:

   - Windows: `\\10.104.14.100\compartida`

   - Linux: `smb://10.104.14.100/compartida`

   - Crea un archivo de prueba para confirmar el acceso de escritura.

5. Ejecuta `sudo /usr/local/bin/server_test.sh` y toma captura de pantalla de las Secciones 1 y 3.

### 9.2 Pruebas de Seguridad

1. Confirma que el inicio de sesión SSH como root está denegado:

   ```bash
   ssh root@10.104.14.100
   ```

   Esperado: permiso denegado (_permission denied_).

2. Confirma que UFW está activo y las reglas coinciden con el diseño:

   ```bash
   sudo ufw status verbose
   ```

3. Confirma que Samba requiere autenticación:

   ```bash
   smbclient -L 10.104.14.100 -N
   ```

   Esperado: acceso denegado (_access denied_).

4. Ejecuta `sudo /usr/local/bin/server_test.sh` y toma captura de pantalla de las Secciones 2 y 4.

### 9.3 Pruebas de Recuperación de Datos

1. Asegúrate de que existe un respaldo:

   ```bash
   sudo ls -la /backup/compartida/
   ```

2. Ejecuta la prueba completa de recuperación:

   ```bash
   sudo /usr/local/bin/backup_compartida.sh --test-recovery
   ```

3. Confirma que el registro muestra que los cinco pasos pasaron:

   ```bash
   sudo tail -n 20 /var/log/backup_compartida.log
   ```

4. Ejecuta `sudo /usr/local/bin/server_test.sh` y toma captura de pantalla de la Sección 5.

### 9.4 Monitoreo

- Tiempo real: `htop`

- Histórico: `sar -u 1 5`, `sar -r 1 5`, `sar -d 1 5`

- Servicios: `systemctl status smbd`, `systemctl status ssh`

- Registros (Logs): `journalctl -u smbd -f`

---

## 10. Resultados Esperados

| Prueba                   | Resultado Esperado                          |
| ------------------------ | ------------------------------------------- |
| Hacer ping al servidor   | Respuestas recibidas                        |
| Puertos `nmap` 22/445    | Abiertos                                    |
| SSH como usuario no-root | Éxito                                       |
| SSH como root            | Denegado                                    |
| Listado anónimo de Samba | Denegado                                    |
| Samba como `vmjesus`     | Éxito                                       |
| Estado de UFW            | Activo, denegar entrantes (_deny incoming_) |
| Existencia de respaldo   | Directorio `backup_*` presente              |
| Prueba de recuperación   | Los 5 pasos OK, el contenido coincide       |
| `server_test.sh`         | `FAIL: 0`                                   |

---

## 11. Solución de Problemas

| Síntoma                                   | Causa probable                                              | Solución                                                              |
| ----------------------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------- |
| `server_test.sh` reporta UFW inactivo     | UFW no está habilitado                                      | `sudo ufw enable`                                                     |
| Falla la verificación del puerto SSH      | SSH en un puerto distinto al predeterminado                 | Actualizar `SSH_PORT` en el script                                    |
| Falla la verificación del puerto Samba    | Samba no está ejecutándose o está bloqueado por el firewall | `sudo systemctl restart smbd`; volver a revisar UFW                   |
| Prueba de recuperación: "No backup found" | Nunca se ejecutó el respaldo, o `BACKUP_ROOT` es incorrecto | Ejecutar `backup_compartida.sh`; verificar ruta                       |
| `sudo -u vmjesus` falla                   | `vmjesus` no tiene cuenta de Linux                          | `sudo adduser vmjesus && sudo smbpasswd -a vmjesus`                   |
| Respaldo legible solo por root            | Permisos en `/backup/compartida`                            | `sudo chown -R root:root /backup/compartida`; ajustar según el diseño |

---

## 12. Archivos Entregados

| Archivo                               | Propósito                         |
| ------------------------------------- | --------------------------------- |
| `/usr/local/bin/server_test.sh`       | Script de validación completa     |
| `/usr/local/bin/backup_compartida.sh` | Script de respaldo + recuperación |
| `/var/log/backup_compartida.log`      | Registro de respaldo/recuperación |
| `/etc/samba/smb.conf`                 | Configuración de Samba            |
| `/etc/ssh/sshd_config`                | Configuración de SSH              |
| `/etc/netplan/<file>.yaml`            | Configuración de IP estática      |
| `/backup/compartida/`                 | Destino de respaldos              |

---

