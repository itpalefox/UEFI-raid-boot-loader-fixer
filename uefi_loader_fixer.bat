rem 
rem    UEFI raid 1 boot loader fixer
rem
rem   All rights reserved https://github.com/itpalefox

@echo off
rem == change CHCP to UTF-8 ==
CHCP 65001
CLS
set diskpos=0
set diskname=a
:fdisk
if not exist "%TMP%\sdb.ini" ( 
echo select disk %diskpos% > %TMP%\sd%diskname%.ini
echo list part >> %TMP%\sd%diskname%.ini
diskpart /s %TMP%\sd%diskname%.ini > %TMP%\sd%diskname%.rep
setlocal
set diskpos=1
set diskname=b
goto fdisk ) else ( 
	if not exist "%TMP%\stage3.ini" ( goto start ) else ( goto cstate )
	)
:start
echo ====================================================================
echo ==============  UEFI BOOT Fixer FOR RAID 1 =========================
echo ====================================================================
echo.
echo Choose Disk with UEFI boot partition from the list given below:
echo [disk 0]
powershell -Com "type %TMP%\sda.rep | select -Last 4"
echo.
echo [disk 1]
powershell -Com "type %TMP%\sdb.rep | select -Last 4"
echo.
set diskos=0
set /p diskos=^/^> Disk number with OS [0/1]:
set partn=1
set /p partn=^/^> System partition number(100+ MB) [1/4]:
set adddiskn=1
set /p adddiskn=^/^> Disk number to add in RAID [0/1]:
rem == Create stage configs ==
echo select disk %adddiskn% > %TMP%\stage1.ini
echo clean >> %TMP%\stage1.ini
echo convert gpt >> %TMP%\stage1.ini
echo select part 1 >> %TMP%\stage1.ini
echo delete part override >> %TMP%\stage1.ini
rem == Windows RE tools partition ==
rem echo create partition primary size=300 >> %TMP%\stage1.ini
rem echo format quick fs=ntfs >> %TMP%\stage1.ini
rem echo set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac" >> %TMP%\stage1.ini
rem echo gpt attributes=0x8000000000000001 >> %TMP%\stage1.ini
rem == System partition ==
echo create partition efi size=100 >> %TMP%\stage1.ini
echo format quick fs=fat32 >> %TMP%\stage1.ini
rem == Microsoft Reserved (MSR) partition ==
echo create partition msr size=16 >> %TMP%\stage1.ini
rem == Add disk in to mirror ==
echo sel disk %diskos% > %TMP%\stage2.ini
echo convert dynamic >> %TMP%\stage2.ini
echo sel disk %adddiskn% >> %TMP%\stage2.ini
echo convert dynamic >> %TMP%\stage2.ini
echo sel vol c >> %TMP%\stage2.ini
echo add disk %adddiskn% >> %TMP%\stage2.ini
rem == Prepare to copy EFI loader ==
echo sel disk %diskos% >> %TMP%\stage2.ini
echo sel par %partn% >> %TMP%\stage2.ini
echo assign letter=P >> %TMP%\stage2.ini
echo sel disk %adddiskn% >> %TMP%\stage2.ini
echo sel par 1 >> %TMP%\stage2.ini
echo assign letter=S >> %TMP%\stage2.ini
rem == Delete partition letters ==
echo sel vol p > %TMP%\stage3.ini
echo remove >> %TMP%\stage3.ini
echo sel vol s >> %TMP%\stage3.ini
echo remove >> %TMP%\stage3.ini
:cstate
echo ====================================================================
echo ^|							 	   ^|
echo ^|		STAGE 1 ^> REBOOT ^> STAGE 2			   ^|
echo ^|								   ^|
echo ====================================================================
echo.
echo Choose STAGE from the list given below:
echo [1] STAGE 1 - Create partitions
echo [2] STAGE 2 - Add second disk to mirror and copy boot loader
echo [3] Delete script files
set stage=3
set /p stage=^/^> What stage are we starting? :
if %stage%==1 goto 1
if %stage%==2 goto 2
if %stage%==3 goto 3 
:1
echo.
echo ======  START DISKPART AT STAGE 1  ======
diskpart /s %TMP%\stage1.ini > %TMP%\stage1.rep
rem Check that disks is successfully created partitions
type %TMP%\stage1.rep | findstr /C:"error" > %tmp%\stage1_dsp.rep
findstr /C:"error" "%tmp%\stage1_dsp.rep"
if %errorlevel% NEQ 1 (
echo.
echo =====^> DISKPART FAIL - For more detail please check %TMP%\stage1.rep
goto no
) else ( 
echo.
echo =====^> DISKPART DONE
goto 1.2
)
:1.2
echo =====^> DONE
echo =====^> You need to REBOOT the server !
set reboot=y
set /p reboot=^/^> REBOOT the server now? [y/n] (default - %reboot%)?:
if %reboot%==y shutdown /r /t 1
if %reboot%==n goto no
goto :EOF
:2
echo.
echo ======  START DISKPART AT STAGE 2  ======
diskpart /s %TMP%\stage2.ini > %TMP%\stage2.rep
rem Check that disks is convert to dynamic
type %TMP%\stage2.rep | findstr /C:"error" > %tmp%\stage2_dsp.rep
findstr /C:"error" "%tmp%\stage2_dsp.rep"
if %errorlevel% NEQ 1 (
echo.
echo =====^> DISKPART FAIL - For more detail please check %TMP%\stage2.rep
goto no
) else ( 
echo.
echo =====^> DISKPART DONE
goto 2.2
)
:2.2
P:
cd EFI\Microsoft\Boot
bcdedit /copy {bootmgr} /d "Windows Boot Manager 2" > %TMP%\stage2_1.rep
rem == PARSE ID ==
powershell -Com "(((Get-Content %TMP%\stage2_1.rep) -split ('{'))[1] -split ('}'))[0]" > %TMP%\stage2_2.rep
set /p bcdidcut=< %TMP%\stage2_2.rep
bcdedit /set {%bcdidcut%} device partition=s:
bcdedit /export P:\EFI\Microsoft\Boot\BCD2
robocopy P:\ S:\ /E /R:0
rename S:\EFI\Microsoft\Boot\BCD2 BCD
del P:\EFI\Microsoft\Boot\BCD2
echo =====^> DONE
echo ======  START DISKPART AT STAGE 3  ======
diskpart /s %TMP%\stage3.ini > %TMP%\stage3.rep
echo =====^> DONE
echo =====^> Clean script temp files
goto yes
goto :EOF
:3
rem == Delete script files==
set delFiles=y
set /p delFiles=^/^> Delete postinstall files [y/n] (default - %delFiles%)?:
if %delFiles%==y goto yes
if %delFiles%==n goto no
:yes
del %TMP%\sd*.ini /f /q
del %TMP%\sd*.rep /f /q
del %TMP%\stage*.ini /f /q
del %TMP%\stage*.rep /f /q
echo =====^> DONE
goto :EOF
:no
goto :EOF