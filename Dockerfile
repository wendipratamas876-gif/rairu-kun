###########################################################
# Ubuntu 22.04 + Systemd + Docker + SSH + Ngrok
# Build:  docker build --build-arg NGROK_TOKEN=isi_token -t vps-full .
# Run:    docker run --privileged -d --name vps -p 22:22 -p 4040:4040 vps-full
###########################################################

FROM ubuntu:22.04

ARG NGROK_TOKEN
ARG REGION=ap
ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    NGROK_TOKEN=$NGROK_TOKEN \
    REGION=$REGION

# 1. base packages + systemd + docker deps + unzip
RUN apt-get update && apt-get install -y \
      openssh-server sudo systemd systemd-sysv nano vim curl wget net-tools \
      dnsutils iputils-ping htop git python3 python3-pip locales unzip && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. systemd strip (biar ringan)
RUN cd /lib/systemd/system/sysinit.target.wants && \
    ls | grep -v systemd-tmpfiles-setup | xargs rm -f && \
    rm -f /lib/systemd/system/multi-user.target.wants/* \
          /etc/systemd/system/*.wants/* \
          /lib/systemd/system/local-fs.target.wants/* \
          /lib/systemd/system/sockets.target.wants/*udev* \
          /lib/systemd/system/sockets.target.wants/*initctl* \
          /lib/systemd/system/basic.target.wants/* \
          /lib/systemd/system/anaconda.target.wants/* \
          /lib/systemd/system/plymouth* \
          /lib/systemd/system/systemd-update-utmp*

# 3. install Docker (dind ready)
RUN curl -fsSL https://get.docker.com | bash && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 4. SSH server setup
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'root:kelvin123' | chpasswd && \
    ssh-keygen -A

# 5. create user (pastikan group 1000 ada dulu)
RUN groupadd --gid $USER_GID $USERNAME 2>/dev/null || true && \
    useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME && \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME && \
    usermod -aG docker $USERNAME && \
    echo "$USERNAME:ruse" | chpasswd

# 6. Ngrok binary
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok.zip && \
    cd / && unzip ngrok.zip && rm ngrok.zip && chmod +x ngrok

# 7. systemd enable services
RUN systemctl enable ssh docker

# 8. startup script (systemd + ngrok + ssh)
RUN printf '#!/bin/bash\n\
systemctl start docker\n\
service cron start\n\
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &\n\
exec /usr/sbin/sshd -D\n' > /start-vps.sh && chmod +x /start-vps.sh

# 9. expose ports
EXPOSE 22 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000

# 10. run
CMD ["/start-vps.sh"]
