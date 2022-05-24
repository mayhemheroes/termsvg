FROM golang:1.18

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential

ADD . /termsvg
WORKDIR /termsvg

RUN go mod tidy
RUN go build cmd/termsvg/main.go