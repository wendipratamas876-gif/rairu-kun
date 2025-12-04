# Menggunakan Ubuntu 22.04 LTS sebagai base image, versi yang umum di VPS
FROM ubuntu:22.04

# Non-interactive install agar tidak meminta input saat proses build
ENV DEBIAN_FRONTEND=noninteractive
# Variabel krusial agar systemd bisa berjalan di dalam container
ENV container=docker

# --- ARG untuk Build Time ---
# Token Ngrok akan dimasukkan sebagai Railway environment variable
ARG NGROK_TOKEN
ARG REGION=ap

# --- ENV untuk Runtime ---
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

# --- Step 1: Instalasi Paket Dasar VPS ---
# Kita install systemd, openssh-server, dan utilitas umum VPS
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    # Sistem init dan manajemen service (JANTUNG VPS)
    systemd systemd-sysv \
    # SSH Server untuk akses remote
    openssh-server \
    # Utilitas wajib di VPS
    sudo curl wget git vim htop net-tools unzip tar gnupg2 ca-certificates lsb-release \
    # Python dan pip (sering dibutuhkan untuk berbagai tool dan app)
    python3 python3-pip python3-venv \
    # Firewall (opsional, tapi bagus untuk simulasi VPS)
    ufw \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Konfigurasi Systemd untuk Lingkungan Container ---
# Langkah ini membersihkan service-service yang tidak relevan atau konflik
# saat systemd dijalankan di dalam container. Ini adalah langkah standar.
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# --- Step 3: Konfigurasi SSH Server ---
# Aktifkan login dengan password dan izinkan root login (untuk kemudahan akses awal)
# Di VPS sungguhan, biasanya login root via password dinonaktifkan, dan menggunakan SSH key.
# Tapi untuk simulasi di container, ini lebih praktis.
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Buat direktori untuk host keys jika belum ada
    mkdir -p /var/run/sshd

# --- Step 4: Download dan Setup Ngrok ---
# Ngrok akan menjadi jembatan kita ke internet
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 5: Membuat User VPS (Mirip VPS sungguhan) ---
# Kita buat user 'vpsadmin' sebagai user utama, bukan root.
# GANTI 'your_super_secret_password' dengan password yang sangat kuat!
RUN useradd -m -s /bin/bash vpsadmin && \
    echo "vpsadmin:your_super_secret_password" | chpasswd && \
    # Berikan hak akses sudo tanpa password (praktis, tapi kurang aman)
    # Untuk keamanan lebih baik, hapus 'NOPASSWD:' sehingga diminta password user saat sudo
    echo "vpsadmin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/vpsadmin

# --- Step 6: Membuat Script Startup untuk Ngrok & Info ---
# Script ini akan dijalankan oleh systemd service saat boot
RUN cat <<'EOF' > /usr/local/bin/start-ssh-tunnel.sh
#!/bin/bash
echo "=== Starting Ngrok Tunnel for VPS SSH Access ==="

# Jalankan ngrok untuk SSH (port 22) di background
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Tunggu beberapa saat agar ngrok sempat membuat tunnel
sleep 10

# Cetak informasi koneksi SSH ke log
echo "Fetching SSH tunnel info..."
for i in {1..5}; do
  TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
  if [ -n "$TUNNEL_INFO" ]; then
    echo "----------------------------------------------------"
    echo "          VPS SSH ACCESS INFO"
    echo "----------------------------------------------------"
    echo "$TUNNEL_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for tunnel in data.get('tunnels', []):
        if '22' in tunnel.get('config', {}).get('addr', ''):
            url = tunnel.get('public_url', '')
            host = url.split('://')[-1].split(':')[0]
            port = url.split(':')[-1]
            print(f'SSH Host: {host}')
            print(f'SSH Port: {port}')
            print(f'Username: vpsadmin')
            print(f'Password: your_super_secret_password')
            print('----------------------------------------------------')
            print('Command to connect:')
            print(f'ssh vpsadmin@{host} -p {port}')
            print('----------------------------------------------------')
            break
    else:
        print('Could not find SSH tunnel in Ngrok response.')
except (json.JSONDecodeError, IndexError, KeyError):
    print('Error parsing Ngrok response.')
"
    break
  else
    echo "Ngrok tunnel not ready yet... (attempt $i/5)"
    sleep 5
  fi
done
EOF
RUN chmod +x /usr/local/bin/start-ssh-tunnel.sh

# --- Step 7: Membuat Systemd Service untuk Ngrok ---
# Agar ngrok otomatis dijalankan setiap kali container boot/restart
RUN cat <<'EOF' > /etc/systemd/system/ngrok-ssh.service
[Unit]
Description=Ngrok TCP Tunnel for SSH
After=network.target ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-ssh-tunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# --- Step 8: Aktifkan Service saat Boot ---
# Ini adalah perintah untuk mengaktifkan service agar otomatis jalan
# ssh dan ngrok-ssh akan di-start oleh systemd saat container dijalankan
RUN systemctl enable ssh.service ngrok-ssh.service

# --- Step 9: Mengekspos port SSH ---
# Meskipun tidak langsung dipakai, ini bagus untuk dokumentasi
EXPOSE 22

# --- Step 10: Memberi tahu Docker cara menghentikan container dengan benar ---
STOPSIGNAL SIGRTMIN+3

# --- Step 11: Command Utama (PID 1) ---
# Ini adalah bagian terpenting. Kita menjalankan /sbin/init
# yang akan memulai systemd sebagai proses utama (PID 1).
# Systemd kemudian akan mengambil alih dan menjalankan semua
# service yang sudah di-enable (ssh, ngrok-ssh).
CMD ["/sbin/init"]
