<#
Create an AMI of Root Volume from a running instance by using the instance's name tag and tag the resulting AMI with a meaningful tag
Copyright 2017 Air11 Technology LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

    .SYNOPSIS
        Creates an AMI from a running or stopped instance. Skips terminated, pending, or shutting down instances

    .DESCRIPTION
        Creates an AMI from running or stopped instances, then tags it AND its associated snaphots for easy identification.

    .NOTES
        2017-03-28 substantially revised to allow for duplicate instance name tags and to permit only running or stopped instances

    .INPUT
        ./CreateRootAMIbyName -instanceNameTag [InstanceNameTag[] ] [-snapebs] -note [string] -platform [ string ]
        $instanceNameTag must be the exact instance name tag for the instance
        $note is a string to be stored in the comment and log file
        $platform is tag:Platform info that is added to the AMI's and snapshots' tags
        $snapebs (optional) Create snapshots of attached EBS disks
    .EXAMPLE
        ./CreateRootAmibyName -instanceNameTag "MyInstance1, MyInstance2"  -snapebs -note "This comment is stored in the AMI description" -platform "BillingApp"
#>
param
(
    [Parameter(Mandatory = $true)]
    [string[]]$instanceNameTag,
    [Parameter(Mandatory = $true)]
    [string]$note,
    [Parameter(Mandatory = $false)]
    [string]$platform,
    [Parameter(Mandatory = $false)]
    [switch]$snapebs
)
Import-Module AWSPowerShell
$platform = $platform.ToUpper()

$array = @($instanceNameTag)

foreach ($nameTag in $array) # Process all supplied name tags after making sure they are upper-cased. Our convention is upper-case instance name tags
{
    $i = (Get-EC2Instance -Filter @{name ='tag:Name'; values = $nameTag}).instances # Create array of type Amazon.EC2.Model.Instance
    foreach ($instance in $i) # In case there are duplicated name tags, offer a choice to create an AMI only for the instances in running or stopped state
    {
        switch ($instance.state.code)
        {

            0 {
                # Status is pending
                $instance.instanceID + " status is " + $instance.state.code + ": pending, skipped"
            }
            { ($_ -eq 16) -or ($_ -eq 80) } {
                # Status is running or stopped
                Write-Host "`nCreate AMI for $nameTag from instance $($instance.InstanceID), status = $($instance.state.name)?" -ForegroundColor Yellow
                "Comment to store in AMI: $note"
                "Platform tag to be used: $platform"
                $title = 'Create AMI for this instance?'
                $prompt = '[Y]es or [N]o?'
                #$yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Continues'
                #$no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Exits'
                #$options = [System.Management.Automation.Host.ChoiceDescription[]] ($yes, $no)
                #$choice = $host.ui.PromptForChoice($title, $prompt, $options, 0)
                $devices = @()
                $bm_array = @()
                $choice = 0
                if ($choice -eq 1)
                {
                    Write-Host "Instance skipped" -ForegroundColor Red
                    Break
                } # End if
                else
                {
                    Write-Host "Create Image for Instance" -ForegroundColor Green
                    $longTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" # Get current time into a string
                    $tagDesc = "Created by " + $MyInvocation.MyCommand.Name + " on " + $longTime + " with comment: " + $note # Make a nice string for the AMI Description tag
                    $amiName = $nameTag + " AMI " + $longTime # Make a name for the AMI
                    foreach($bm in $instance.BlockDeviceMappings) {
                        if ($bm.DeviceName -ne  "/dev/sda1") {
                            $devices += $bm.DeviceName
                        }
                    }

                    [Int]$i = 0
                    foreach($d in $devices) {
                        $b = New-Object -TypeName Amazon.EC2.Model.BlockDeviceMapping
                        $b.DeviceName = $d
                        $b.VirtualName= "ephemeral" + $i.ToString()
                        $i++
                        $bm_array += $b
                    }
                    $amiID = New-EC2Image -InstanceId $instance.InstanceId -Description $tagDesc -Name $amiName -BlockDeviceMapping $bm_array -NoReboot:$true # Create the AMI, without rebooting the instance in the process
                    Start-Sleep -Seconds 90 # Wait a few seconds just to make sure the call to Get-EC2Image will return the assigned objects for this AMI

                    $shortTime = Get-Date -Format "yyyy-MM-dd" # Shorter date for the name tag
                    $tagName = $nameTag + " AMI " + $shortTime # Sting for use with the name TAG -- as opposed to the AMI name, which is something else and set in New-EC2Image
                    [Amazon.EC2.Model.Tag]$tag = @{ Key = "Name"; Value = $tagName }
                    [Amazon.EC2.Model.Tag]$tagDesc = @{ Key = "Description"; Value = $tagDesc }
                    [Amazon.EC2.Model.Tag]$tagPlat = @{ Key = 'Platform'; Value = $platform }
                    New-EC2Tag -Resources $amiID -Tag $tag
                    New-EC2Tag -Resources $amiID -Tag $tagDesc
                    New-EC2Tag -Resources $amiID -Tag $tagPlat
 
                    Write-Host "`nCompleted instance $($instance.InstanceID), new AMI = $($amiID) " -ForegroundColor Yellow

                    switch ($snapebs)
                    {
                        $true {
                            Write-Host "Create Snapshots of attached EBS disks for Instance" -ForegroundColor Green

                            foreach($bm in $instance.BlockDeviceMappings) {
                                if ($bm.DeviceName -ne  "/dev/sda1") {
                                    $volId = $bm.ebs.VolumeId
                                    $vol = Get-EC2Volume -VolumeId $volId
                                    #  get name tag for volume
                                    $volTags = $vol.Tags
                                    $volName = $volTags.Where({$_.Key -eq "Name"}).Value

                                    # create snapshot with name as per vol name tag
                                    $shortTime = Get-Date -Format "yyyy-MM-dd" # Shorter date for the name tag
                                    $snapDesc =  $volName + " " + $shortTime

                                    Write-Host "`nCreate snapshot for volume = $($volId) $($volName) " -ForegroundColor Yellow

                                    $snap = New-EC2Snapshot -VolumeId $volId -Description $snapDesc -Force
                                    [Amazon.EC2.Model.Tag]$snapTag = @{ Key = "Name"; Value = $volName }
                                    New-EC2Tag -Resources $snap.SnapshotId -Tag $snapTag
                                    Write-Host "`nCompleted snapshot $($snap.SnapshotId), for volume = $($volId) $($volName) " -ForegroundColor Yellow
                                }
                            }
                        }
                        default
                        {
                            Write-Host "Creating Snapshots of attached EBS disks skipped" -ForegroundColor Red
                        }
                    }
                }
            }
            32 {
                # Status is shutting-down
                $instance.instanceID + " status is " + $instance.state.code + ": shutting down,skipped"
            }
            48 {
                # Status is terminated
                $instance.instanceID + " status is " + $instance.state.code + ": terminated, skipped"
            }
            64 {
                # Status is stopping
                $instance.instanceID + " status is " + $instance.state.code + ": stopping, skipped"
            }
            default
            {
                Write-Error "No valid states detected for any of the instances associated with the specified name tag."
            }
        }
    }
}
