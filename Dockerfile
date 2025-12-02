# Menggunakan ubuntu:latest sebagai base image
FROM ubuntu:latest

# --- PERBAIKAN 1: Menentukan Arsitektur Build ---
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH

# Variabel ini akan diteruskan sebagai build-arg
ARG NGROK_TOKEN
ARG REGION=ap

ENV DEBIAN_FRONTEND=noninteractive

# Perintah instalasi paket
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    ssh wget unzip vim curl python3 \
    && rm -rf /var/lib/apt/lists/*

# Mengunduh ngrok yang Sesuai dengan Arsitektur Target
RUN wget -q "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${TARGETARCH}.zip" -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- PERBAIKAN PENTING: Membuat script tanpa substitusi variabel ---
# Perhatikan '\${}' bukan '${}'. Ini mencegah Docker mengganti variabel saat build.
# Variabel akan dibaca saat script dijalankan di container.
RUN mkdir -p /run/sshd \
    && cat <<'EOF' > /openssh.sh
#!/bin/bash
set -e  # Keluar dari script jika ada perintah yang gagal

# Jalankan ngrok di background
# Variabel ini akan dibaca dari environment container saat runtime
/ngrok tcp --authtoken \${NGROK_TOKEN} --region \${REGION} 22 &

# Tunggu ngrok siap
sleep 5

# Cetak informasi koneksi SSH
echo "Mengambil info tunnel ngrok..."
curl -s http://localhost:4040/api/tunnels | python3 -c "import sys, json; print('ssh info:\n', 'ssh', 'root@' + json.load(sys.stdin)['tunnels'][0]['public_url'][6:].replace(':', ' -p '), '\nROOT Password: craxid')" || echo "\nError: Tidak bisa mengambil info tunnel. Periksa NGROK_TOKEN dan log ngrok."

# Jalankan SSH server di foreground
echo "Memulai SSH server..."
/usr/sbin/sshd -D
EOF

# Atur permission dan konfigurasi SSH
RUN chmod 755 /openssh.sh \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd

EXPOSE 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000
CMD ["/openssh.sh"]
