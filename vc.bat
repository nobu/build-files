@echo off

setlocal
set name=%~n0
set ver=%name:vc=%0
for /f "usebackq delims== tokens=1*" %%I in (`set VS%ver%COMNTOOLS`) do (
    if "%%I" == "VS%ver%COMNTOOLS" set vsdir=%%J
)
call "%vsdir%..\..\VC\vcvarsall.bat"
%*
