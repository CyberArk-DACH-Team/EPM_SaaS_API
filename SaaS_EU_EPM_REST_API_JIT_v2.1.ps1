#
# SIMPLE Script - Create JIT policy
# v2.1 | Created by Fabian Hotarek
#

#
# Get Parameters
#
$varTargetUsername = "cybr\john"
$varTargetComputer = "Workstation01"
[Int]$varElevationTime = 4

<#
# Read arguments
if (!$args[0] -or !$args[1] -or !$args[2]){
    Write-Host "Please run the script with 3 parameters, example:"
    Write-Host $MyInvocation.MyCommand.Name "cybr\john MyWorkstation01 4"
    exit 0
}
#$varTargetUsername = $args[0]
#$varTargetComputer = $args[1]
#$varElevationTime = $args[2]
#>

#
# Important Variables (example EU & US datacenter)
#
#$EPMURL="https://eu.epm.cyberark.com"
#$EPMURLInstance = "https://eu111.epm.cyberark.com"
$EPMURL="https://login.epm.cyberark.com"
$EPMURLInstance = "https://na111.epm.cyberark.com"

####                  ####
# Hard Coded Credentials #
####                  ####
#----
#$Username = ""          # Change me as needed
#$Password = ""          # Change me as needed
#----

####                             ####
# Read the credential interactively #
####                             ####
#----
$Username = Read-Host -Prompt 'Username'
$inputpw = Read-Host -Prompt 'Password' -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputpw)
$Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#----

#
# Some more variables
#
$APPID = "irrevelent"  #Required not used at this point in time
$LogonBody = @{Username = $Username; Password = $Password; ApplicationID = $APPID} | ConvertTo-JSON

#
# Function to parse the results of a failure after invoking the rest api
#
Function ParseErrorForResponseBody($Error) {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if ($Error.Exception.Response) {  
            $Reader = New-Object System.IO.StreamReader($Error.Exception.Response.GetResponseStream())
            $Reader.BaseStream.Position = 0
            $Reader.DiscardBufferedData()
            $ResponseBody = $Reader.ReadToEnd()
            if ($ResponseBody.StartsWith('{')) {
                $ResponseBody = $ResponseBody | ConvertFrom-Json
            }
            return $ResponseBody
        }
    }
    else {
        return $Error.ErrorDetails.Message
    }
}

# Get the EPM Version info
$EPMVERINFO = Invoke-RestMethod -Uri "$EPMURL/EPM/API/Server/Version"
$EPMVER = $EPMVERINFO.Version

#
# Attempt to login
#
try {
	$EPMLogonResult = Invoke-RestMethod -Uri "$EPMURL/EPM/API/$EPMVER/Auth/EPM/Logon" -Method Post -ContentType "application/json" -Body $LogonBody
	# Store the token returned
	if ($EPMLogonResult.IsPasswordExpired -eq $true) {
		Write-Host "$Username - Password is expired!" -ForegroundColor Red
		exit
	}

	# Build the header to get the sets for this user
    $FullToken = "basic " + $EPMLogonResult.EPMAuthenticationResult
    $EPMHeader = @{}
	$EPMHeader.Add("Authorization", $FullToken)
} catch {
	ParseErrorForResponseBody($_)
}

#
# Main
#
	try {
        # Get all SETs
        $SETResult = Invoke-RestMethod -Method Get -Uri "$EPMURL/EPM/API/$EPMVER/Sets" -Headers $EPMHeader
        $i = 0
        write-host "Available Sets:"
        do {
            Write-Host -nonewline "[$i] "; write-host $SETResult.Sets[$i].Name
        $i = $i + 1
        }while($i -lt $SETResult.SetsCount)
        $SETSelection = Read-Host -Prompt "Which SET you want to choose > "
        
        # Get selected SET
        if (($SETSelection -eq 0) -or ($SETSelection -eq 1)) {
            write-host -nonewline "Selected: "; write-host $SETResult.Sets[$SETSelection].Name
            $SETSelectionID = $SETResult.Sets[$SETSelection].Id
        }
        else{
            write-host "Wrong Selection"
        }

        # Get all Computers registered to SET
        $ComputersInSet = Invoke-RestMethod -Method Get -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Computers" -Headers $EPMHeader

        # List all available computers and select one of the list
        #$varN = 0
        #write-host "Available computers:"
        #do {
        #    write-host -NoNewline "[$varN] "; write-host $ComputersInSet.Computers[$varN].ComputerName
        #    $varN = $varN + 1
        #} while ($varN -lt $ComputersInSet.TotalCount)
        #$ComputerSelection = Read-Host -Prompt "Which Computer you want to choose > "
        #$ComputerSelectionName = $ComputersInSet.Computers[$ComputerSelection].ComputerName

        # Get Computer Agent ID
        $varTargetComputerEntry = $ComputersInSet.Computers | where {$_.ComputerName -eq "$varTargetComputer"}
        
        # if only one entry
        
        if (!$varTargetComputerEntry) {
            $varTargetComputerID = $varTargetComputerEntry.AgentId
            $varTargetComputerInstallTime = $varTargetComputerEntry.InstallTime
            $ComputerStatus = $varTargetComputerEntry.Status
            write-host "ONLY 1"
        }
        # if more than one entry
        elseif ($varTargetComputerEntry.Count -gt 1) {
            [Int]$counter1 = 0
            write-host "MORE THAN 1"
            do {
                if ($varTargetComputerEntry[$counter1].Status -eq "Alive") {
                    write-host "IN SETTINGS"
                    $varTargetComputerID = $varTargetComputerEntry[$counter1].AgentId
                    $varTargetComputerInstallTime = $varTargetComputerEntry[$counter1].InstallTime
                    
                }
                $counter1 = $counter1 + 1
            } while ($counter1 -lt $varTargetComputerEntry.Count)
        }

        # Get Username without domain
        $varTargetUsernameSplit = $varTargetUsername.Split("\")
        $varTargetUsernameOnly = $varTargetUsernameSplit[1]
        write-host "CHECK"

        # Create JSON variable to Call the API
        $params = @{
            PolicyType = "AdHocElevate";
            Name = "Automated-JIT-Policy_$varTargetUsernameOnly-$varTargetComputer";
            Duration = "$varElevationTime";
            TerminateProcesses = "true";
            Audit = "true";
            Justification = "true";
            IncludeUsers = @(@{
            Username = $varTargetUsername;
                Sid = ""
            });
            IncludeComputersInSet = @(@{
                Id = $varTargetComputerID
            })
            LocalGroups = @(@{
                GroupName = ".\Administrators"
            })
        } | ConvertTo-JSON

        write-host "params set"

        # Create JIT Policy
        $CreateJITResult = Invoke-RestMethod -Method Post -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies" -Body $params -ContentType "application/json" -Headers $EPMHeader
            
} catch {
	ParseErrorForResponseBody($_)
}
finally {
    $Time=Get-Date
    Write-Host "This script ended at $Time"
}
