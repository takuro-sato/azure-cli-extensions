# Add exactly 20 non-empty filesystem layers above the Nano Server base image.
FROM mcr.microsoft.com/windows/nanoserver:ltsc2025-amd64

RUN mkdir C:\layers && echo layer-01>C:\layers\01.txt
RUN echo layer-02>C:\layers\02.txt
RUN echo layer-03>C:\layers\03.txt
RUN echo layer-04>C:\layers\04.txt
RUN echo layer-05>C:\layers\05.txt
RUN echo layer-06>C:\layers\06.txt
RUN echo layer-07>C:\layers\07.txt
RUN echo layer-08>C:\layers\08.txt
RUN echo layer-09>C:\layers\09.txt
RUN echo layer-10>C:\layers\10.txt
RUN echo layer-11>C:\layers\11.txt
RUN echo layer-12>C:\layers\12.txt
RUN echo layer-13>C:\layers\13.txt
RUN echo layer-14>C:\layers\14.txt
RUN echo layer-15>C:\layers\15.txt
RUN echo layer-16>C:\layers\16.txt
RUN echo layer-17>C:\layers\17.txt
RUN echo layer-18>C:\layers\18.txt
RUN echo layer-19>C:\layers\19.txt
RUN echo layer-20>C:\layers\20.txt

CMD ["cmd.exe", "/c", "echo ===MANY_LAYERS_OK==="]
