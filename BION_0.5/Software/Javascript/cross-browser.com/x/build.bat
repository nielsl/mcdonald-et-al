@echo off

echo - Begin X Library Batch Build -

rem Run XC on all .xcp files in the current dirctory.

for %%f in (*.xcp) do xc\xc %%~nf

echo - End X Library Batch Build -
pause
