rem @echo off

mkdir release

for %%f in (democfg.json5 license.txt readme.txt patch.bat) do copy %%f release
for %%s in (ft.xdelta ftdemo.xdelta ft.ftcfg) do copy ff%%s release

pause