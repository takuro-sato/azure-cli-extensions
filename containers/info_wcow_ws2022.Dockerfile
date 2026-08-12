# Non-confidential Windows Server 2022 info image.
#
# This image intentionally excludes confidential-compute tooling: no
# psputilgo.exe, amdsnppspapi.dll, sign1util.exe, or security-context schema.

FROM mcr.microsoft.com/windows/servercore:ltsc2022-amd64 AS installer
RUN powershell.exe -Command \
    $ErrorActionPreference = 'Stop'; \
    Invoke-WebRequest -Uri https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe -OutFile c:\python3-install.exe ; \
    Start-Process c:\python3-install.exe -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=C:\Python310' -Wait ; \
    Remove-Item c:\python3-install.exe -Force

FROM mcr.microsoft.com/windows/nanoserver:ltsc2022-amd64
USER ContainerAdministrator
RUN setx /M PATH "%PATH%;C:\Python310\Scripts\;C:\Python310"
USER ContainerUser
COPY --from=installer ["/Python310", "/Python310"]
WORKDIR /app
COPY info_wcow.py ./info_wcow.py
CMD ["python", "./info_wcow.py"]
