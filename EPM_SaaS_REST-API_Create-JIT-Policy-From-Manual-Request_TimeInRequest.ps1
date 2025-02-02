#
# Manual Request - Create JIT policy
# Time in Request. Request must end with "...time=<<valid number>>"
# e.g. "JIT Request time=6"
#

cls
write-host '                   ______      __              ___         __  
                  / ____/_  __/ /_  ___  _____/   |  _____/ /__Æ
                 / /   / / / / __ \/ _ \/ ___/ /| | / ___/ //_/
                / /___/ /_/ / /_/ /  __/ /  / ___ |/ /  / ,<   
                \____/\___ /_____/\___/_/  /_/  |_/_/  /_/|_|  
                      ____/' -ForegroundColor blue
write-host "#########################################################################################"-ForegroundColor blue
write-host -nonewline -f blue "# ";write-host -nonewline "  Sample CyberArk EPM SaaS REST-API - Check for Manual Requests and Create JIT Policy ";write-host -f blue "#"
write-host -nonewline -f blue "# ";write-host -nonewline "  Sample by CyberArk - feel free to adopt                                             ";write-host -f blue "#"
write-host -nonewline -f blue "# ";write-host -nonewline "  v1.0 (modified by Fabian Hotarek)                                                   ";write-host -f blue "#"
write-host "#########################################################################################"-ForegroundColor blue

#####Important Variables (example US Datacenter)
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

$APPID = "irrevelent"  #Required not used at this point in time
$LogonBody = @{Username = $Username; Password = $Password; ApplicationID = $APPID} | ConvertTo-JSON

# Function to parse the results of a failure after invoking the rest api
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
# Create JIT Policy
#
	try {
        # Get all SETs
        $SETResult = Invoke-RestMethod -Method Get -Uri "$EPMURL/EPM/API/$EPMVER/Sets" -Headers $EPMHeader
        $i = 0
        [Int]$countSETs = $SETResult.SetsCount

        # Write Out all SETs to choose from
        write-host "Available Sets:"
        do {
            Write-Host -nonewline "[$i] "; write-host $SETResult.Sets[$i].Name
        $i = $i + 1
        }while($i -lt $SETResult.SetsCount)
        [Int]$SETSelection = Read-Host -Prompt "Which SET you want to choose > "
        
        if ($SETSelection -gt -1 -and $SETSelection -lt $countSETs) {
            write-host -nonewline "Selected: "; write-host $SETResult.Sets[$SETSelection].Name
            $SETSelectionID = $SETResult.Sets[$SETSelection].Id
        }
        else{
            write-host "Wrong Selection. Please start again."
            exit 0
        }

        # Get All Computers from SET
        $ComputersInSet = Invoke-RestMethod -Method Get -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Computers" -Headers $EPMHeader
        
        # Get All Policies from SET
        $varPolicies = Invoke-RestMethod -Method Get -Uri $EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies -Headers $EPMHeader

        # Chek for JIT Policies
        [System.Collections.ArrayList]$varJITPolicies = @()
        $counterA = 0
        do {
            if ($varPolicies.Policies[$counterA].PolicyType -eq "AdHocElevate") {
                $result = $varJITPolicies.Add($varPolicies.Policies[$counterA])
            }
            $counterA = $counterA + 1
        } while ($counterA -lt $varPolicies.TotalCount)

        # Check for Active JIT Policies
        [System.Collections.ArrayList]$varJITActivePolicies = @()
        $counterPolicies = 0
        do {
            if ($varJITPolicies[$counterPolicies].Active -eq "True") {
                $result2 = $varJITActivePolicies.Add($varJITPolicies[$counterPolicies])
            }
            $counterPolicies = $counterPolicies + 1
        } while ($counterPolicies -lt $varJITPolicies.Count)

        # Get all Application Events
        $ApplicationEventsInSet = Invoke-RestMethod -Method Get -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Events/ApplicationEvents" -Headers $EPMHeader
        # Get all Manual Requests from Application Events
        $ManualRequestsInSet = $ApplicationEventsInSet.Events | Where-Object -Property EventType -eq "ManualRequest"
        # Change to ArrayList to delete duplicate entries
        [System.Collections.ArrayList]$resultingManualRequestsInSet = @()

        # Delete multiple entries of Manual Request (based on Username & Computername)
        $counterDeleteDuplicates = 0
        do {
            # If list is empty add first manual request
            if ($resultingManualRequestsInSet.Count -eq 0){
                    $counterInitial = 0
                    $addNewLine = "true"
                    $varPolicyID = $varJITActivePolicies[$counterDeleteDuplicates].PolicyID
                    $varJITActivePolicyDetails = Invoke-RestMethod -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies/$varPolicyID" -Method Get -Headers $EPMHeader
                    do {
                        if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventUserName -eq $varJITActivePolicyDetails.IncludeUsers.Username) {
                            $varJITActivePolicyComputerID = $varJITActivePolicyDetails.IncludeComputersInSet.Id
                            $varJITActivePolicyComputer = $ComputersInSet.Computers | where {$_.AgentID -eq "$varJITActivePolicyComputerID"}
                            $varJITActivePolicyComputerName = $varJITActivePolicyComputer.ComputerName
                            if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventComputer -eq $varJITActivePolicyComputerName) {
                                $addNewLine = "false"
                                Write-Host "An active JIT policy already exists for " $varJITActivePolicyDetails.IncludeUsers.Username " & " $ManualRequestsInSet[$counterDeleteDuplicates].LastEventComputer
                            }
                        }
                        $counterInitial = $counterInitial + 1
                    } while ($counterInitial -lt $varJITActivePolicies.Count)
            }
            else {
                # Check if Manual Request is already in resulting list - if not add it
                $counterA = 0
                $addNewLine = "true"
                do {
                    if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventUserName -eq $resultingManualRequestsInSet[$counterA].LastEventUserName) {
                        if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventComputer -eq $resultingManualRequestsInSet[$counterA].LastEventComputer) {
                            $addNewLine = "false"
                        }
                    }
                    $counterA = $counterA + 1
                } while($counterA -lt $resultingManualRequestsInSet.Count)
                
                # Check if an active policy for the username & computername already exists
                if ($addNewLine -eq "true") {
                    $counterB = 0
                    $varPolicyID = $varJITActivePolicies[$counterB].PolicyID
                    $varJITActivePolicyDetails = Invoke-RestMethod -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies/$varPolicyID" -Method Get -Headers $EPMHeader
                    do {
                        if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventUserName -eq $varJITActivePolicyDetails.IncludeUsers.Username) {
                            $varJITActivePolicyComputerID = $varJITActivePolicyDetails.IncludeComputersInSet.Id
                            $varJITActivePolicyComputer = $ComputersInSet.Computers | where {$_.AgentID -eq "$varJITActivePolicyComputerID"}
                            $varJITActivePolicyComputerName = $varJITActivePolicyComputer.ComputerName
                            if ($ManualRequestsInSet[$counterDeleteDuplicates].LastEventComputer -eq $varJITActivePolicyComputerName) {
                                $addNewLine = "false"
                                Write-Host "An active JIT policy already exists for " $varJITActivePolicyDetails.IncludeUsers.Username " & " $ManualRequestsInSet[$counterDeleteDuplicates].LastEventComputer
                            }
                        }
                        $counterB = $counterB + 1
                    } while ($counterB -lt $varJITActivePolicies.Count)
                }
                # Add to resulting list if not exists and no active policy exists
                if ($addNewLine -eq "true") {
                    $resultOut2 = $resultingManualRequestsInSet.Add($ManualRequestsInSet[$counterDeleteDuplicates])
                }
            }
            $counterDeleteDuplicates = $counterDeleteDuplicates + 1
        } while ($counterDeleteDuplicates -lt $ManualRequestsInSet.Count)

        # Go through all Resulting Manual Requests
        $counterManualRequests = 0
        write-host "Creating JIT Policies"
        write-host "---------------------"
        if ($resultingManualRequestsInSet.Count -ne 0) {
            do {
                # Get Username and Computername
                $varJITUsername = $resultingManualRequestsInSet[$counterManualRequests].LastEventUserName
                $varJITUsernameSplit = $varJITUsername.Split("\")
                $varJITUsernamePlainText = $varJITUsernameSplit[1]
                $varJITComputer = $resultingManualRequestsInSet[$counterManualRequests].LastEventComputer
                write-host -NoNewline "Request $counterManualRequests - "; write-host "Create JIT Policy for: " $varJITUsername " on " $varJITComputer

                # Get Raw Application Event Data
                $varFileQualifier = $ManualRequestsInSet[$counterManualRequests].FileQualifier
                $RawApplicationEvent = Invoke-RestMethod -Method Get -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Events/ApplicationEvents/$varFileQualifier" -Headers $EPMHeader
                if ($RawApplicationEvent.Events.Count -eq 1){
                    $varJustification = $RawApplicationEvent.Events.Justification
                    $varEqualsSign = $varJustification.IndexOf("=")
                    $varElevationTimeStart = $varEqualsSign + 1
                    [Int]$varElevationTime = $varJustification.substring($varElevationTimeStart)
                } else {
                    Write-Host "Too many events"
                }

                # Get Computer ID
                $TargetComputerEntry = $ComputersInSet.Computers | where {$_.ComputerName -eq "$varJITComputer"}
                $ComputerID = $TargetComputerEntry.AgentId
                #$ComputerInstallTime = $TargetComputerEntry.InstallTime
                #$ComputerStatus = $TargetComputerEntry.Status

                #
                # Create JSON variable to Call the API
                #
                $params = @{
                    PolicyType = "AdHocElevate";
                    Name = "Automated-JIT-Policy_$varJITUsernamePlainText-$varJITComputer";
                    Duration = "$varElevationTime";
                    TerminateProcesses = "true";
                    Audit = "true";
                    Justification = "true";
                    IncludeUsers = @(@{
                        Username = $varJITUsername;
                        Sid = ""
                    });
                    IncludeComputersInSet = @(@{
                        Id = $ComputerID
                    })
                    LocalGroups = @(@{
                        GroupName = ".\Administrators"
                    })
                } | ConvertTo-JSON

                # Create JIT Policy
                $CreateJITResult = Invoke-RestMethod -Method Post -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies"  -Body $params -ContentType "application/json" -Headers $EPMHeader

                $counterManualRequests = $counterManualRequests + 1
            } while ($counterManualRequests -lt $resultingManualRequestsInSet.Count )
        }
}
catch {
	ParseErrorForResponseBody($_)
}
finally {
    $Time=Get-Date
    Write-Host "This script ended at $Time"
}
