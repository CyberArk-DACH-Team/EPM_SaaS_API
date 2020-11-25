#####Important Variables
$EPMURL="https://eu.epm.cyberark.com"
$EPMURLInstance = "https://eu124.epm.cyberark.com"

####                  ####
# Variables for Policies #
####                  ####
$targetComputerName = "Fabians-MacBook-Pro"
$targetUserName = "CYBR\john"

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

# Attempt to login
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


# Create JIT Policy
	try {
		#
		#	Get SET to create Advanced policy in (example script only expects 1 result)
		#

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

        #
        #   Get Computer ID to set Advanced policy to
        #

        $ComputersInSet = Invoke-RestMethod -Method Get -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Computers" -Headers $EPMHeader
        $TargetComputerEntry = $ComputersInSet.Computers | where {$_.ComputerName -eq "$targetComputerName"}
        $ComputerID = $TargetComputerEntry.AgentId
        $ComputerInstallTime = $TargetComputerEntry.InstallTime
        $ComputerStatus = $TargetComputerEntry.Status

        #
        # Create JSON variable to Call the API
        #
        $params = @{
            PolicyType = "AdvancedWinApp";
            Name = "My Advanced Policy Test 1";
            Action = "Elevate";
            Activation = @{
                Enabled = "true";
                DeactivateDate = @{
                    Year = "2025";
                    Month = "5";
                    Day = "30";
                    Hours = "8";
                    Minutes = "40";
                    Seconds = "0"
                }
            };
            IncludeComputersInSet = @(@{
                Id = $ComputerID
            });
            IncludeUsers = @(@{
                Username = $targetUserName
            });
            Applications = @(@{
                Type = "EXE";
                Checksum = "SHA1:5FF30FF14984820C01941F767CE47F0F39BDE265";
                FileName = "grep.exe"
                FileSize = 135680;
                Location = "Fixed"
            },@{
                Type = "EXE";
                Description = "Common-Based Script";
                FileName = "cscript.exe";
                FileNameCompare = "Exactly";
                Location = "%SystemRoot%";
                Signature = "Microsoft";
                SignatureCompare = "Prefix"
            },@{
                Type = "EXE";
                Location = "C:\Users\User1\Documents\tmp";
                LocationCompare = "WithSubFolders";
                FileName = "WinMD5.exe";
                Owner = "MyOwnDomain\User1";
                MinFileVersion = "6.1";
                MaxFileVersion = "8.2"
            })
        } | ConvertTo-JSON

        ####             ####
        # Create the Policy #
        ####             ####
        $CreateAdvancedPolicy = Invoke-RestMethod -Method Post -Uri "$EPMURLInstance/EPM/API/$EPMVER/Sets/$SETSelectionID/Policies" -Body $params -ContentType "application/json" -Headers $EPMHeader
	
} catch {
	ParseErrorForResponseBody($_)
}
finally
{
    $Time=Get-Date
    Write-Host "This script ended at $Time"
}



