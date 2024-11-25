FROM mcr.microsoft.com/aci/skr:2.7

COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.1
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.2
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.3
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.4
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.5
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.6
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.7
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.8
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.9
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.10

COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.11
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.12
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.13
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.14
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.15
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.16
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.17
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.18
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.19
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.20

COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.21
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.22
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.23
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.24
COPY sidecar.Dockerfile /tmp/sidecar.Dockerfile.25

# We can't run the normal skr command because the other container does not
# handle the necessary HTTP request.
CMD [ "/bin/sleep", "infinity" ]
