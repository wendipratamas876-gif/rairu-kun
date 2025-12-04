# Menggunakan Ubuntu 22.04 LTS sebagai base image
FROM ubuntu:22.04

# Non-interactive install agar tidak meminta input saat proses build
ENV DEBIAN_FRONTEND=noninteractive
# Variabel krusial agar systemd bisa berjalan di dalam container
ENV container=docker

# --- ARG untuk Build Time ---
ARG NGROK_TOKEN
ARG REGION=us

# --- ENV untuk Runtime ---
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

# --- Step 1: Instalasi Paket Dasar VPS ---
# Install semua paket yang biasa ada di VPS sungguhan
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    # Sistem init dan manajemen service (JANTUNG VPS)
    systemd systemd-sysv \
    # SSH Server untuk akses remote
    openssh-server \
    # Utilitas wajib di VPS
    sudo curl wget git vim htop net-tools unzip tar gnupg2 ca-certificates lsb-release \
    # Python dan pip
    python3 python3-pip python3-venv \
    # Network tools
    iproute2 iptables \
    # Logging
    systemd-journal-remote \
    # Process management
    cron \
    # Text editor
    nano \
    # Network utilities
    dnsutils iputils-ping \
    # File system utilities
    xfsprogs e2fsprogs \
    # Disk utilities
    parted fdisk \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Konfigurasi Systemd untuk Lingkungan Container ---
# Langkah ini membersihkan service-service yang tidak relevan atau konflik
# saat systemd dijalankan di dalam container
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# --- Step 3: Konfigurasi SSH Server ---
# Aktifkan login dengan password dan izinkan root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Buat direktori untuk host keys jika belum ada
    mkdir -p /var/run/sshd

# --- Step 4: Setup User dan Password ---
# Setup user root dengan password
RUN echo "root:kelvin123" | chpasswd

# --- Step 5: Download dan Setup Ngrok ---
# Ngrok akan menjadi jembatan kita ke internet
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 6: Membuat Script Startup untuk Ngrok ---
# Script ini akan dijalankan oleh systemd service saat boot
RUN cat <<'EOF' > /usr/local/bin/start-ngrok-tunnel.sh
#!/bin/bash
echo "=== Starting Ngrok Tunnel for VPS SSH Access ==="

# Pastikan token dan region tersedia
if [ -z "$NGROK_TOKEN" ]; then
    echo "ERROR: NGROK_TOKEN is not set!"
    exit 1
fi

# Log token untuk debugging (hanya karakter pertama dan terakhir)
echo "Using NGROK_TOKEN: ${NGROK_TOKEN:0:2}...${NGROK_TOKEN: -2}"
echo "Using REGION: ${REGION}"

# Jalankan ngrok untuk SSH (port 22) di background
echo "Starting ngrok with region: ${REGION}"
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &

# Tunggu ngrok siap
echo "Waiting for ngrok to start..."
sleep 15

# Cetak informasi koneksi SSH ke log
echo "Fetching SSH tunnel info..."
for i in {1..10}; do
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
            print(f'Username: root')
            print(f'Password: kelvin123')
            print('----------------------------------------------------')
            print('Command to connect:')
            print(f'ssh root@{host} -p {port}')
            print('----------------------------------------------------')
            break
    else:
        print('Could not find SSH tunnel in Ngrok response.')
except Exception as e:
    print(f'Error parsing Ngrok response: {e}')
"
    break
  else
    echo "Ngrok tunnel not ready yet... (attempt $i/10)"
    sleep 5
  fi
done

# Log status ngrok
echo "Ngrok process status:"
ps aux | grep ngrok
EOF
RUN chmod +x /usr/local/bin/start-ngrok-tunnel.sh

# --- Step 7: Membuat Systemd Service untuk Ngrok ---
# Agar ngrok otomatis dijalankan setiap kali container boot/restart
RUN cat <<'EOF' > /etc/systemd/system/ngrok-ssh.service
[Unit]
Description=Ngrok TCP Tunnel for SSH
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-ngrok-tunnel.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# --- Step 8: Menyimpan Environment Variables ---
# Menyimpan environment variables ke file yang bisa dibaca oleh systemd
RUN echo "NGROK_TOKEN=${NGROK_TOKEN}" >> /etc/environment && \
    echo "REGION=${REGION}" >> /etc/environment

# --- Step 9: Setup Host Keys untuk SSH ---
# Generate host keys jika belum ada
RUN ssh-keygen -A

# --- Step 10: Aktifkan Service saat Boot ---
# Mengaktifkan service agar otomatis jalan saat boot
RUN systemctl enable ssh.service ngrok-ssh.service

# --- Step 11: Setup Cron ---
# Enable cron service
RUN systemctl enable cron.service

# --- Step 12: Setup Journal ---
# Configure systemd journal to persist logs
RUN mkdir -p /var/log/journal && \
    systemd-tmpfiles --create --prefix /var/log/journal

# --- Step 13: Mengekspos port SSH ---
EXPOSE 22

# --- Step 14: Memberi tahu Docker cara menghentikan container dengan benar ---
STOPSIGNAL SIGRTMIN+3

# --- Step 15: Command Utama (PID 1) ---
# Menjalankan systemd sebagai proses utama (PID 1)
CMD ["/sbin/init"]
