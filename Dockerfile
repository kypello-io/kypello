FROM golang:1.26-alpine AS build

ENV GOPATH=/go
ENV CGO_ENABLED=0

WORKDIR /build

COPY ./kypello /go/bin/kypello
RUN chmod +x /go/bin/kypello

# TODO: switch to kypello-io/kc
RUN go install -ldflags "-s -w" -v github.com/minio/mc@master

FROM registry.access.redhat.com/ubi9/ubi-micro:latest

LABEL name="Kypello" \
      vendor="KypelloIO <dev@kypello.io>" \
      maintainer="KypelloIO <dev@kypello.io>" \
      summary="Kypello is a High Performance Object Storage, API compatible with Amazon S3 cloud storage service." \
      description="Kypello object storage is fundamentally different. Designed for performance and the S3 API, it is 100% open-source. Kypello is ideal for large, private cloud environments with stringent security requirements and delivers mission-critical availability across a diverse range of workloads."

ENV MINIO_ACCESS_KEY_FILE=access_key \
    MINIO_SECRET_KEY_FILE=secret_key \
    MINIO_ROOT_USER_FILE=access_key \
    MINIO_ROOT_PASSWORD_FILE=secret_key \
    MINIO_KMS_SECRET_KEY_FILE=kms_master_key \
    MINIO_CONFIG_ENV_FILE=config.env \
    MC_CONFIG_DIR=/tmp/.mc

RUN chmod -R 777 /usr/bin

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /go/bin/kypello* /usr/bin/
COPY --from=build /go/bin/mc* /usr/bin/

COPY CREDITS /licenses/CREDITS
COPY LICENSE /licenses/LICENSE
COPY dockerscripts/docker-entrypoint.sh /usr/bin/docker-entrypoint.sh

EXPOSE 9000
VOLUME ["/data"]

ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["kypello"]
