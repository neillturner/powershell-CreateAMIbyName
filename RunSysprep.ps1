<#
Run remote powershell script to sysprep a windows server. 

#>
param
(
    [Parameter(Mandatory = $true)]
    [string[]]$instanceNameTag,
    [Parameter(Mandatory = $false)]
    [string]$scriptName
)
Import-Module AWSPowerShell
if ($scriptName -eq "") {
   $scriptName = 'C:\Users\Administrator\sysprep-ec2config.ps1'
 }

$array = @($instanceNameTag)

foreach ($nameTag in $array) 
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
            { ($_ -eq 16) } {
                # Status is running
                Write-Host "`nSysprep script $($scriptName) the instance for $nameTag from instance $($instance.InstanceID), status = $($instance.state.name)?" -ForegroundColor Yellow
                $cmd = Send-SSMCommand -InstanceId $instance.InstanceID -DocumentName AWS-RunPowerShellScript -Comment 'sysprep the instance' -Parameter @{'commands'=@($scriptName)}
                Start-Sleep -Seconds 15 # Wait a few seconds to let it complete
                $result = Get-SSMCommand -CommandId $runPSCommand.CommandId
                Write-Host "`nCommand Status $($result.status[0])" -ForegroundColor Yellow
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
            80 {
                # Status is stopped
                $instance.instanceID + " status is " + $instance.state.code + ": stopped, skipped"
            }
            default
            {
                Write-Error "No valid states detected for any of the instances associated with the specified name tag."
            }
        }
    }
}
