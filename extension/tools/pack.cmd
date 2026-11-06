@echo off
setlocal
pushd "%~dp0.."

echo [1/5] Build icons
node tools\build-icons.mjs
if errorlevel 1 goto fail

echo.
echo [2/5] Pack dev zip (keeps manifest key)
node tools\pack.mjs
if errorlevel 1 goto fail

echo.
echo [3/5] Pack store zip (removes manifest key)
node tools\pack.mjs --store
if errorlevel 1 goto fail

echo.
echo [4/5] Verify dev package
node tools\verify-pack.mjs
if errorlevel 1 goto fail

echo.
echo [5/5] Verify store package
for /f "delims=" %%f in ('dir /b "dist\*-store.zip"') do node tools\verify-pack.mjs "dist\%%f" --store
if errorlevel 1 goto fail

popd
exit /b 0

:fail
echo.
echo Build failed. See the error above.
popd
exit /b 1
