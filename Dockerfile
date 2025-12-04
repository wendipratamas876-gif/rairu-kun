###########################################################
# Ubuntu 22.04 + Systemd + Docker + SSH + Ngrok
# Build:  docker build --build-arg NGROK_TOKEN=isi_token -t vps-systemd .
# Run:    docker run --privileged -d --name vps \
#            --tmpfs /tmp --tmpfs /run -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
#            -p 22:22 -p 4040:4040 vps-systemd
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

# 1. base + systemd + docker + unzip
RUN apt-get update && apt-get install -y \
      openssh-server sudo systemd systemd-sysv nano vim curl wget net-tools \
      dnsutils iputils-ping htop git python3 python3-pip locales unzip && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. systemd strip
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

# 3. install docker
RUN curl -fsSL https://get.docker.com | bash

# 4. SSH setup
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'root:kelvin123' | chpasswd && \
    ssh-keygen -A

# 5. user
RUN groupadd --gid $USER_GID $USERNAME 2>/dev/null || true && \
    useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME && \
    echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME && \
    usermod -aG docker $USERNAME && \
    echo "$USERNAME:ruse" | chpasswd

# 6. ngrok binary
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok.zip && \
    cd / && unzip ngrok.zip && rm ngrok.zip && chmod +x ngrok

# 7. systemd unit kecil untuk ngrok (supaya tidak pakai systemctl manual)
RUN printf '[Unit]\nDescription=Ngrok SSH Tunnel\nAfter=network.target\n\
[Service]\nType=simple\n\
ExecStart=/ngrok tcp --authtoken ${NGROK_TOKEN} --region ${REGION} 22\n\
Restart=always\n\
[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/ngrok.service

# 8. enable services
RUN systemctl enable ssh docker ngrok

# 9. expose ports
EXPOSE 22 80 443 3306 4040 5432 5700 5701 5010 6800 6900 8080 8888 9000

# 10. systemd jadi PID 1
CMD ["/lib/systemd/systemd"]
