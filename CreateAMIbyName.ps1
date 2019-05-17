<#
Create an AMI from a running instance by using the instance's name tag and tag the resulting AMI and all snapshots with a meaningful tag
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
        ./CreateAMIbyName -instanceNameTag [InstanceNameTag[] ] -up [$true | $false] -note [string] -platform [ string ]
        $instanceNameTag must be the exact instance name tag for the instance
        $up (optional) uppercases lowercase name input
        $note is a string to be stored in the comment and log file
        $platform is tag:Platform info that is added to the AMI's and snapshots' tags
    .EXAMPLE
        ./CreateAmibyName -instanceNameTag "MyInstance1, MyInstance2", -up $true, -note "This comment is stored in the AMI description" -platform "BillingApp"
#>
param
(
    [Parameter(Mandatory = $true)]
    [string[]]$instanceNameTag,
    [Parameter(Mandatory = $true)]
    [string]$note,
    [Parameter(Mandatory = $true)]
    [boolean]$up,
    [Parameter(Mandatory = $false)]
    [string]$platform
)
Import-Module AWSPowerShell
$platform = $platform.ToUpper()
switch ($up)
{
    $TRUE {
        $array = @($instanceNameTag.ToUpper())

    }
    default
    {
        $array = @($instanceNameTag)
    }
}

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
                $yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Continues'
                $no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Exits'
                $options = [System.Management.Automation.Host.ChoiceDescription[]] ($yes, $no)
                $choice = $host.ui.PromptForChoice($title, $prompt, $options, 0)
                If ($choice -eq 1)
                {
                    Write-Host "Instance skipped" -ForegroundColor Red
                    Break
                } # End if
                else
                {

                    $longTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" # Get current time into a string
                    $tagDesc = "Created by " + $MyInvocation.MyCommand.Name + " on " + $longTime + " with comment: " + $note # Make a nice string for the AMI Description tag
                    $amiName = $nameTag + " AMI " + $longTime # Make a name for the AMI

                    $amiID = New-EC2Image -InstanceId $instance.InstanceId -Description $tagDesc -Name $amiName -NoReboot:$false # Create the AMI, rebooting the instance in the process
                    Start-Sleep -Seconds 90 # Wait a few seconds just to make sure the call to Get-EC2Image will return the assigned objects for this AMI

                    $shortTime = Get-Date -Format "yyyy-MM-dd" # Shorter date for the name tag
                    $tagName = $nameTag + " AMI " + $shortTime # Sting for use with the name TAG -- as opposed to the AMI name, which is something else and set in New-EC2Image

                    New-EC2Tag -Resources $amiID -Tags @(@{ Key = "Name"; Value = $tagName }, @{ Key = "Description"; Value = $tagDesc }, @{ Key = 'Platform'; Value = $platform }) # Add tags to new AMI

                    $amiProperties = Get-EC2Image -ImageIds $amiID # Get Amazon.EC2.Model.Image
                    $amiBlockDeviceMapping = $amiProperties.BlockDeviceMapping # Get Amazon.Ec2.Model.BlockDeviceMapping
                    $amiBlockDeviceMapping.ebs | `
                    ForEach-Object -Process { New-EC2Tag -Resources $_.SnapshotID -Tags @(@{ Key = "Name"; Value = $amiName }, @{ Key = 'Platform'; Value = $platform }) } # Add tags to snapshots associated with the AMI using Amazon.EC2.Model.EbsBlockDevice
                    Write-Host "`nCompleted instance $($instance.InstanceID), new AMI = $($amiID) " -ForegroundColor Yellow
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
