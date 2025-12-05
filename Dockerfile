# Ubuntu 22.04 + SSH + Ngrok (tanpa systemd) - cocok untuk PaaS
FROM ubuntu:22.04

ARG NGROK_TOKEN
ARG REGION=ap

ENV DEBIAN_FRONTEND=noninteractive \
    NGROK_TOKEN=$NGROK_TOKEN \
    REGION=$REGION


RUN apt-get update && apt-get install -y \
      openssh-server nano vim curl wget net-tools dnsutils iputils-ping \
      htop git python3 python3-pip unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. ngrok binary
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok.zip && \
    cd / && unzip ngrok.zip && rm ngrok.zip && chmod +x ngrok

# 3. SSH setup
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'root:kelvin123' | chpasswd && \
    ssh-keygen -A

# 4. startup script (no systemd)
RUN printf '#!/bin/bash\n\
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &\n\
/usr/sbin/sshd -D\n' > /start.sh && chmod +x /start.sh

EXPOSE 22 4040
CMD ["/start.sh"]
