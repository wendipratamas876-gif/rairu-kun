# Menggunakan ubuntu:latest sebagai base image
FROM ubuntu:latest

# --- ARG untuk Build Time ---
# Untuk multi-arch build dan ngrok token
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH
ARG NGROK_TOKEN
ARG REGION=ap

# --- ENV untuk Runtime ---
# Meneruskan ARG ke ENV agar bisa diakses oleh script
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}
ENV DEBIAN_FRONTEND=noninteractive

# --- Step 1: Instalasi Paket Dasar ---
# --- PERBAIKAN: Bersihkan cache apt sebelum instalasi ---
RUN apt-get clean && \
    apt-get update --fix-missing && \
    apt-get upgrade -y && \
    apt-get install -y \
    ssh wget unzip vim curl python3 bzip2 shc ncurses-utils && \
    rm -rf /var/lib/apt/lists/*

# --- Step 2: Download dan Setup Ngrok ---
RUN wget -q "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${TARGETARCH}.zip" -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 3: Membuat Script Startup Utama (/startup.sh) ---
# Script ini akan menjalankan SEMUANYA: SSH, Ngrok, DAN Instalasi RDP
RUN mkdir -p /run/sshd \
    && cat <<'EOF' > /startup.sh
#!/bin/bash
set -e  # Keluar jika ada perintah yang gagal

echo "================================================"
echo "      CONTAINER STARTUP - AUTO INSTALL RDP"
echo "================================================"
echo ""

# Fungsi untuk mencetak info SSH
print_ssh_info() {
    echo "Fetching SSH tunnel info..."
    for i in {1..5}; do
        TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null)
        if [ -n "$TUNNEL_INFO" ]; then
            echo "$TUNNEL_INFO" | python3 -c "import sys, json; print('ssh info:\n', 'ssh', 'root@' + json.load(sys.stdin)['tunnels'][0]['public_url'][6:].replace(':', ' -p '), '\nROOT Password: craxid')"
            break
        else
            echo "SSH tunnel not ready yet... (attempt $i/5)"
            sleep 5
        fi
    done
}

# --- Bagian 1: Jalankan SSH dan Ngrok di Background ---
echo "Starting SSH server and Ngrok tunnel for monitoring..."
# Jalankan ngrok di background untuk port SSH (22)
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Jalankan SSH server di background
/usr/sbin/sshd -D &

# Tunggu beberapa detik agar ngrok dan SSH siap
sleep 15

# Cetak info SSH ke log, ini satu-satunya cara Anda tahu apakah container hidup
print_ssh_info

echo ""
echo "================================================"
echo "       STARTING AUTOMATIC RDP INSTALLATION"
echo "================================================"
echo ""
echo "WARNING: This script will attempt to replace the OS with Windows."
echo "This process is HIGHLY LIKELY TO FAIL in a containerized environment"
echo "like Cloud Run due to permission restrictions."
echo ""

# --- Bagian 2: Jalankan Instalasi RDP ---
# Ini adalah bagian yang akan gagal.
# Kita berikan input otomatis seperti sebelumnya.
# Menggunakan 'yes' atau 'printf' untuk mengotomatisasi input.
# Pilihan: 1 (Windows 10 Atlas), Port: 11304, Password: kelvin123, lalu 'y'
printf "1\n11304\nkelvin123\n\n\ny\n" | wget -q https://github.com/Bintang73/auto-install-rdp/raw/refs/heads/main/main -O setup -O - | bash

echo ""
echo "================================================"
echo "          INSTALLATION PROCESS FINISHED"
echo "================================================"
echo ""
echo "If the installation was successful (unlikely), the container should now"
echo "be running Windows. You can try to connect via RDP."
echo ""
echo "If the installation failed (very likely), the container might have crashed"
echo "or be in an undefined state. Check the logs for errors."
echo ""

# Jika script mencapai sini, berarti instalasi selesai (atau gagal dengan cara tidak fatal).
# Kita perlu menjaga container tetap hidup.
# Jika Windows berhasil diinstall, prosesnya akan mengambil alih.
# Jika gagal, kita masuk ke loop tak terbatas agar container tidak mati.
echo "Entering infinite loop to keep container alive..."
while true; do
    sleep 60
done
EOF

# --- Step 4: Konfigurasi Akhir ---
# Memberikan permission pada script startup
RUN chmod +x /startup.sh

# Mengatur password root dan konfigurasi SSH
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd

# Mengekspos port
EXPOSE 22 3389

# --- Step 5: Ganti CMD ke Script Startup ---
# Sekarang, saat container dijalankan, ia akan menjalankan /startup.sh
CMD ["/startup.sh"]
