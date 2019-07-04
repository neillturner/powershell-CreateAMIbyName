# powershell-CreateAMIbyName
Powershell Create AMI by Name 

from https://www.yobyot.com/aws/how-to-tag-amis-and-snapshots-with-aws-powershell-cmdlets/2014/10/21/

Takes an instance tag and creates an AWS snapshot and AMI.

To just take an AMI of the root disk (i.e. C drive) use CreateRootAMIbyName.ps1

To sysprep the server so EC2 administrator password can be obtained from the AWS console
* make sure sysprep-ec2config.ps1 is on the server in the C:/Users/Administrator folder.
* run first the RunSysprep.ps1 script before the CreateAMIbyName.ps1 or CreateRootAMIbyName.ps1 script.
* RunSysprep.ps1 accepts an optional parameter where the script name can be specified if differently named.

This can be specified in a Jenkins pipeline via:

```
pipeline {
     agent any
     parameters {
        choice(choices: ['servera','serverb'],
        description: 'What EC2 Instance?', name: 'instanceNameTag')
        string(defaultValue: "backup", description: 'What comment?', name: 'note')
     }
     stages {
         stage ('CreateAMIByName') {
             steps {
                 script {
                     git branch: 'master',
                        url: 'https://github.com/neillturner/powershell-CreateAMIbyName.git'
                     powershell returnStatus: true, script: ".\\RunSysprep.ps1 -instanceNameTag ${params.instanceNameTag}"
                     powershell returnStatus: true, script: ".\\CreateRootAMIbyName.ps1 -instanceNameTag ${params.instanceNameTag}-note ${params.note} -architecture i386 "

                 }
             }
         }
     }
}
```