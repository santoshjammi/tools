@echo off
setlocal

for /f %%I in ('wmic os get localdatetime /format:list ^| find "="') do set "%%I"
set "YYYY=%localdatetime:~0,4%"
set /a "MM=1%localdatetime:~4,2% - 100"
set "DD=%localdatetime:~6,2%"
for /f "tokens=%MM%" %%I in ("JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC") do set "month=%%I"

echo %DD%-%month%-%YYYY%
echo %month%%DD%

set hour=%time:~0,2%
if "%hour:~0,1%" == " " set hour=0%hour:~1,1%
echo hour=%hour%
set min=%time:~3,2%
if "%min:~0,1%" == " " set min=0%min:~1,1%
echo min=%min%
set secs=%time:~6,2%
if "%secs:~0,1%" == " " set secs=0%secs:~1,1%
echo secs=%secs%

set buildlog=build_SUITE_%YYYY%%MM%%DD%%hour%%min%%sec%.log
echo %YYYY%%MM%%DD%%hour%%min%%sec% > %buildlog% 2>&1
