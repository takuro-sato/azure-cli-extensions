# Confidential WCOW info + attestation prebuilt image.
#
# Windows analogue of containers/info.Dockerfile (the LCOW info container). It
# embeds psputilgo.exe -- a small Go tool that calls amdsnppspapi.dll
# (SnpPspIsSnpMode / SnpPspFetchAttestationReport) to fetch a raw AMD SEV-SNP
# attestation report from inside the confidential Windows guest -- plus a Python
# runner (attest.py) that invokes it and emits OUTPUT/ERROR lines for
# scripts/parse_container_output.py.
#
# amdsnppspapi.dll is BUNDLED into the image at /app next to psputilgo.exe (it
# is NOT present in the container's nanoserver System32 and is NOT lazy-loaded
# from the UVM host). The Go tool loads it via windows.NewLazyDLL, whose default
# search order includes the executable's own directory (/app).
#
# Used by three workloads (all reuse this single prebuilt image):
#   * workloads/attestation_cwcow  -- standalone SNP attestation assertion
#   * workloads/info_cwcow         -- info dump + attestation (enhanced)
#   * workloads/many_layers_cwcow  -- exercises a near-cimfs-limit layer count
#
# MUST be built FROM ltsc2025 bases (os.version 10.0.26100): AUC2 confidential
# WCOW only process-isolates ltsc2025 guests. Build on a windows-2025 runner;
# Server 2022 (windows-latest / 10.0.20348) cannot build or run these.
#
# psputilgo.exe is pre-built on the runner with `go build` (GOOS=windows, public
# deps only) and COPY'd in -- there is no Windows golang base image for
# ltsc2025, so we avoid an in-Dockerfile builder stage.

# --- installer stage: lay down a self-contained Python 3.10 ---
FROM mcr.microsoft.com/windows/servercore:ltsc2025-amd64 AS installer
RUN powershell.exe -Command \
    $ErrorActionPreference = 'Stop'; \
    Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe -OutFile c:\python3-install.exe ; \
    Start-Process c:\python3-install.exe -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=C:\Python310' -Wait ; \
    Remove-Item c:\python3-install.exe -Force
RUN python.exe -m pip install --upgrade pip

# --- final image ---
FROM mcr.microsoft.com/windows/nanoserver:ltsc2025-amd64
USER ContainerAdministrator
RUN setx /M PATH "%PATH%;C:\Python310\Scripts\;C:\Python310"
USER ContainerUser
COPY --from=installer ["/Python310", "/Python310"]
WORKDIR /app
# psputilgo.exe is built on the runner (see the Makefile / build job) into
# ./psputil/ before `docker build`. amdsnppspapi.dll is pulled from the team ACR
# (cacidashboardaci OCI artifact prebuilt-test-containers/amdsnppspapi-dll) into
# ./psputil/ by the build job; it MUST sit next to psputilgo.exe so NewLazyDLL
# finds it via the exe-directory search path.
COPY psputil/psputilgo.exe ./psputilgo.exe
COPY psputil/amdsnppspapi.dll ./amdsnppspapi.dll
COPY attest.py ./attest.py
CMD ["python", "./attest.py"]
