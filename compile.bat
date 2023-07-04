@set OPTS=PATCH_ROM="Final_Fantasy_(U).nes"
@set COMPILE_OPTS=-D FFR_BUILD=0
@set LINK_OPTS=
@set GAME_PRE=ff

@call :buildgame
@IF ERRORLEVEL 1 GOTO failure

@set OPTS=PATCH_ROM="ffrbase.nes" 
@set COMPILE_OPTS=-D FFR_BUILD=1
@set GAME_PRE=ffr

@call :buildgame
@IF ERRORLEVEL 1 GOTO failure

@echo.
@echo Success!
@goto :endbuild

:buildgame
make GAME_PRE=%GAME_PRE% FTCFG_PRE=ff DEMO_CFG_NAME=democfg.json5 %OPTS% COMPILE_OPTS="%COMPILE_OPTS% -D MMC=3" LINK_OPTS="%LINK_OPTS%" BHOP_COMPILE_OPTS="-D MMC=3"
@IF ERRORLEVEL 1 GOTO endbuild

@exit /b

:failure
@echo.
@echo Build error!

:endbuild
@exit /b