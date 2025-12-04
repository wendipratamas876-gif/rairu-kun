# Menggunakan Ubuntu 22.04 LTS sebagai base image
FROM ubuntu:22.04

# Non-interactive install
ENV DEBIAN_FRONTEND=noninteractive
# Variabel krusial agar systemd bisa berjalan
ENV container=docker

# --- ARG untuk Build Time ---
ARG NGROK_TOKEN
ARG REGION=ap

# --- ENV untuk Runtime ---
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

# --- Step 1: Instalasi Paket Dasar VPS ---
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    systemd systemd-sysv \
    openssh-server \
    sudo curl wget git vim htop net-tools unzip tar \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Konfigurasi Systemd untuk Container ---
# (Bagian ini sudah benar, biarkan saja)
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# --- Step 3: Konfigurasi SSH Server ---
# (Bagian ini sudah benar, biarkan saja)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /var/run/sshd

# --- Step 4: Download dan Setup Ngrok ---
# (Bagian ini sudah benar, biarkan saja)
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 5: Membuat User VPS ---
# GANTI 'your_super_secret_password'!
RUN useradd -m -s /bin/bash vpsadmin && \
    echo "vpsadmin:your_super_secret_password" | chpasswd && \
    echo "vpsadmin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/vpsadmin

# --- Step 6: Membuat Script Startup untuk Ngrok & Info ---
# Script ini sedikit diperbaiki untuk debugging
RUN cat <<'EOF' > /usr/local/bin/start-ssh-tunnel.sh
#!/bin/bash
echo "=== Starting Ngrok Tunnel for VPS SSH Access ==="

# Debug: Cek apakah token ada
if [ -z "$NGROK_TOKEN" ]; then
    echo "ERROR: NGROK_TOKEN is not set!"
    exit 1
fi
echo "Ngrok token found. Starting tunnel..."

# Jalankan ngrok untuk SSH (port 22) di background
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Tunggu lebih lama, biar ngrok benar-bener siap
sleep 15

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
except (json.JSONDecodeError, IndexError, KeyError, TypeError) as e:
    print(f'Error parsing Ngrok response: {e}')
    print('Raw response:')
    print('$TUNNEL_INFO')
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
# PERBAIKAN: Tambahkan Environment agar service bisa baca token
RUN cat <<'EOF' > /etc/systemd/system/ngrok-ssh.service
[Unit]
Description=Ngrok TCP Tunnel for SSH
# PERBAIKAN: Hanya butuh network, jangan tunggu ssh
After=network.target

[Service]
Type=oneshot
# PERBAIKAN: Beritahu systemd environment variable-nya apa
Environment="NGROK_TOKEN=${NGROK_TOKEN}"
Environment="REGION=${REGION}"
ExecStart=/usr/local/bin/start-ssh-tunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# --- Step 8: Aktifkan Service saat Boot ---
# (Bagian ini sudah benar, biarkan saja)
RUN systemctl enable ssh.service ngrok-ssh.service

# --- Step 9: Mengekspos port ---
EXPOSE 22

# --- Step 10: Memberi tahu Docker cara menghentikan container ---
STOPSIGNAL SIGRTMIN+3

# --- Step 11: Command Utama (PID 1) ---
# PERBAIKAN: Ini adalah perintah WAJIB untuk Dockerfile.privileged di Railway
CMD ["railway", "run", "--privileged", "--pid=host", "/sbin/init"]
