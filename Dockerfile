# Menggunakan Ubuntu 22.04 LTS sebagai base image
FROM ubuntu:22.04

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# --- ARG untuk Build Time ---
ARG NGROK_TOKEN
ARG REGION=ap

# --- ENV untuk Runtime ---
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

# --- Step 1: Instalasi Paket VPS Lengkap ---
# Install semua paket yang biasa ada di VPS sungguhan
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    # SSH Server
    openssh-server \
    # Utilitas jaringan
    wget curl net-tools iproute2 dnsutils iputils-ping \
    # Text editor
    vim nano \
    # System monitoring
    htop iotop \
    # File management
    tar unzip zip gzip bzip2 \
    # Version control
    git \
    # Python dan tools
    python3 python3-pip python3-venv \
    # Process management
    cron \
    # System utilities
    sudo \
    # SSL certificates
    ca-certificates \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Download dan Setup Ngrok ---
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable-linux-amd64.zip \
    && cd / && unzip ngrok-stable-linux-amd64.zip \
    && chmod +x ngrok \
    && rm ngrok-stable-linux-amd64.zip

# --- Step 3: Setup SSH Server ---
RUN mkdir /run/sshd \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo root:kelvin123 | chpasswd

# --- Step 4: Generate SSH Host Keys ---
RUN ssh-keygen -A

# --- Step 5: Setup Cron untuk VPS ---
# Create cron directory and start cron service
RUN mkdir -p /var/spool/cron/crontabs

# --- Step 6: Membuat Script Startup VPS ---
# Script yang menjalankan semua service VPS
RUN cat <<'EOF' > /start-vps.sh
#!/bin/bash

echo "=== Starting VPS Services ==="

# Start cron service
echo "Starting cron service..."
service cron start

# Start ngrok tunnel for SSH
echo "Starting ngrok tunnel..."
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &
NGROK_PID=$!

# Wait for ngrok to initialize
echo "Waiting for ngrok to initialize..."
sleep 10

# Get SSH connection info
echo "=== SSH Connection Information ==="
for i in {1..5}; do
  TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
  if [ -n "$TUNNEL_INFO" ]; then
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
            print('Command to connect:')
            print(f'ssh root@{host} -p {port}')
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

# Start SSH server
echo "Starting SSH server..."
/usr/sbin/sshd -D &
SSH_PID=$!

echo "=== VPS Services Started Successfully ==="
echo "SSH PID: $SSH_PID"
echo "Ngrok PID: $NGROK_PID"

# Keep container running
wait $SSH_PID $NGROK_PID
EOF

# Make the script executable
RUN chmod +x /start-vps.sh

# --- Step 7: Expose Ports ---
EXPOSE 22 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000

# --- Step 8: Start VPS ---
CMD ["/start-vps.sh"]
