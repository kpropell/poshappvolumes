function Get-AppStackActionUrl
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $true)]
			[ValidateSet("Assign","Unassign")]
			[string]
			$ActionType,
			[Parameter(Position=2, Mandatory = $true)]
			[string]
			$ID,
			[Parameter(Position=3, Mandatory = $true)]
			[ValidateSet("User","Computer","Group")]
			[string]
			$EntityType,
			[Parameter(Position=4, Mandatory = $true)]
			[string]
			$DistinguishedName,
			[Parameter(Position=5, Mandatory = $false)]
			[switch]
			$MountImmediately
		)
	process
	{
		$DistinguishedName = $DistinguishedName -replace "CN=","CN%3D"
		$DistinguishedName = $DistinguishedName -replace ",OU=","%2COU%3D"
		$DistinguishedName = $DistinguishedName -replace ",DC=","%2CDC%3D"		
		
		[string]$rtime = $MountImmediately
		$rtime = $rtime.ToLower()
		
		$URL = "http://{0}/cv_api/assignments?action_type={1}&id={2}&assignments%5B0%5D%5Bentity_type%5D={3}&assignments%5B0%5D%5Bpath%5D={4}&rtime={5}&mount_prefix=" -f $AVManager, $ActionType, $ID, $EntityType, $DistinguishedName, $rtime
		
		return $URL
	}	
}

function Get-AppVolumesManagerSession
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $true)]
			[System.Management.Automation.PSCredential]
			$Credential
		)
	process
	{
		$body = @{
			username = $Credential.UserName
			password = $Credential.GetNetworkCredential().Password
		}
		
		$Url = "http://{0}/cv_api/sessions" -f $AVManager
		
		Invoke-RestMethod -SessionVariable 'AVMSession' -Method Post -Uri $Url -Body $body | Out-Null
		
		$Global:AVMSession = $AVMSession
	}
}

function Get-AppStack
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $false)]
			[string]
			$AppStack
		)
	begin
	{
		if (-not([boolean]$AVMSession))
		{
			Get-AppVolumesManagerSession -AVManager $AVManager
		}
	}
	process
	{
		$Url = "http://{0}/cv_api/appstacks" -f $AVManager
		try
		{
			$AppStacks = Invoke-RestMethod -WebSession $AVMSession -Method Get -Uri $Url
		}
		catch
		{
			Get-AppVolumesManagerSession -AVManager $AVManager
			$AppStacks = Invoke-RestMethod -WebSession $AVMSession -Method Get -Uri $Url
		}
		
		if ($AppStack)
		{
			$AppStackID = $AppStacks | Where-Object {$_.Name -eq $AppStack}
		
			if ($AppStackID)
			{
				return $AppStackID
			}
		}
		else
		{
			return $AppStacks
		}
	}	
}

function Get-AppStackAssignment
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $true)]
			[string]
			$AppStack
		)
	begin
	{
		$AppStackID = Get-AppStack -AVManager $AVManager -AppStack $AppStack
	}
	process
	{
		if ($AppStackID)
		{
			$Url = "http://srv-6appvol01/cv_api/appstacks/{0}/assignments" -f $AppStackID.ID
			$Assignments = Invoke-RestMethod -WebSession $AVMSession -Method Get -Uri $Url
			
			if ($Assignments.Count -ge 1)
			{
				foreach ($Assignment in $Assignments)
				{
					New-Object PSCustomObject -Property @{
						Name = $AppStackID.Name
						ID = $AppstackID.ID
						EntityType = $Assignment.entity_type
						Assignment = (($Assignment.name -split '>|<')[2]).Split("\\")[1]
					} | Select Name, ID, EntityType, Assignment
				}
			}
			else
			{
				return $false
			}
		}
	}	
}

function Unassign-AppStack
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $true)]
			[string]
			$AppStack
		)
	begin
	{
		$Assignments = Get-AppStackAssignment -AVManager $AVManager -AppStack $AppStack
	}
	process
	{
		if ($Assignments)
		{
			foreach ($Assignment in $Assignments)
			{
				switch ($Assignment.EntityType) {
					"User" {$DistinguishedName = (Get-ADUser -Identity $Assignment.Assignment).DistinguishedName}
					"Group" {$DistinguishedName = (Get-ADGroup -Identity $Assignment.Assignment).DistinguishedName}
				}
				
				$Url = Get-AppStackActionUrl -AVManager $AVManager -ActionType Unassign -ID $Assignment.ID -EntityType $Assignment.EntityType -DistinguishedName $DistinguishedName
				Invoke-RestMethod -WebSession $AVMSession -Method Post -Uri $Url
			}
		}
	}
}

function Assign-AppStack
{
	[CmdletBinding()]
    [OutputType([psobject])]
		param
		(
			[Parameter(Position=0, Mandatory = $true)]
			[string]
			$AVManager,
			[Parameter(Position=1, Mandatory = $true)]
			[string]
			$AppStack,
			[Parameter(Position=2, Mandatory = $true)]
			[string]
			$Entity,
			[Parameter(Position=3, Mandatory = $true)]
			[ValidateSet("User","Computer","Group")]
			[string]
			$EntityType,
			[Parameter(Position=4, Mandatory = $false)]
			[Switch]
			$MountImmediately
		)
	begin
	{
		$AppStackID = Get-AppStack -AVManager $AVManager -AppStack $AppStack
	}
	process
	{
		switch ($EntityType) {
			"User" {$DistinguishedName = (Get-ADUser -Identity $Entity -ErrorAction SilentlyContinue).DistinguishedName}
			"Group" {$DistinguishedName = (Get-ADGroup -Identity $Entity -ErrorAction SilentlyContinue).DistinguishedName}
		}
		
		
		if ($DistinguishedName)
		{
			if ($MountImmediately -eq $true)
			{
				$Url = Get-AppStackActionUrl -AVManager $AVManager -ActionType Assign -ID $AppStackID.ID -EntityType $EntityType -DistinguishedName $DistinguishedName -MountImmediately
				Invoke-RestMethod -WebSession $AVMSession -Method Post -Uri $Url
			}
			else
			{
				$Url = Get-AppStackActionUrl -AVManager $AVManager -ActionType Assign -ID $AppStackID.ID -EntityType $EntityType -DistinguishedName $DistinguishedName
				Invoke-RestMethod -WebSession $AVMSession -Method Post -Uri $Url
			}
		}
	}
}