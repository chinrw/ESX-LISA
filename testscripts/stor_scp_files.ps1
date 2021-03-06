###############################################################################
##
## Description:
##   SCP a large file from the VM A to VM B with different disk type.
##
###############################################################################
##
## Revision:
## v1.0 - ldu - 07/31/2018 - Build the script
##
###############################################################################
<#
.Synopsis
    SCP a large file from the VM A to VM B with different disk type
.Description
 <test>
            <testName>stor_scp_big_files</testName>
            <testID>ESX-Stor-015</testID>
            <setupScript>
                <file>SetupScripts\revert_guest_B.ps1</file>
                <file>setupscripts\add_hard_disk.ps1</file>
            </setupScript>
            <testScript>testscripts/stor_scp_files.ps1</testScript>
            <files>remote-scripts/utils.sh</files>
            <files>remote-scripts/stor_scp_big_files.sh</files>
            <testParams>
                <param>DiskType=IDE</param>
                <param>StorageFormat=Thin</param>
                <param>CapacityGB=10</param>
                <param>nfs=10.73.198.145:/mnt/ceph-block/esx</param>
                <param>TC_COVERED=RHEL-34931,RHEL7-50911</param>
            </testParams>
            <cleanupScript>SetupScripts\remove_hard_disk.ps1</cleanupScript>
            <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
            <timeout>9000</timeout>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>
.Parameter vmName
    Name of the VM to add disk.

.Parameter hvServer
    Name of the ESXi server hosting the VM.

.Parameter testParams
    Test data for this test case
#>

param([String] $vmName, [String] $hvServer, [String] $testParams)
#
# Checking the input arguments
#
if (-not $vmName)
{
    "Error: VM name cannot be null!"
    exit
}

if (-not $hvServer)
{
    "Error: hvServer cannot be null!"
    exit
}

if (-not $testParams)
{
    Throw "Error: No test parameters specified"
}

#
# Display the test parameters so they are captured in the log file
#
"TestParams : '${testParams}'"

#
# Parse the test parameters
#
$rootDir = $null
$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "sshKey"       { $sshKey = $fields[1].Trim() }
    "rootDir"      { $rootDir = $fields[1].Trim() }
    "ipv4"         { $ipv4 = $fields[1].Trim() }
    "TestLogDir"   { $testLogDir = $fields[1].Trim() }
    default        {}
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    if ( (Test-Path -Path "${rootDir}") )
    {
        cd $rootDir
    }
    else
    {
        "Warn : rootdir '${rootDir}' does not exist"
    }
}

#
# Source the tcutils.ps1 file
#
. .\setupscripts\tcutils.ps1

PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
                  $env:ENVVISUSERNAME `
                  $env:ENVVISPASSWORD `
                  $env:ENVVISPROTOCOL

###############################################################################
#
# Main Body
#
###############################################################################

$retVal = $Failed

#
# The VM A and the VM B own the same part in names
# RHEL-7.4-20170711.0-x86_64-BIOS-A / RHEL-7.4-20170711.0-x86_64-BIOS-A
# RHEL-7.3-20161019.0-x86_64-EFI-A / RHEL-7.3-20161019.0-x86_64-EFI-B
#
$vmNameB = $vmName -replace "-A$","-B"
$vmObjectB = Get-VMHost -Name $hvServer | Get-VM -Name $vmNameB
Write-Host -F Gray "The VM B is $vmObjectB"
Write-Output "The VM B is $vmObjectB"

# Confirm the VM B power state
$vmObjectBPowerState = $vmObjectB.PowerState
Write-Host -F Gray "The VM B power state is $vmObjectBPowerState"
Write-Output "The VM B power state is $vmObjectBPowerState"
# Boot vmObjectB if its power state isn't PoweredOn and get its IP
if ($vmObjectBPowerState -ne "PoweredOn")
{
    Write-Host -F Gray "Start to power on VM $vmObjectB"
    Write-Output "Start to power on VM $vmObjectB"
    $vmObjectBOn = Start-VM -VM $vmObjectB -Confirm:$False
    $timeout = 360
    while ($timeout -gt 0)
    {
        $vmTemp = Get-VMHost -Name $hvServer | Get-VM -Name $vmNameB
        $vmTempPowerState = $vmTemp.PowerState
        Write-Host -F Gray "The VM B power state is $vmTempPowerState"
        Write-Output "The VM B power state is $vmTempPowerState"
        if ($vmTempPowerState -eq "PoweredOn")
        {
            $ipv4B = GetIPv4 $vmNameB $hvServer
            Write-Host -F Gray "The VM B ipv4 is $ipv4B"
            Write-Output "The VM B ipv4 is $ipv4B"
            if ($ipv4B -ne $null)
            {
                break
            }
        }
        Start-Sleep -S 6
        $timeout = $timeout - 6
        if ($timeout -eq 0)
        {
            Write-Host -F Yellow "WARNING: Timeout, and power off the VM B"
            Write-Output "WARNING: Timeout, and power off the VM B"
            $vmObjectBOff = Stop-VM -VM $vmObjectB -Confirm:$False
            return $Aborted
        }
    }
}
# If its power state is PoweredOn, get its IP
else
{
    $ipv4B = GetIPv4 $vmNameB $hvServer
    Write-Host -F Gray "The VM B ipv4 is $ipv4B"
    Write-Output "The VM B ipv4 is $ipv4B"
    if ($ipv4B -eq $null)
    {
        Write-Host -F Yellow "WARNING: can't get VMB's ipv4, abort. And powered off the VM B"
        Write-Output "WARNING: can't get VMB's ipv4, abort. And powered off the VM B"
        $vmObjectBOff = Stop-VM -VM $vmObjectB -Confirm:$False
        return $Aborted
    }
}

#
# Will use a shell script to change VM's MTU = 9000 and DD a file > 5G and scp it
#
$result = SendCommandToVM $ipv4 $sshKey "cd /root && dos2unix stor_scp_big_files.sh && chmod u+x stor_scp_big_files.sh && ./stor_scp_big_files.sh $ipv4B"
if (-not $result)
{
	Write-Host -F Red "FAIL: Failed to execute stor_scp_big_files.sh in VM"
	Write-Output "FAIL: Failed to execute stor_scp_big_files.sh in VM"
	DisconnectWithVIServer
	Write-Host -F Red "Last, power off the VM B"
    Write-Output "Last, power off the VM B"
    $result = SendCommandToVM $ipv4B $sshKey "rm -f /root/bigfile"
    $vmObjectBOff = Stop-VM -VM $vmObjectB -Confirm:$False
	return $Aborted
}
else
{
	Write-Host -F Green "PASS: Execute stor_scp_big_files script in VM successfully, and power off the VM B"
    Write-Output "PASS: Execute stor_scp_big_files script in VM successfully, and power off the VM B"
    $result = SendCommandToVM $ipv4B $sshKey "rm -f /root/bigfile"
    $retVal = $Passed
    $vmObjectBOff = Stop-VM -VM $vmObjectB -Confirm:$False
}

DisconnectWithVIServer
return $retVal
