# Menggunakan ubuntu:latest sebagai base image
FROM ubuntu:latest

# --- PERBAIKAN 1: Menentukan Arsitektur Build ---
# Ini membantu Docker BuildX untuk memilih target yang benar
# Nilai 'linux/amd64', 'linux/arm64', dll. akan disediakan saat build
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH

ARG NGROK_TOKEN
ARG REGION=ap
ENV DEBIAN_FRONTEND=noninteractive

# Perintah instalasi paket
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    ssh wget unzip vim curl python3 \
    && rm -rf /var/lib/apt/lists/*

# --- PERBAIKAN 2: Mengunduh ngrok yang Sesuai dengan Arsitektur Target ---
# Kita menggunakan variabel TARGETARCH yang diisi otomatis oleh BuildX
# Ini akan mengunduh 'ngrok-v3-stable-linux-arm64.zip' jika di build untuk ARM64,
# atau 'ngrok-v3-stable-linux-amd64.zip' jika di build untuk AMD64.
RUN wget -q "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${TARGETARCH}.zip" -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- PERBAIKAN 3: Membuat script dengan Shebang yang Benar ---
# Kita mulai file dengan '#!/bin/bash' untuk memastikan sistem tahu cara menjalankannya.
# Menggunakan 'cat <<EOF' adalah cara yang lebih bersih untuk membuat file multi-baris.
RUN mkdir -p /run/sshd \
    && cat <<EOF > /openssh.sh
#!/bin/bash
set -e  # Keluar dari script jika ada perintah yang gagal

# Jalankan ngrok di background
/ngrok tcp --authtoken ${NGROK_TOKEN} --region ${REGION} 22 &

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
