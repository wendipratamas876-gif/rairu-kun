# Mengubah basis image dari debian menjadi ubuntu
FROM ubuntu:latest

ARG NGROK_TOKEN
ARG REGION=ap
# Variabel ini tetap berguna untuk mencegah prompt interaktif saat instalasi paket
ENV DEBIAN_FRONTEND=noninteractive

# Perintah instalasi paket tetap sama karena Ubuntu juga menggunakan apt
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    ssh wget unzip vim curl python3 \
    # Membersihkan cache apt untuk mengurangi ukuran image
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok-stable-linux-amd64.zip\
    && cd / && unzip ngrok-stable-linux-amd64.zip \
    && chmod +x ngrok

# --- BARIS YANG DIPERBAIKI ---
# Menggunakan 'mkdir -p' agar tidak error jika direktori sudah ada (baik di Debian maupun Ubuntu)
RUN mkdir -p /run/sshd \
    && echo "/ngrok tcp --authtoken ${NGROK_TOKEN} --region ${REGION} 22 &" >>/openssh.sh \
    && echo "sleep 5" >> /openssh.sh \
    && echo "curl -s http://localhost:4040/api/tunnels | python3 -c \"import sys, json; print(\\\"ssh info:\\\n\\\",\\\"ssh\\\",\\\"root@\\\"+json.load(sys.stdin)['tunnels'][0]['public_url'][6:].replace(':', ' -p '),\\\"\\\nROOT Password:craxid\\\")\" || echo \"\nError：NGROK_TOKEN，Ngrok Token\n\"" >> /openssh.sh \
    && echo '/usr/sbin/sshd -D' >>/openssh.sh \
    && echo 'PermitRootLogin yes' >>  /etc/ssh/sshd_config  \
    && echo root:craxid|chpasswd \
    && chmod 755 /openssh.sh

EXPOSE 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000
CMD ["/openssh.sh"]
