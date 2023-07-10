## 
##    UEFI raid 1 boot loader fixer
##
##   All rights reserved https://github.com/itpalefox

$raid=("list disk" | diskpart | Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"} | % {$_ -replace ("\s+", " ")} | Foreach {"$(($_ -split ' ')[2,4])"}).Split()
if ($raid.Length -lt "4") { Write-Warning "		Can't find disk with same space "}
For ($i=1; $i -lt $raid.Length; $i+=2) {
		For ($j=$i+2; $j -lt $raid.Length; $j+=2) {
			if ($raid[$i] -eq $raid[$j])
			{ 	
				$diska=$raid[$i-1]
				$diskb=$raid[$j-1]
				Write-Host ""
				Write-Host  " ===================================================================="
				Write-Host  " ==================  UEFI BOOT Fixer FOR RAID 1 ====================="
				Write-Host  " ===================================================================="
				if (-not(Test-Path -Path $env:LOCALAPPDATA\Temp\stage.v -PathType Leaf)) {
				Write-Host " Choose Disk with UEFI boot partition from the list given below:"
				Write-Host ""
				Write-Host -nonewline "[ DISK"$diska" ]"; Write-Host ""
				("select disk $diska `nlist part") -join '' | diskpart |  Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"}
				Write-Host -nonewline "[ DISK"$diskb" ]"; Write-Host ""
				("select disk $diskb `nlist part") -join '' | diskpart |  Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"}
				Write-Host ""
				[string]$diskos = Read-Host -Prompt " Disk number with OS [0/1]"
				$partn=(((("select disk $diskos `nlist part") -join '' | diskpart |  Where-Object {$_ -match "System" -or $_ -match " 99 | 100 " -and $_ -notmatch "###"}) -Split "\s+")[2]) -Join ''
				if (($partn) -eq $null) { [string]$partn = Read-Host -Prompt "System partition number(100+ MB) [1/4]" }
				[string]$adddiskn = Read-Host -Prompt " Disk number to add in RAID [0/1]"
				Set-Content -Path $env:LOCALAPPDATA\Temp\stage.v -Value $diskos","$partn","$adddiskn }
				$con=Get-Content -Path $env:LOCALAPPDATA\Temp\stage.v
				Write-Host ""
				Write-Host  " ===================================================================="
				Write-Host  " |		   						    |"
				Write-Host  " |		      STAGE 1 ^> REBOOT ^> STAGE 2		    |"
				Write-Host  " |		   						    |"
				Write-Host  " ===================================================================="
				Write-Host ""
				Write-Host  " Choose STAGE from the list given below:"
				Write-Host  " [1] STAGE 1 - Create partitions"
				Write-Host  " [2] STAGE 2 - Add second disk to mirror and copy boot loader"
				Write-Host  " [3] Reassign Disks"
				$chkerror=" "
				function ErChk {
					param (
					[PARAMETER(Mandatory=$True,Position=0)]$Diskparts,
					[PARAMETER(Mandatory=$True,Position=1)][String]$FileName
					)
					if ((($diskparts -Like '*Error*').Count) -ne "0") {
							Write-Warning "    DISKPART HAVE AN ERROR!!!  "
							Write-Warning "    SEE DISKPART LOG IN ^> $env:LOCALAPPDATA\Temp\$FileName"
							Set-Content -Path $env:LOCALAPPDATA\Temp\$FileName -Value $diskparts
							break
						}
				}
				Do {
					$Valid = $True
					[string]$stage = Read-Host -Prompt " What stage are we starting?"
					Switch ($stage) {
					{"1" -contains $_} {
						$systemsize=((((echo "select disk "$con[0]" `nlist part") -join '' | diskpart |  Where-Object {$_ -match "System" -and $_ -notmatch "###"}) -Split "\s+")[4]) -Join ''
						Write-Host " ======  START DISKPART AT STAGE 1  ======"
						$chkerror=(echo "select disk "$con[4]" `nclean`nconvert gpt`nselect part 1`ndelete part override") -join '' | diskpart
						ErChk -Diskparts $chkerror -FileName 'ds_stage1'
						if (($con[2]) -ne "1") {
							$resize=((((echo "select disk "$con[0]" `nlist part") -join '' | diskpart |  Where-Object {$_ -match "Recovery" -and $_ -notmatch "###"}) -Split "\s+")[4]) -Join ''
							$chkerror=(echo "select disk "$con[4]" `ncreate partition primary size=$resize`nformat quick fs=ntfs`nset id=`"de94bba4-06d1-4d40-a16a-bfd50179d6ac`"`ngpt attributes=0x8000000000000001") -join '' | diskpart
							ErChk -Diskparts $chkerror -FileName 'ds_stage1_1'
						} 
						$chkerror=(echo "select disk "$con[4]" `ncreate part efi size=$systemsize`nformat quick fs=fat32`ncreate part msr size=16") -join '' | diskpart
						ErChk -Diskparts $chkerror -FileName 'ds_stage1_2'
						Write-Host " ======^> DISKPART DONE"
						Do {
							$rbValid = $True
							[string]$rb = Read-Host -Prompt "^/^> REBOOT the server now? [y/n]"
							Switch ($rb) {
							{"y","Y","Yes","yes" -contains $_} {
								Restart-Computer localhost -force
								Exit
								}
							{"n","N","No","no" -contains $_} {
								Write-Warning "		======  EXIT Without Reboot  ======"
								Exit
								}
							default {
								Write-Warning "		Reboot server have not a valid entry"
								$Valid = $False
								}
							}
						  } Until ($Valid)
						}
					{"2" -contains $_} {
						Write-Host " ======  START DISKPART AT STAGE 2  ======"
						$chkerror=(echo "sel disk "$con[0]" `nconvert dynamic`nsel disk "$con[4]" `nconvert dynamic`nsel vol c`nadd disk "$con[4]" `nsel disk "$con[0]" `nsel part "$con[2]" `nassign letter=P`nsel disk "$con[4]" `nsel part "$con[2]" `nassign letter=S") -join '' | diskpart
						ErChk -Diskparts $chkerror -FileName 'ds_stage2'
						Write-Host " =====^> DISKPART DONE"
						# == Copy EFI files ==
						P:
						cd EFI\Microsoft\Boot
						$bcdid = (((bcdedit /copy `{bootmgr`} /d "Windows Boot Manager 2") -split ('{'))[1] -split ('}'))[0]
						bcdedit /set "`{$bcdid`}" device partition=s:
						bcdedit /export P:\EFI\Microsoft\Boot\BCD2
						robocopy P:\ S:\ /E /R:0
						Rename-Item -Path S:\EFI\Microsoft\Boot\BCD2 -NewName S:\EFI\Microsoft\Boot\BCD
						Remove-Item P:\EFI\Microsoft\Boot\BCD2 -Force
						Write-Host " ======^> DISKPART DONE"
						# == Delete partition letters ==
						Write-Host " ======  START DISKPART AT STAGE 3  ======"
							if (($con[2]) -ne "1") {
								Write-Host " ======  START DISKPART AT STAGE 3.1  ======"
								$chkerror=(echo "sel disk "$con[0]" `nsel part 1 `nassign letter=R`nsel disk "$con[4]" `nsel part 1`nassign letter=T") -join '' | diskpart
								ErChk -Diskparts $chkerror -FileName 'ds_stage3_1'
								robocopy R:\ T:\ /E /R:0
								$chkerror=("sel vol P`nremove`nsel vol S`nremove`nsel vol R`nremove`nsel vol T`nremove") -join '' | diskpart
								ErChk -Diskparts $chkerror -FileName 'ds_stage3_2'
							} else {
								$chkerror=("sel vol P`nremove`nsel vol S`nremove") -join '' | diskpart
								ErChk -Diskparts $chkerror -FileName 'ds_stage3'
							}
						Write-Host " ======^> DISKPART DONE"
						Remove-Item $env:LOCALAPPDATA\Temp\stage.v -Force
						Remove-Item $env:LOCALAPPDATA\Temp\ds_stage* -Force
						}
						{"3" -contains $_} {
							Remove-Item $env:LOCALAPPDATA\Temp\stage.v -Force
							Remove-Item $env:LOCALAPPDATA\Temp\ds_stage* -Force
							Write-Host " ======^> REASSIGN DISK DONE"
							Write-Host " ======^> Please Run Script again! "
						}
					default {
						Write-Warning "		Stage have not a valid entry"
						$Valid = $False
						}
					}
				} Until ($Valid)
								
			}
			
		}
    }