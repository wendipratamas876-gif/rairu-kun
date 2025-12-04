# Menggunakan Ubuntu 22.04 LTS, standar industri VPS
FROM ubuntu:22.04

# Non-interactive install
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

# --- Step 1: Instalasi Paket Dasar VPS Lengkap ---
# Install semua yang biasa ada di VPS: systemd, ssh, utilitas, firewall, dll.
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    # Sistem init dan manajemen service (JANTUNG VPS)
    systemd systemd-sysv \
    # SSH Server
    openssh-server \
    # Utilitas wajib VPS
    sudo curl wget git vim htop net-tools unzip tar gnupg2 ca-certificates lsb-release \
    # Python dan pip (sering dibutuhkan)
    python3 python3-pip python3-venv \
    # Firewall
    ufw \
    # Network tools
    iproute2 iptables \
    # CAs untuk apt
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Konfigurasi Systemd untuk Lingkungan Container ---
# Membersihkan service yang tidak relevan atau konflik di container. Langkah WAJIB.
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# --- Step 3: Konfigurasi SSH Server ---
# Aktifkan login root dengan password
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /var/run/sshd

# --- Step 4: Setup User Root ---
# Sesuai permintaan: username root, password kelvin123
RUN echo "root:kelvin123" | chpasswd

# --- Step 5: Download dan Setup Ngrok ---
# Ngrok untuk tunneling SSH
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 6: Membuat Script Startup untuk Ngrok & Info ---
# Script ini akan dipanggil oleh systemd service
RUN cat <<'EOF' > /usr/local/bin/start-ngrok-tunnel.sh
#!/bin/bash
echo "=== Starting Ngrok Tunnel for VPS SSH Access ==="

# Jalankan ngrok untuk SSH (port 22) di background
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Tunggu ngrok siap
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
    echo "Ngrok tunnel not ready yet... (attempt $i/5)"
    sleep 5
  fi
done
EOF
RUN chmod +x /usr/local/bin/start-ngrok-tunnel.sh

# --- Step 7: Membuat Systemd Service untuk Ngrok ---
# Agar ngrok otomatis dijalankan setiap kali VPS boot
RUN cat <<'EOF' > /etc/systemd/system/ngrok-ssh-tunnel.service
[Unit]
Description=Ngrok TCP Tunnel for SSH
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=oneshot
# Berikan akses ke environment variable
Environment="NGROK_TOKEN=${NGROK_TOKEN}"
Environment="REGION=${REGION}"
ExecStart=/usr/local/bin/start-ngrok-tunnel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# --- Step 8: Aktifkan Service saat Boot ---
# Ini adalah perintah VPS asli! Mengaktifkan service agar jalan otomatis.
RUN systemctl enable ssh.service ngrok-ssh-tunnel.service

# --- Step 9: Mengekspos port ---
EXPOSE 22

# --- Step 10: Memberi tahu Docker cara menghentikan container dengan benar ---
STOPSIGNAL SIGRTMIN+3

# --- Step 11: Command Utama (PID 1) ---
# Ini adalah perintah untuk menjalankan systemd sebagai proses utama.
CMD ["/sbin/init"]
