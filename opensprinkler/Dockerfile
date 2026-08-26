# The base is the firmware image built by rbhr/OpenSprinkler-Firmware, pinned
# in build.yaml. This add-on contains no firmware source: everything below adds
# the Home Assistant contract (options.json, add-on labels) on top of an image
# that already works standalone under plain Docker.
ARG BUILD_FROM
FROM ${BUILD_FROM}

# The base image is debian:bookworm-slim, not the Alpine-based HA base, so jq
# comes from apt rather than being present already.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/*

# BUILD_ARCH and BUILD_VERSION are supplied by the builder build-image action,
# which also overrides io.hass.arch/io.hass.version and the OCI created/source/
# version labels at build time. The defaults below only apply to local builds.
ARG BUILD_ARCH="amd64"
ARG BUILD_VERSION="dev"
LABEL \
    io.hass.name="OpenSprinkler" \
    io.hass.description="OpenSprinkler Pi irrigation controller, with or without sprinkler hardware" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.url="https://github.com/rbhr/ha-app-OpenSprinkler-Server" \
    maintainer="rbhr" \
    org.opencontainers.image.title="OpenSprinkler" \
    org.opencontainers.image.description="OpenSprinkler Pi irrigation controller, with or without sprinkler hardware" \
    org.opencontainers.image.vendor="rbhr" \
    org.opencontainers.image.authors="rbhr" \
    org.opencontainers.image.licenses="GPL-3.0-or-later" \
    org.opencontainers.image.source="https://github.com/rbhr/ha-app-OpenSprinkler-Server" \
    org.opencontainers.image.version="${BUILD_VERSION}"

COPY run.sh /run.sh
RUN chmod +x /run.sh

# CMD must be cleared explicitly. The base image sets
# CMD ["/OpenSprinkler/OpenSprinkler", "-d", "/data"], which Docker would
# otherwise pass to this ENTRYPOINT as arguments -- run.sh would be handed a
# stale data directory as $1 and the -d /data the add-on exists to avoid.
ENTRYPOINT ["/run.sh"]
CMD []
