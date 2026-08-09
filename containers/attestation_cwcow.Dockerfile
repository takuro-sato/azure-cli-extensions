FROM mcr.microsoft.com/windows/servercore:ltsc2025-amd64 AS installer
RUN powershell.exe -Command \
    $ErrorActionPreference = 'Stop'; \
    Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe -OutFile c:\python3-install.exe ; \
    Start-Process c:\python3-install.exe -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=C:\Python310' -Wait ; \
    Remove-Item c:\python3-install.exe -Force

FROM mcr.microsoft.com/windows/nanoserver:ltsc2025-amd64
USER ContainerAdministrator
RUN setx /M PATH "%PATH%;C:\Python310"
USER ContainerUser
COPY --from=installer ["/Python310", "/Python310"]
WORKDIR /app
COPY maa_attest.py ./maa_attest.py
CMD ["python", "./maa_attest.py"]
