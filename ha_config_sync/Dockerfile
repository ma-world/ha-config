ARG BUILD_FROM=ghcr.io/hassio-addons/base:16.3.1
FROM ${BUILD_FROM}

RUN apk add --no-cache git openssh-client rsync jq curl

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
