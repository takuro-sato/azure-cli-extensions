# Confidential WCOW info prebuilt image.
#
# Windows analogue of containers/info.Dockerfile (the LCOW info container). It
# embeds psputilgo.exe -- a small Go tool that calls amdsnppspapi.dll
# (SnpPspIsSnpMode / SnpPspFetchAttestationReport) to fetch a raw AMD SEV-SNP
# attestation report from inside the confidential Windows guest -- plus a Python
# runner (attest.py) that validates the security context and emits OUTPUT/ERROR
# lines for scripts/parse_container_output.py.
#
# amdsnppspapi.dll is bundled into the image at /app next to psputilgo.exe. The
# Go tool loads it via windows.NewLazyDLL, whose default search order includes
# the executable's own directory (/app).
#
# Used by workloads/info_cwcow.
#
# MUST be built FROM ltsc2025 bases (os.version 10.0.26100). Build on a
# windows-2025 runner; Server 2022 cannot build or run these bases.

FROM mcr.microsoft.com/windows/servercore:ltsc2025-amd64 AS installer
RUN powershell.exe -Command \
    $ErrorActionPreference = 'Stop'; \
    Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe -OutFile c:\python3-install.exe ; \
    Start-Process c:\python3-install.exe -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=C:\Python310' -Wait ; \
    Remove-Item c:\python3-install.exe -Force ; \
    Invoke-WebRequest -Uri https://github.com/microsoft/cosesign1go/releases/download/v1.6.0/sign1util.exe -OutFile c:\sign1util.exe
RUN python.exe -m pip install --upgrade pip jsonschema

FROM mcr.microsoft.com/windows/nanoserver:ltsc2025-amd64
USER ContainerAdministrator
RUN setx /M PATH "%PATH%;C:\Python310\Scripts\;C:\Python310"
USER ContainerUser
COPY --from=installer ["/Python310", "/Python310"]
COPY --from=installer ["/sign1util.exe", "/app/sign1util.exe"]
WORKDIR /app
COPY psputil/psputilgo.exe ./psputilgo.exe
COPY psputil/amdsnppspapi.dll ./amdsnppspapi.dll
COPY attest.py ./attest.py
COPY security_context_schema ./security_context_schema
CMD ["python", "./attest.py"]
