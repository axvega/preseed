#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root"
    echo "Usa: sudo bash sc-red.sh"
fi

PRESEED_URL="http://preseed.angeldlv.es/debian-preseed.cfg"

ISO_ORIGINAL="/home/axvega/debian-auto-install/debian-13.1.0-amd64-netinst.iso"
WORK_DIR="/tmp/iso-preseed-red"
ISO_MOUNT="/tmp/iso-original"
ISO_NUEVA="autorediso.iso"
ISO_DESTINO="/home/axvega/debian-auto-install/"

VM_NAME="InstalacionRed"
VM_DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
VM_DISK_SIZE="20G"
VM_RAM="2048"
VM_VCPUS="2"
VM_ISO_PATH="${ISO_DESTINO}/${ISO_NUEVA}"
REAL_USER="usuario"

echo "Verificando requisitos"

if [ ! -f "$ISO_ORIGINAL" ]; then
    echo "ERROR: No se encuentra la ISO original: $ISO_ORIGINAL"
fi

if [ ! -d "$ISO_DESTINO" ]; then
    mkdir -p "$ISO_DESTINO"
    chown ${REAL_USER}:${REAL_USER} "$ISO_DESTINO"
fi

echo "Verificando acceso al preseed en: $PRESEED_URL"
if ! curl -f -s "$PRESEED_URL" > /dev/null; then
    echo "ERROR: No se puede acceder al preseed"
    echo "Verifica que el servidor web este ejecutandose"
    echo "URL: $PRESEED_URL"
fi
echo "Preseed accesible"

echo "Limpiando directorios temporales..."
umount "$ISO_MOUNT" 2>/dev/null || true
rm -rf "$WORK_DIR" "$ISO_MOUNT"
mkdir -p "$WORK_DIR" "$ISO_MOUNT"

echo "Montando ISO original..."
mount -o loop "$ISO_ORIGINAL" "$ISO_MOUNT"

echo "Copiando contenido..."
rsync -a "$ISO_MOUNT/" "$WORK_DIR/"
umount "$ISO_MOUNT"

chmod -R +w "$WORK_DIR"

echo "Configurando arranque BIOS..."
if [ -f "$WORK_DIR/isolinux/txt.cfg" ]; then
    cat > "$WORK_DIR/isolinux/txt.cfg" << EOF
default install
timeout 0
label install
    menu label ^Instalacion Automatica (Red)
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz auto=true priority=critical url=${PRESEED_URL} console-setup/ask_detect=false keyboard-configuration/xkb-keymap=es locale=es_ES.UTF-8 --- quiet
label manual
    menu label Instalacion ^Manual
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz
EOF
    echo "txt.cfg configurado"
fi

if [ -f "$WORK_DIR/isolinux/isolinux.cfg" ]; then
    sed -i 's/^timeout .*/timeout 0/' "$WORK_DIR/isolinux/isolinux.cfg" || true
    sed -i 's/^default .*/default install/' "$WORK_DIR/isolinux/isolinux.cfg" || true
fi

echo "Configurando arranque UEFI..."
if [ -f "$WORK_DIR/boot/grub/grub.cfg" ]; then
    cat > "$WORK_DIR/boot/grub/grub.cfg" << EOF
set timeout=0
set default=0

menuentry 'Instalacion Automatica (Red)' {
    set background_color=black
    linux    /install.amd/vmlinuz auto=true priority=critical url=${PRESEED_URL} console-setup/ask_detect=false keyboard-configuration/xkb-keymap=es locale=es_ES.UTF-8 --- quiet
    initrd   /install.amd/initrd.gz
}
EOF
    echo "grub.cfg configurado"
fi

echo "Actualizando checksums..."
cd "$WORK_DIR"
chmod +w md5sum.txt 2>/dev/null || true
find . -follow -type f ! -name md5sum.txt ! -path "./isolinux/*" -exec md5sum {} \; > md5sum.txt 2>/dev/null || true
cd - > /dev/null

echo "Generando ISO..."
xorriso -as mkisofs \
    -r -V "Debian 13 Red" \
    -o "$ISO_NUEVA" \
    -J -joliet-long \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$WORK_DIR" > /dev/null 2>&1

rm -rf "$WORK_DIR" "$ISO_MOUNT"

echo "Copiando ISO al destino..."
if [ -f "${ISO_DESTINO}/${ISO_NUEVA}" ]; then
    rm -f "${ISO_DESTINO}/${ISO_NUEVA}"
fi

cp "$ISO_NUEVA" "$ISO_DESTINO/"
chown ${REAL_USER}:${REAL_USER} "${ISO_DESTINO}/${ISO_NUEVA}"
chmod 644 "${ISO_DESTINO}/${ISO_NUEVA}"
rm -f "$ISO_NUEVA"

ISO_SIZE=$(du -h "${VM_ISO_PATH}" | cut -f1)
echo "ISO creada: ${VM_ISO_PATH} (${ISO_SIZE})"

echo "Configurando maquina virtual..."
if virsh list --all | grep -q "$VM_NAME"; then
    echo "Eliminando VM anterior..."
    if virsh list --state-running | grep -q "$VM_NAME"; then
        virsh destroy "$VM_NAME" 2>/dev/null || true
    fi
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
fi

if [ -f "$VM_DISK_PATH" ]; then
    rm -f "$VM_DISK_PATH"
fi

echo "Creando disco virtual..."
qemu-img create -f qcow2 "$VM_DISK_PATH" "$VM_DISK_SIZE" > /dev/null 2>&1

echo "Creando VM..."
virt-install \
    --name="$VM_NAME" \
    --ram="$VM_RAM" \
    --vcpus="$VM_VCPUS" \
    --disk path="$VM_DISK_PATH",format=qcow2,bus=virtio \
    --cdrom="$VM_ISO_PATH" \
    --os-variant=debian12 \
    --network network=default,model=virtio \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole \
    --boot uefi \
    > /dev/null 2>&1

echo "VM creada: $VM_NAME"
echo "Preseed URL: $PRESEED_URL"
echo "Acceso: virt-manager o virt-viewer $VM_NAME"
axvega@portatil:~/debian-auto-install$ nano
debian-13.1.0-amd64-netinst.iso  iso.sh                           preseed.cfg                      sc-red.sh
axvega@portatil:~/debian-auto-install$ nano sc-red.sh
axvega@portatil:~/debian-auto-install$ sudo bash sc-red.sh
Verificando requisitos
Verificando acceso al preseed en: http://preseed.angeldlv.es/debian-preseed.cfg
Preseed accesible
Limpiando directorios temporales...
Montando ISO original...
mount: /tmp/iso-original: ATENCIÓN: origen protegido contra escritura; se monta como solo lectura.
Copiando contenido...
Configurando arranque BIOS...
txt.cfg configurado
Configurando arranque UEFI...
grub.cfg configurado
Actualizando checksums...
Generando ISO...
xorriso 1.5.6 : RockRidge filesystem manipulator, libburnia project.

Drive current: -outdev 'stdio:/home/axvega/debian-auto-install//autorediso.iso'
Media current: stdio file, overwriteable
Media status : is blank
Media summary: 0 sessions, 0 data blocks, 0 data, 58.3g free
xorriso : WARNING : -volid text problematic as automatic mount point name
xorriso : WARNING : -volid text does not comply to ISO 9660 / ECMA 119 rules
Added to ISO image: directory '/'='/tmp/iso-preseed-red'
xorriso : UPDATE :    1530 files added in 1 seconds
xorriso : UPDATE :    1530 files added in 1 seconds
xorriso : NOTE : Copying to System Area: 432 bytes from file '/usr/lib/ISOLINUX/isohdpfx.bin'
xorriso : UPDATE :  20.29% done
xorriso : UPDATE :  94.89% done
ISO image produced: 495616 sectors
Written to medium : 495616 sectors at LBA 0
Writing to 'stdio:/home/axvega/debian-auto-install//autorediso.iso' completed successfully.

ISO creada: /home/axvega/debian-auto-install//autorediso.iso (969M)
Configurando maquina virtual...
Creando disco virtual...
Creando VM...
VM creada exitosamente: InstalacionRed
Preseed URL: http://preseed.angeldlv.es/debian-preseed.cfg
Acceso: virt-manager o virt-viewer InstalacionRed
axvega@portatil:~/debian-auto-install$ cat sc-red.sh
#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root"
    echo "Usa: sudo bash sc-red.sh"
    exit 1
fi

PRESEED_URL="http://preseed.angeldlv.es/debian-preseed.cfg"
ISO_ORIGINAL="/home/axvega/debian-auto-install/debian-13.1.0-amd64-netinst.iso"
WORK_DIR="/tmp/iso-preseed-red"
ISO_MOUNT="/tmp/iso-original"
ISO_DESTINO="/home/axvega/debian-auto-install/"
ISO_NUEVA="$ISO_DESTINO/autorediso.iso"

VM_NAME="InstalacionRed"
VM_DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
VM_DISK_SIZE="20G"
VM_RAM="2048"
VM_VCPUS="2"
REAL_USER="axvega"  # Cambia esto por tu usuario real

echo "Verificando requisitos"

if [ ! -f "$ISO_ORIGINAL" ]; then
    echo "ERROR: No se encuentra la ISO original: $ISO_ORIGINAL"
    exit 1
fi

if [ ! -d "$ISO_DESTINO" ]; then
    mkdir -p "$ISO_DESTINO"
    chown ${REAL_USER}:${REAL_USER} "$ISO_DESTINO"
fi

echo "Verificando acceso al preseed en: $PRESEED_URL"
if ! curl -f -s "$PRESEED_URL" > /dev/null; then
    echo "ERROR: No se puede acceder al preseed"
    echo "Verifica que el servidor web este ejecutandose"
    echo "URL: $PRESEED_URL"
    exit 1
fi
echo "Preseed accesible"

echo "Limpiando directorios temporales..."
umount "$ISO_MOUNT" 2>/dev/null || true
rm -rf "$WORK_DIR" "$ISO_MOUNT"
mkdir -p "$WORK_DIR" "$ISO_MOUNT"

echo "Montando ISO original..."
mount -o loop "$ISO_ORIGINAL" "$ISO_MOUNT"

echo "Copiando contenido..."
rsync -a "$ISO_MOUNT/" "$WORK_DIR/"
umount "$ISO_MOUNT"

chmod -R +w "$WORK_DIR"

echo "Configurando arranque BIOS..."
if [ -f "$WORK_DIR/isolinux/txt.cfg" ]; then
    cat > "$WORK_DIR/isolinux/txt.cfg" << EOF
default install
timeout 0
label install
    menu label ^Instalacion Automatica (Red)
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz auto=true priority=critical url=${PRESEED_URL} console-setup/ask_detect=false keyboard-configuration/xkb-keymap=es locale=es_ES.UTF-8 --- quiet
label manual
    menu label Instalacion ^Manual
    kernel /install.amd/vmlinuz
    append initrd=/install.amd/initrd.gz
EOF
    echo "txt.cfg configurado"
fi

if [ -f "$WORK_DIR/isolinux/isolinux.cfg" ]; then
    sed -i 's/^timeout .*/timeout 0/' "$WORK_DIR/isolinux/isolinux.cfg" || true
    sed -i 's/^default .*/default install/' "$WORK_DIR/isolinux/isolinux.cfg" || true
fi

echo "Configurando arranque UEFI..."
if [ -f "$WORK_DIR/boot/grub/grub.cfg" ]; then
    cat > "$WORK_DIR/boot/grub/grub.cfg" << EOF
set timeout=0
set default=0

menuentry 'Instalacion Automatica (Red)' {
    set background_color=black
    linux    /install.amd/vmlinuz auto=true priority=critical url=${PRESEED_URL} console-setup/ask_detect=false keyboard-configuration/xkb-keymap=es locale=es_ES.UTF-8 --- quiet
    initrd   /install.amd/initrd.gz
}
EOF
    echo "grub.cfg configurado"
fi

echo "Actualizando checksums..."
cd "$WORK_DIR"
chmod +w md5sum.txt 2>/dev/null || true
find . -follow -type f ! -name md5sum.txt ! -path "./isolinux/*" -exec md5sum {} \; > md5sum.txt 2>/dev/null || true
cd - > /dev/null

echo "Generando ISO..."
if [ -f "$ISO_NUEVA" ]; then
    rm -f "$ISO_NUEVA"
fi

xorriso -as mkisofs \
    -r -V "Debian 13 Red" \
    -o "$ISO_NUEVA" \
    -J -joliet-long \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$WORK_DIR" 2>&1 | grep -v "libisofs"

if [ $? -ne 0 ] || [ ! -f "$ISO_NUEVA" ]; then
    echo "ERROR: No se pudo generar la ISO"
    rm -rf "$WORK_DIR" "$ISO_MOUNT"
    exit 1
fi

chown ${REAL_USER}:${REAL_USER} "$ISO_NUEVA"
chmod 644 "$ISO_NUEVA"

rm -rf "$WORK_DIR" "$ISO_MOUNT"

ISO_SIZE=$(du -h "$ISO_NUEVA" | cut -f1)
echo "ISO creada: $ISO_NUEVA (${ISO_SIZE})"

echo "Configurando maquina virtual..."
if virsh list --all | grep -q "$VM_NAME"; then
    echo "Eliminando VM anterior..."
    if virsh list --state-running | grep -q "$VM_NAME"; then
        virsh destroy "$VM_NAME" 2>/dev/null || true
    fi
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
fi

if [ -f "$VM_DISK_PATH" ]; then
    rm -f "$VM_DISK_PATH"
fi

echo "Creando disco virtual..."
qemu-img create -f qcow2 "$VM_DISK_PATH" "$VM_DISK_SIZE" > /dev/null 2>&1

echo "Creando VM..."
virt-install \
    --name="$VM_NAME" \
    --ram="$VM_RAM" \
    --vcpus="$VM_VCPUS" \
    --disk path="$VM_DISK_PATH",format=qcow2,bus=virtio \
    --cdrom="$ISO_NUEVA" \
    --os-variant=debian12 \
    --network network=default,model=virtio \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole \
    --boot uefi \
    > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "VM creada exitosamente: $VM_NAME"
    echo "Preseed URL: $PRESEED_URL"
    echo "Acceso: virt-manager o virt-viewer $VM_NAME"
else
    echo "ADVERTENCIA: Hubo un problema al crear la VM, pero la ISO se generó correctamente"
    echo "Puedes usar la ISO manualmente: $ISO_NUEVA"
fi
