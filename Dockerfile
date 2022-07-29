FROM golang:1.18 as builder

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential

ADD . /termsvg
WORKDIR /termsvg

RUN go mod tidy
RUN go build cmd/termsvg/main.go

# Package Stage
FROM debian:bookworm-slim
COPY --from=builder /termsvg/main /