# Build jellyfin-web
FROM node:20 as jellyfin-web

ARG JELLYFIN_BRANCH

RUN git clone -b ${JELLYFIN_BRANCH} https://github.com/jellyfin/jellyfin-web.git /home/jellyfin/jellyfin-web

WORKDIR /home/jellyfin/jellyfin-web

RUN SKIP_PREPARE=1 npm ci --no-audit
RUN USE_SYSTEM_FONTS=1 npm run build:production

# Build jellyfin-tizen
FROM node:18 as jellyfin-tizen

RUN useradd -m jellyfin -s /bin/bash
USER jellyfin

RUN git clone https://github.com/jellyfin/jellyfin-tizen.git /home/jellyfin/jellyfin-tizen

WORKDIR /home/jellyfin/jellyfin-tizen

COPY --from=jellyfin-web --chown=jellyfin /home/jellyfin/jellyfin-web/dist/ ./dist/

ENV JELLYFIN_WEB_DIR=./dist

RUN npm ci --no-audit

# Tizen stage
FROM ubuntu:22.04 as build

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Poland

RUN apt-get update && apt-get upgrade -y && apt-get install -y tzdata && apt-get install -y wget git expect 

# Create user 
RUN useradd -m jellyfin -s /bin/bash
USER jellyfin

# Install tizen-studio
RUN wget https://download.tizen.org/sdk/Installer/tizen-studio_5.6/web-cli_Tizen_Studio_5.6_ubuntu-64.bin -P /home/jellyfin
RUN chmod a+x /home/jellyfin/web-cli_Tizen_Studio_5.6_ubuntu-64.bin
RUN ./home/jellyfin/web-cli_Tizen_Studio_5.6_ubuntu-64.bin --accept-license /home/jellyfin/tizen-studio
ENV PATH=${PATH}:/home/jellyfin/tizen-studio/tools/ide/bin:/home/jellyfin/tizen-studio/tools

# Copy built app
WORKDIR /home/jellyfin/build
COPY --from=jellyfin-tizen --chown=jellyfin /home/jellyfin/jellyfin-tizen/config.xml ./config.xml
COPY --from=jellyfin-tizen --chown=jellyfin /home/jellyfin/jellyfin-tizen/icon.png ./icon.png
COPY --from=jellyfin-tizen --chown=jellyfin /home/jellyfin/jellyfin-tizen/index.html ./index.html
COPY --from=jellyfin-tizen --chown=jellyfin /home/jellyfin/jellyfin-tizen/tizen.js ./tizen.js
COPY --from=jellyfin-tizen --chown=jellyfin /home/jellyfin/jellyfin-tizen/www/ ./www/

ARG CERT_PASSWORD
ARG CERT_FILENAME
ARG CERT_NAME

# Create certificates
COPY cert/${CERT_FILENAME}.p12 /home/jellyfin/tizen-studio-data/keystore/author/Jellyfin.p12

# Load profile
RUN tizen security-profiles add -n ${CERT_NAME} -a /home/jellyfin/tizen-studio-data/keystore/author/Jellyfin.p12 -p ${CERT_PASSWORD}

# Switch passwords
RUN sed -i 's/\/home\/jellyfin\/tizen-studio-data\/keystore\/author\/Jellyfin.pwd//' /home/jellyfin/tizen-studio-data/profile/profiles.xml
RUN sed -i 's/\/home\/jellyfin\/tizen-studio-data\/tools\/certificate-generator\/certificates\/distributor\/tizen-distributor-signer.pwd/tizenpkcs12passfordsigner/' /home/jellyfin/tizen-studio-data/profile/profiles.xml

# Build Tizen App
RUN tizen build-web

COPY --chown=jellyfin --chmod=744 ./scripts/package-app.sh ./package-app.sh
COPY --chown=jellyfin --chmod=744 ./scripts/install-app.sh ./install-app.sh

RUN ./package-app.sh

ENTRYPOINT [ "./install-app.sh" ]
