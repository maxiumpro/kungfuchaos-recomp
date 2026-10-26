@echo off
rem Builds kfc_recomp.exe (Release, clang-cl, Ninja) into build\.
rem Needs Visual Studio 2022+ (C++ workload, or the Build Tools) for the Windows SDK and
rem CMake/Ninja, and LLVM's clang-cl: the toolkit uses GCC atomics, which MSVC's cl lacks.
rem Run regen.sh first: the generated C in src\recomp\gen is not in the repository.
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul || exit /b 1
set "PATH=%ProgramFiles%\LLVM\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
where clang-cl >nul 2>nul || (echo clang-cl not found: install LLVM & exit /b 1)
if not exist "%~dp0src\recomp\gen\recomp_funcs.h" (echo src\recomp\gen is empty: run regen.sh first & exit /b 1)
cd /d "%~dp0"
if exist build\CMakeCache.txt findstr /c:"clang-cl" build\CMakeCache.txt >nul || rmdir /s /q build
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DXBOXRECOMP_ENHANCE=ON %* || exit /b 1
cmake --build build || exit /b 1
echo BUILD_OK
