$ErrorActionPreference='Stop'
$build=Join-Path $PSScriptRoot 'native\build'
$output=Join-Path $PSScriptRoot 'package\reframework\plugins'
New-Item -ItemType Directory -Path $build,$output -Force | Out-Null
$vcvars='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
$lines=@('@echo off',"call `"$vcvars`" >nul",'if errorlevel 1 exit /b 1',"cd /d `"$build`"", "cl /nologo /EHsc /std:c++20 /MD /O2 /LD /I`"$PSScriptRoot\dependencies`" `"$PSScriptRoot\native\MenuInput.cpp`" /link user32.lib /OUT:`"$output\friteabc_input.dll`"",'exit /b %errorlevel%')
$cmd=Join-Path $build 'build.cmd'
[IO.File]::WriteAllLines($cmd,$lines)
& cmd.exe /d /c $cmd
if($LASTEXITCODE -ne 0){throw 'Input plugin compilation failed'}
