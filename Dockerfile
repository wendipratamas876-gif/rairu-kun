# Menggunakan ubuntu:latest sebagai base image
FROM ubuntu:latest

# --- PERUBAHAN PENTING DI BAGIAN AWAL ---
# ARG digunakan untuk menerima nilai saat build
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETARCH
ARG NGROK_TOKEN
ARG REGION=ap

# --- PERUBAHAN PENTING: Teruskan ARG ke ENV ---
# ENV akan membuat variabel ini tersedia di dalam container saat runtime
# Nilainya diambil dari ARG yang didefinisikan di atas
ENV NGROK_TOKEN=${NGROK_TOKEN}
ENV REGION=${REGION}

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

# --- PERUBAHAN: Membuat script dengan heredoc yang "polos" ---
# Kita tidak perlu khawatir tentang escaping karena kita akan menggunakan
# variabel lingkungan (ENV) yang sudah pasti ada.
RUN mkdir -p /run/sshd \
    && cat <<'EOF' > /openssh.sh
#!/bin/bash
set -e  # Keluar dari script jika ada perintah yang gagal

# Tambahkan baris debug untuk memastikan variabel terbaca (opsional, bisa dihapus nanti)
echo "DEBUG: Ngrok Token is: ${NGROK_TOKEN:0:10}..."
echo "DEBUG: Ngrok Region is: ${REGION}"

# Jalankan ngrok di background
# Karena NGROK_TOKEN dan REGION sudah adalah ENV, mereka bisa diakses langsung
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Tunggu ngrok siap
sleep 10 # Ditambah menjadi 10 detik untuk memberi lebih banyak waktu

# Cetak informasi koneksi SSH
echo "Mengambil info tunnel ngrok..."
# Tambahkan loop untuk mencoba beberapa kali
for i in {1..5}; do
  TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels)
  if [ -n "$TUNNEL_INFO" ]; then
    echo "$TUNNEL_INFO" | python3 -c "import sys, json; print('ssh info:\n', 'ssh', 'root@' + json.load(sys.stdin)['tunnels'][0]['public_url'][6:].replace(':', ' -p '), '\nROOT Password: craxid')"
    break
  else
    echo "Tunnel belum siap, mencoba lagi dalam 5 detik... (percobaan $i/5)"
    sleep 5
  fi
done

# Jalankan SSH server di foreground
echo "Memulai SSH server..."
exec /usr/sbin/sshd -D
EOF

# Atur permission dan konfigurasi SSH
RUN chmod 755 /openssh.sh \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd

EXPOSE 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000
CMD ["/openssh.sh"]
