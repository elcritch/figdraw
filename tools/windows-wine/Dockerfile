FROM nimlang/nim:2.2.4 AS nim

FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/nim/bin:${PATH}"

RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    fonts-dejavu-core \
    fonts-liberation \
    gcc-mingw-w64-x86-64 \
    wine \
    wine64 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=nim /opt/nim /opt/nim
COPY run.sh /usr/local/bin/figdraw-windows-wine-test

WORKDIR /work
RUN mkdir -p /work/tests
ENTRYPOINT ["/usr/local/bin/figdraw-windows-wine-test"]
