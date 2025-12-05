FROM ubuntu:22.04

ARG NGROK_TOKEN
ARG REGION=ap

ENV DEBIAN_FRONTEND=noninteractive \
    NGROK_TOKEN=$NGROK_TOKEN \
    REGION=$REGION

# 1. base tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server wget unzip curl python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. ngrok binary - download langsung dari GitHub
RUN mkdir -p /tmp/ngrok && \
    cd /tmp/ngrok && \
    wget -q https://github.com/nhoya/ngrokCLI/releases/latest/download/ngrok_linux_amd64.zip -O ngrok.zip && \
    unzip ngrok.zip && \
    mv ngrok /usr/local/bin/ && \
    chmod +x /usr/local/bin/ngrok && \
    rm -rf /tmp/ngrok

# 3. sshd setup
RUN mkdir -p /run/sshd && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "root:craxid" | chpasswd

# 4. start script
RUN printf '#!/bin/bash\n\
set -e\n\
touch /var/log/ngrok.log\n\
ngrok tcp --authtoken "${NGROK_TOKEN}" --region "${REGION}" 22 \
           > /var/log/ngrok.log 2>&1 &\nsleep 5\n\
URL=$(curl -s http://localhost:4040/api/tunnels | \
      python3 -c "import sys,json;d=json.load(sys.stdin);print(d[\"tunnels\"][0][\"public_url\"])" 2>/dev/null)\n\
if [ -n "$URL" ]; then\n\
  echo "====================================="\n\
  echo "SSH : ssh root@${URL:6}  -p ${URL##*:}"\n\
  echo "PASS: craxid"\n\
  echo "====================================="\n\
else\n\
  echo "[!] Ngrok tunnel not ready – check NGROK_TOKEN / REGION"\n\
fi\n\
exec /usr/sbin/sshd -D\n' > /start.sh && chmod +x /start.sh

EXPOSE 22 4040
CMD ["/start.sh"]
