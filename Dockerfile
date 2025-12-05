FROM ubuntu:22.04

ARG NGROK_TOKEN
ARG REGION=ap

ENV DEBIAN_FRONTEND=noninteractive \
    NGROK_TOKEN=$NGROK_TOKEN \
    REGION=$REGION

# 1. base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server wget unzip curl python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. ngrok binary
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok.zip && \
    cd / && unzip -q ngrok.zip && rm ngrok.zip && chmod +x ngrok

# 3. sshd config + root pass
RUN mkdir -p /run/sshd && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "root:craxid" | chpasswd

# 4. startup script
RUN printf '#!/bin/bash\n\
set -e\n\
touch /var/log/ngrok.log\n\
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &\n\
sleep 5\n\
TUN=$(curl -s http://localhost:4040/api/tunnels | python3 -c "\
import sys,json,os;\
data=json.load(sys.stdin);\
print(data[\"tunnels\"][0][\"public_url\"]) if data.get(\"tunnels\") else sys.exit(1)")\n\
echo "============================================="\n\
echo "SSH command :  ssh root@${TUN:6}  -p ${TUN##*:}"\n\
echo "ROOT password: craxid"\n\
echo "============================================="\n\
exec /usr/sbin/sshd -D\n' > /start.sh && chmod +x /start.sh

EXPOSE 22 4040
CMD ["/start.sh"]FROM ubuntu:22.04

ARG NGROK_TOKEN
ARG REGION=ap

ENV DEBIAN_FRONTEND=noninteractive \
    NGROK_TOKEN=$NGROK_TOKEN \
    REGION=$REGION

# 1. base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server wget unzip curl python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. ngrok binary
RUN wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip -O /ngrok.zip && \
    cd / && unzip -q ngrok.zip && rm ngrok.zip && chmod +x ngrok

# 3. sshd config + root pass
RUN mkdir -p /run/sshd && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "root:craxid" | chpasswd

# 4. startup script
RUN printf '#!/bin/bash\n\
set -e\n\
touch /var/log/ngrok.log\n\
/ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 > /var/log/ngrok.log 2>&1 &\n\
sleep 5\n\
TUN=$(curl -s http://localhost:4040/api/tunnels | python3 -c "\
import sys,json,os;\
data=json.load(sys.stdin);\
print(data[\"tunnels\"][0][\"public_url\"]) if data.get(\"tunnels\") else sys.exit(1)")\n\
echo "============================================="\n\
echo "SSH command :  ssh root@${TUN:6}  -p ${TUN##*:}"\n\
echo "ROOT password: craxid"\n\
echo "============================================="\n\
exec /usr/sbin/sshd -D\n' > /start.sh && chmod +x /start.sh

EXPOSE 22 4040
CMD ["/start.sh"]
