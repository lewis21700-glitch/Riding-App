@rem
@rem Copyright 2015 the original author or authors.
@rem
@rem Licensed under the Apache License, Version 2.0.
@rem

@if "%DEBUG%" == "" @echo off
@rem ##########################################################################
@rem # Gradle startup script for Windows                                     #
@rem ##########################################################################

@if "%OS%" == "Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%" == "" set DIRNAME=.
set APP_BASE_NAME=%~n0
set APP_HOME=%DIRNAME%

@rem Resolve the absolute path of APP_HOME.
for %%i in ("%APP_HOME%") do set APP_HOME=%%~fi

@rem Use bundled Java when present, otherwise the Java installation on PATH.
if defined JAVA_HOME goto findJavaFromJavaHome

@rem Android Studio usually ships a JDK even when JAVA_HOME is unset.
if defined ANDROID_STUDIO_JDK goto findAndroidStudioJdk
if defined STUDIO_JDK goto findStudioJdk

set "STUDIO_JDK=%LOCALAPPDATA%\Programs\Android Studio\jbr"
if exist "%STUDIO_JDK%\bin\java.exe" goto findStudioJdk

set "STUDIO_JDK=%ProgramFiles%\Android\Android Studio\jbr"
if exist "%STUDIO_JDK%\bin\java.exe" goto findStudioJdk

set JAVA_EXE=java.exe
%JAVA_EXE% -version >NUL 2>&1
if "%ERRORLEVEL%" == "0" goto execute

echo.
echo ERROR: Java is required to run the Android build. Install a JDK and set JAVA_HOME.
goto fail

:findAndroidStudioJdk
set "JAVA_HOME=%ANDROID_STUDIO_JDK%"
goto useJavaHome

:findStudioJdk
set "JAVA_HOME=%STUDIO_JDK%"

:findJavaFromJavaHome
set JAVA_HOME=%JAVA_HOME:"=%

:useJavaHome
set JAVA_HOME=%JAVA_HOME:"=%
set JAVA_EXE=%JAVA_HOME%\bin\java.exe
if exist "%JAVA_EXE%" goto execute

echo.
echo ERROR: JAVA_HOME points to an invalid Java installation: %JAVA_HOME%
goto fail

:execute
if not exist "%APP_HOME%\gradle\wrapper\gradle-wrapper.jar" goto missingWrapper
set CLASSPATH=%APP_HOME%\gradle\wrapper\gradle-wrapper.jar
"%JAVA_EXE%" -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*
goto end

:missingWrapper
echo.
echo ERROR: The Gradle wrapper JAR is missing. Run "flutter create ." in the mobile project folder to restore the Android wrapper files.
set ERRORLEVEL=1

:end
@if "%ERRORLEVEL%" == "0" goto mainEnd

:fail
@if not "%ERRORLEVEL%" == "0" exit /b %ERRORLEVEL%

:mainEnd
@if "%OS%" == "Windows_NT" endlocal
