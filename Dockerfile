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

# --- Step 1: Instalasi Paket Dasar dan Setup SSH ---
# --- PERBAIKAN: Ganti 'tput' dengan 'ncurses-utils' ---
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    ssh wget unzip vim curl python3 bzip2 shc ncurses-utils \
    && rm -rf /var/lib/apt/lists/*

# --- Step 2: Download dan Setup Ngrok ---
RUN wget -q "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${TARGETARCH}.zip" -O /ngrok-stable.zip \
    && cd / && unzip ngrok-stable.zip \
    && chmod +x ngrok \
    && rm ngrok-stable.zip

# --- Step 3: Membuat Script Startup Utama (/openssh.sh) ---
# Script ini akan menjalankan SSH server dan ngrok di background
RUN mkdir -p /run/sshd \
    && cat <<'EOF' > /openssh.sh
#!/bin/bash
set -e

echo "=== Container Startup Script ==="
echo "Starting SSH server and Ngrok tunnel..."

# Jalankan ngrok di background untuk port SSH (22)
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 &

# Tunggu ngrok siap
sleep 10

# Cetak informasi koneksi SSH
echo "Fetching SSH tunnel info..."
for i in {1..5}; do
  TUNNEL_INFO=$(curl -s http://localhost:4040/api/tunnels)
  if [ -n "$TUNNEL_INFO" ]; then
    echo "$TUNNEL_INFO" | python3 -c "import sys, json; print('ssh info:\n', 'ssh', 'root@' + json.load(sys.stdin)['tunnels'][0]['public_url'][6:].replace(':', ' -p '), '\nROOT Password: craxid')"
    break
  else
    echo "SSH tunnel not ready yet, trying again in 5s... (attempt $i/5)"
    sleep 5
  fi
done

# Jalankan SSH server di foreground agar container tetap berjalan
echo "Starting SSH server..."
exec /usr/sbin/sshd -D
EOF

# --- Step 4: Membuat Script Menu RDP (/menu.sh) ---
# Ini adalah script yang akan Anda jalankan setelah login via SSH
RUN cat <<'EOF' > /menu.sh
#!/bin/bash

# Warna dengan tput
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
YELLOW=$(tput setaf 3)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Fungsi untuk mendapatkan IP (akan menunjukkan IP internal container)
get_ip() {
    hostname -I | awk '{print $1}'
}

# Instalasi RDP
install_rdp() {
    echo ""
    echo "${BOLD}${CYAN}💻 Instalasi RDP Dimulai...${RESET}"
    echo "${YELLOW}PERINGATAN: Ini akan mengubah OS container menjadi Windows.${RESET}"
    echo "${YELLOW}Proses ini memakan waktu dan VPS akan disconnect.${RESET}"
    echo ""
    read -p "Apakah Anda yakin? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Mengunduh script installer..."
        wget -q https://github.com/Bintang73/auto-install-rdp/raw/refs/heads/main/main -O setup
        chmod +x setup
        echo "Menjalankan installer..."
        ./setup
    else
        echo "Instalasi dibatalkan."
    fi
    read -p "Tekan Enter untuk kembali ke menu..." dummy
    main_menu
}

# Menu Utama
main_menu() {
    clear
    echo "${CYAN}";
    echo "██████╗ ██████╗ ██████╗       ██╗   ██╗██████╗ ███████╗";
    echo "██╔══██╗██╔══██╗██╔══██╗      ██║   ██║██╔══██╗██╔════╝";
    echo "██████╔╝██║  ██║██████╔╝█████╗██║   ██║██████╔╝███████╗";
    echo "██╔══██╗██║  ██║██╔═══╝ ╚════╝╚██╗ ██╔╝██╔═══╝ ╚════██║";
    echo "██║  ██║██████╔╝██║            ╚████╔╝ ██║     ███████║";
    echo "╚═╝  ╚═╝╚═════╝ ╚═╝             ╚═══╝  ╚═╝     ╚══════╝";
    echo "${RESET}";

    echo "${GREEN}OS         : ${WHITE}Ubuntu Container${RESET}"
    echo "${GREEN}SSH Access : ${WHITE}Aktif via Ngrok${RESET}"
    echo "${GREEN}IP Internal: ${WHITE}$(get_ip)${RESET}"
    echo "${GREEN}Powered By : ${WHITE}@starfz - PurwokertoDev${RESET}"
    echo ""
    echo "${MAGENTA}📋 Pilih Opsi:${RESET}"
    echo "${CYAN}1.${RESET} ${WHITE}Auto Install RDP (Reinstall to Windows)${RESET}"
    echo "${CYAN}2.${RESET} ${WHITE}Check System Info${RESET}"
    echo "${CYAN}8.${RESET} ${RED}Exit Menu${RESET}"

    echo ""
    echo "${YELLOW}====================================================${RESET}"
    echo ""

    printf "${BOLD}${CYAN}Masukkan pilihan Anda (1, 2, 8): ${RESET}"
    read pilihan

    case "$pilihan" in
        1) install_rdp ;;
        2)
            clear
            echo "${YELLOW}📌 System Information${RESET}"
            echo "OS Info:"
            cat /etc/os-release
            echo ""
            echo "Memory Info:"
            free -h
            echo ""
            echo "Disk Info:"
            df -h
            read -p "Tekan Enter untuk kembali ke menu..." dummy
            main_menu
            ;;
        8)
            echo ""
            echo "${BOLD}${CYAN}👋 Kembali ke shell...${RESET}"
            echo ""
            # Keluar dari menu, kembali ke bash
            ;;
        *)
            echo "${RED}Pilihan tidak valid. Silakan pilih antara 1, 2, atau 8.${RESET}"
            sleep 1
            main_menu
            ;;
    esac
}

# Jalankan menu
main_menu
EOF

# --- Step 5: Konfigurasi Akhir ---
# Memberikan permission pada script
RUN chmod +x /openssh.sh /menu.sh

# Mengatur password root dan konfigurasi SSH
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo root:craxid | chpasswd

# Mengekspos port (meskipun tidak langsung digunakan di Cloud Run)
EXPOSE 22 3389

# Command utama yang dijalankan saat container start
CMD ["/openssh.sh"]
