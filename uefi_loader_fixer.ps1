## 
##    UEFI raid 1 boot loader fixer
##
##   All rights reserved https://github.com/itpalefox
#(echo "list disk" | diskpart | Foreach {"$(($_ -split '\s+',4)[0..2])"} | Select-String -Pattern "Диск" |  Select-String -Pattern "###" -Notmatch).Matches.Length
$test=(echo "list disk" | diskpart | Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"} | % {$_ -replace ("\s+", " ")} | Foreach {"$(($_ -split ' ')[2,5])"}).Split()
For ($i=1; $i -lt $test.Length; $i+=2) {
		For ($j=$i+2; $j -lt $test.Length; $j+=2) {
			if ($test[$i] -eq $test[$j])
			{ 	
				$diska=$test[$i-1]
				$diskb=$test[$j-1]
				Write-Host ""
				Write-Host  " ===================================================================="
				Write-Host  " ==================  UEFI BOOT Fixer FOR RAID 1 ====================="
				Write-Host  " ===================================================================="
				if (-not(Test-Path -Path $env:LOCALAPPDATA\Temp\stage.v -PathType Leaf)) {
				Write-Host "Choose Disk with UEFI boot partition from the list given below:"
				Write-Host ""
				Write-Host -nonewline "[ DISK"$diska" ]"; Write-Host ""
				(echo "select disk $diska `nlist part") -join '' | diskpart |  Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"}
				Write-Host -nonewline "[ DISK"$diskb" ]"; Write-Host ""
				(echo "select disk $diskb `nlist part") -join '' | diskpart |  Where-Object {$_ -match "\d\d " -and $_ -notmatch "###"}
				Write-Host ""
				[string]$diskos = Read-Host -Prompt "Disk number with OS [0/1]"
				$partn=((((echo "select disk $diskos `nlist part") -join '' | diskpart |  Where-Object {$_ -match "System" -or $_ -match "100" -and $_ -notmatch "###"}) -Split "\s+")[2]) -Join ''
				if (($partn) -eq $null) { [string]$partn = Read-Host -Prompt "System partition number(100+ MB) [1/4]" }
				[string]$adddiskn = Read-Host -Prompt "Disk number to add in RAID [0/1]"
				Set-Content -Path $env:LOCALAPPDATA\Temp\stage.v -Value $diskos","$partn","$adddiskn }
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
				#Write-Host  " [3] Delete script files"
				Do {
					$Valid = $True
					[string]$stage = Read-Host -Prompt "What stage are we starting?"
					Switch ($stage) {
					{"1" -contains $_} {
						Write-Host "======  START DISKPART AT STAGE 1  ======"
						(echo "select disk $adddiskn `nclean`nconvert gpt`nselect part 1`ndelete part override`ncreate part efi size=100`nformat quick fs=fat32`ncreate part msr size=16") -join '' | diskpart
						Write-Host "=====^> DISKPART DONE"
						Do {
							$rbValid = $True
							[string]$rb = Read-Host -Prompt "^/^> REBOOT the server now? [y/n]"
							Switch ($rb) {
							{"y","Y","Yes","yes" -contains $_} {
								echo "IN Yes reboot"
								Restart-Computer localhost -force
								Exit
								}
							{"n","N","No","no" -contains $_} {
								echo "IN NO reboot"
								Exit
								}
							default {
								Write-Host "Reboot server have not a valid entry"
								$Valid = $False
								}
							}
						  } Until ($Valid)
						}
					{"2" -contains $_} {
						$con=Get-Content -Path $env:LOCALAPPDATA\Temp\stage.v
						Write-Host "======  START DISKPART AT STAGE 2  ======"
						(echo "sel disk "$con[0]" `nconvert dynamic`nsel disk "$con[4]" `nconvert dynamic`nsel vol c`nadd disk "$con[4]" `nsel disk "$con[0]" `nsel part "$con[2]" `nassign letter=P`nsel disk "$con[4]" `nsel part 1`nassign letter=S") -join '' ###| diskpart
						Write-Host "=====^> DISKPART DONE"
						# == Copy EFI files ==
						P:
						cd EFI\Microsoft\Boot
						$bcdid = (((bcdedit /copy `{bootmgr`} /d "Windows Boot Manager 2") -split ('{'))[1] -split ('}'))[0]
						bcdedit /set "`{$bcdid`}" device partition=s:
						bcdedit /export P:\EFI\Microsoft\Boot\BCD2
						robocopy P:\ S:\ /E /R:0
						Rename-Item -Path S:\EFI\Microsoft\Boot\BCD2 -NewName S:\EFI\Microsoft\Boot\BCD
						Remove-Item P:\EFI\Microsoft\Boot\BCD2 -Force
						Write-Host "=====^> DISKPART DONE"
						# == Delete partition letters ==
						Write-Host "======  START DISKPART AT STAGE 3  ======"
						(echo "sel vol p`nremove`nsel vol s`nremove") -join '' | diskpart
						Write-Host "=====^> DISKPART DONE"
						}
					default {
						Write-Host "Stage have not a valid entry"
						$Valid = $False
						}
					}
				} Until ($Valid)
								
			} 
			
		}
    }
#((Get-Content "$($env:temp)\sda.rep" | select-string "System") -Split "\s+")[2]