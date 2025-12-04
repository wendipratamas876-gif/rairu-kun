# Ubuntu 22.04 LTS - base image yang sama dengan VPS sungguhan
FROM ubuntu:22.04

# Non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive
# Variabel krusial untuk systemd di container
ENV container=docker

# ARG untuk build time
ARG NGROK_TOKEN
ARG REGION=ap

# ENV untuk runtime
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

# Step 1: Install paket VPS lengkap
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    # Init system (JANTUNG VPS)
    systemd systemd-sysv \
    # SSH server
    openssh-server \
    # Network tools
    net-tools iproute2 iptables \
    # Utilitas umum VPS
    sudo curl wget git vim htop \
    # Python
    python3 python3-pip \
    # File management
    tar gzip unzip \
    # Process monitoring
    iotop sysstat \
    # DNS tools
    dnsutils \
    # SSL certificates
    ca-certificates \
    # Text editor
    nano \
    # Service management
    cron \
    # System utilities
    systemctl \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Step 2: Konfigurasi systemd untuk container
# Langkah WAJIB agar systemd bisa jalan di container
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# Step 3: Setup SSH server
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo "root:kelvin123" | chpasswd

# Step 4: Generate SSH host keys
RUN ssh-keygen -A

# Step 5: Install ngrok
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# Step 6: Buat script untuk ngrok
RUN cat <<'EOF' > /usr/local/bin/start-ngrok.sh
#!/bin/bash
# Pastikan token tersedia
if [ -z "$NGROK_TOKEN" ]; then
    echo "ERROR: NGROK_TOKEN is not set!" > /var/log/ngrok-error.log
    exit 1
fi

# Jalankan ngrok di background
echo "Starting ngrok with region: $REGION" > /var/log/ngrok.log
/ngrok tcp --authtoken "$NGROK_TOKEN" --region "$REGION" 22 >> /var/log/ngrok.log 2>&1 &

# Tunggu ngrok siap
sleep 10

# Coba dapatkan info tunnel
for i in {1..5}; do
    TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
    if [ -n "$TUNNEL_INFO" ]; then
        echo "$TUNNEL_INFO" > /var/log/ngrok-tunnel.json
        break
    fi
    sleep 5
done
EOF
RUN chmod +x /usr/local/bin/start-ngrok.sh

# Step 7: Buat systemd service untuk ngrok
RUN cat <<'EOF' > /etc/systemd/system/ngrok.service
[Unit]
Description=Ngrok Tunnel for SSH
After=network.target ssh.service
Wants=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-ngrok.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Step 8: Simpan environment variables untuk systemd
RUN echo "NGROK_TOKEN=${NGROK_TOKEN}" > /etc/environment && \
    echo "REGION=${REGION}" >> /etc/environment

# Step 9: Enable services
RUN systemctl enable ssh.service && \
    systemctl enable ngrok.service && \
    systemctl enable cron.service

# Step 10: Setup persistent journal logs
RUN mkdir -p /var/log/journal

# Step 11: Expose port
EXPOSE 22

# Step 12: Signal untuk proper shutdown
STOPSIGNAL SIGRTMIN+3

# Step 13: Jalankan systemd sebagai PID 1 (seperti VPS sungguhan)
CMD ["/sbin/init"]
