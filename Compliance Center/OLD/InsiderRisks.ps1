<#
 .Synopsis
  Pré-configuration for WorkshopPLUS: Securiy and Compliance: Compliance Center

 .Description
  Displays a visual representation of a calendar. This function supports multiple months
  and lets you highlight specific date ranges or days.

    ##################################################################################################
    # This sample script is not supported under any Microsoft standard support program or service.   #
    # This sample script is provided AS IS without warranty of any kind.                             #
    # Microsoft further disclaims all implied warranties including, without limitation, any implied  #
    # warranties of merchantability or of fitness for a particular purpose. The entire risk arising  #
    # out of the use or performance of the sample script and documentation remains with you. In no   #
    # event shall Microsoft, its authors, or anyone else involved in the creation, production, or    #
    # delivery of the scripts be liable for any damages whatsoever (including, without limitation,   #
    # damages for loss of business profits, business interruption, loss of business information,     #
    # or other pecuniary loss) arising out of the use of or inability to use the sample script or    #
    # documentation, even if Microsoft has been advised of the possibility of such damages.          #
    ##################################################################################################

 .Parameter Start
  The first month to display.

 .Parameter End
  The last month to display.

 .Parameter FirstDayOfWeek
  The day of the month on which the week begins.

 .Parameter HighlightDay
  Specific days (numbered) to highlight. Used for date ranges like (25..31).
  Date ranges are specified by the Windows PowerShell range syntax. These dates are
  enclosed in square brackets.

 .Parameter HighlightDate
  Specific days (named) to highlight. These dates are surrounded by asterisks.

 .Example
   # Show a default display of this month.
   Show-Calendar

 .Example
   # Display a date range.
   Show-Calendar -Start "March, 2010" -End "May, 2010"

 .Example
   # Highlight a range of days.
   Show-Calendar -HighlightDay (1..10 + 22) -HighlightDate "December 25, 2008"
#>

##
## New-ModuleManifest -Path .\Scripts\TestModule.psd1 -Author 'Marcelo Hunecke' -CompanyName 'Microsoft' -RootModule 'WorkshopSnC.psm1' -FunctionsToExport @('Get-RegistryKey','Set-RegistryKey') -Description 'This is a Workshop Security and Compliance module.'
##

Param (
    [CmdletBinding()]
    [switch]$debug,
    [switch]$SkipSensitivityLabels,
    [switch]$SkipRetentionPolicies,
    [switch]$SkipDLP,
    [switch]$InsiderRisksOnly
)

# -----------------------------------------------------------
# Write the log
# -----------------------------------------------------------
function logWrite([int]$phase, [bool]$result, [string]$logstring)
{
    if ($result)
        {
            Add-Content -Path $LogCSV -Value "$phase,$result,$(Get-Date),$logString"
            Write-Host -ForegroundColor Green "$(Get-Date) - Phase $phase : $logstring"
        } 
    else 
        {
            Write-Host -ForegroundColor Red "$(Get-Date) - Phase $phase : $logstring"
        }
}

# -----------------------------------------------------------
# Sleep x seconds
# -----------------------------------------------------------
function goToSleep ([int]$seconds){
    for ($i = 1; $i -le $seconds; $i++ )
    {
        $p = ([Math]::Round($i/$seconds, 2) * 100)
        Write-Progress -Activity "Allowing time for the creation on backend..." -Status "$p% Complete:" -PercentComplete $p
        Start-Sleep -Seconds 1
    }
}

# -----------------------------------------------------------
# Start the recovery steps
# -----------------------------------------------------------
function recovery
{
    Write-host "Starting recovery..."
    Set-Location -Path $LogPath
    $global:recovery = $true
    $savedLog = Import-Csv $LogCSV
    $lastEntry = (($savedLog.Count) - 1)
    Write-Debug "Last Entry #: $lastEntry"
    $lastEntry2 = (($savedLog.Count) - 2)
    Write-Debug "Entry Before Last: $lastEntry2"
    $lastEntryPhase = [int]$savedLog[$lastEntry].Phase
    Write-Debug "Last Phase: $lastEntryPhase"
    $lastEntryResult = $savedLog[$lastEntry].Result
    Write-Debug "Last Entry Result: $lastEntryResult"

    if ($lastEntryResult -eq $false)
        {
            if ($lastEntryPhase -eq $savedLog[$lastEntry2].Phase)
                {
                    WriteHost -ForegroundColor Red "The script has failed at Phase $lastEntryPhase repeatedly.  PLease check with your instructor."
                    exitScript
                }
                else 
                    {
                        Write-Host "There was a problem with Phase $lastEntryPhase, so trying again...."
                        $global:nextPhase = $lastEntryPhase
                        Write-Debug "nextPhase set to $global:nextPhase"
                    }
        }
            else
                {
                    # set the phase
                    Write-Host "Phase $lastEntryPhase was successful, so picking up where we left off...."
                    $global:nextPhase = $lastEntryPhase + 1
                    write-Debug "nextPhase set to $global:nextPhase"
                }
}


# -----------------------------------------------------------
# Test the log path (Step 0)
# -----------------------------------------------------------
function initialization
{
    $pathExists = Test-Path($LogPath)
    if (!$pathExists)
        {
            New-Item -ItemType "directory" -Path $LogPath -ErrorAction SilentlyContinue | Out-Null
        }
        Set-Location -Path $LogPath
        Add-Content -Path $LogCSV -Value '"Phase","Result","DateTime","Status"'
        logWrite 0 $true "Initialization completed"
}

# -----------------------------------------------------------
# Connect to AzureAD (Step 1)
# -----------------------------------------------------------
function ConnectAzureAD
{
    try 
        {
            Write-Debug "Get-AzureADDirectoryRole -ErrorAction stop"
            $testConnection = Get-AzureADDirectoryRole -ErrorAction stop | Out-Null #if true (Already Connected)
        }
        catch
            {
                try
                    {
                        write-Debug $error[0].Exception
                        Write-Host "Connecting to Azure AD..."
                        Connect-AzureAD -ErrorAction stop | Out-Null
                    }
                    catch    
                        {
                            try
                                {
                                    write-Debug $error[0].Exception
                                    Write-Host "Installing Azure AD PowerShell Module..."
                                    Install-Module AzureAD -Force -AllowClobber
                                    Connect-AzureAD -ErrorAction stop | Out-Null
                                }
                                catch
                                    {
                                        write-Debug $error[0].Exception
                                        logWrite 1 $false "Couldn't connect to Azure AD. Exiting."
                                        exitScript
                                    }
                       
                        }
            }
    if($global:recovery -eq $false)
        {
            logWrite 1 $true "Successfully connected to Azure AD."
            if ($InsiderRisksOnly -eq $true)
            {
                $global:nextPhase = 41
            }
            else 
                {
                    $global:nextPhase++
                }
            Write-Debug "nextPhase set to $global:nextPhase"
        }
}

# -----------------------------------------------------------
# Connect to Microsoft Online (Step 2)
# -----------------------------------------------------------
function ConnectMsol
{
    try 
    {
        Write-Debug "Get-MSOLCompanyInformation -ErrorAction stop"
        $testConnection = Get-MSOLCompanyInformation -ErrorAction stop | Out-Null #if true (Already Connected)
    }
    catch
        {
            try
                {
                    write-Debug $error[0].Exception
                    Write-Host "Connecting to Microsoft Online..."
                    Connect-MSOLService -ErrorAction stop | Out-Null
                }
                catch    
                    {
                        try
                            {
                                write-Debug $error[0].Exception
                                Write-Host "Installing Microsoft Online PowerShell Module..."
                                Install-Module MSOnline -Force -AllowClobber -ErrorAction stop | Out-Null
                                Connect-MSOLService -ErrorAction stop | Out-Null
                            }
                            catch
                                {
                                    write-Debug $error[0].Exception
                                    logWrite 2 $false "Couldn't connect to Microsoft Online. Exiting."
                                    exitScript
                                }
                   
                    }
        }
        if($global:recovery -eq $false)
            {
                logWrite 2 $true "Successfully connected to Microsoft Online"
                $global:nextPhase++
                Write-Debug "nextPhase set to $global:nextPhase"
            }
}

# -------------------------------------------------------
# Download Workshop Script (Step 9)
# -------------------------------------------------------
function downloadscripts
{
    try
        {
            #General scripts
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/Update-Hub.ps1 -OutFile "$($LogPath)Update-Hub.ps1" -ErrorAction Stop
            #Labels scritp
            Write-Debug "Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-label.ps1 -OutFile $($LogPath)wks-new-label.ps1 -ErrorAction Stop"
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-label.ps1 -OutFile "$($LogPath)wks-new-label.ps1" -ErrorAction Stop
            #DLP Script
            Write-Debug "Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-DLP.ps1 -OutFile $($LogPath)wks-new-DLP.ps1 -ErrorAction Stop"
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-DLP.ps1 -OutFile "$($LogPath)wks-new-DLP.ps1" -ErrorAction Stop
            #Retention script
            Write-Debug "Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-retention.ps1 -OutFile $($LogPath)wks-new-retention.ps1 -ErrorAction Stop"
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-retention.ps1 -OutFile "$($LogPath)wks-new-retention.ps1" -ErrorAction Stop
            #InsiderRisk scripts
            Write-Debug "Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-HRConnector.ps1 -OutFile $($LogPath)wks-new-HRConnector.ps1 -ErrorAction Stop"
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/WKSPlus-M365SCC/main/Compliance%20Center/wks-new-HRConnector.ps1 -OutFile "$($LogPath)wks-new-HRConnector.ps1" -ErrorAction Stop
            Write-Debug "Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/m365-hrconnector-sample-scripts/master/upload_termination_records.ps1 -OutFile $($LogPath)upload_termination_records.ps1 -ErrorAction Stop"
            Invoke-WebRequest -Uri https://raw.githubusercontent.com/microsoft/m365-hrconnector-sample-scripts/master/upload_termination_records.ps1 -OutFile "$($LogPath)upload_termination_records.ps1" -ErrorAction Stop
        } 
        catch 
            {
                write-Debug $error[0].Exception
                logWrite 3 $false "Unable to download the workshop scripts from GitHub! Exiting."
                exitScript
            }
    if($global:recovery -eq $false)
        {
            logWrite 3 $True "Successfully downloaded the workshop scripts."
            $global:nextPhase++
            Write-Debug "nextPhase set to $global:nextPhase"
        }
}       


#######################################################################################
#########                    I N S I D E R     R I S K S                     ##########
#######################################################################################

# -------------------------------------------------------
# InsiderRisks - Create an Azure App (Step 41)
# -------------------------------------------------------
function InsiderRisks_CreateAzureApp
{
    try
        {
            $AzureADAppReg = New-AzureADApplication -DisplayName HRConnector -AvailableToOtherTenants $false -ErrorAction Stop
            $appname = $AzureADAppReg.DisplayName
            $global:appid = $AzureADAppReg.AppID
            $AzureTenantID = Get-AzureADTenantDetail
            $global:tenantid = $AzureTenantID.ObjectId
            $AzureSecret = New-AzureADApplicationPasswordCredential -CustomKeyIdentifier PrimarySecret -ObjectId $azureADAppReg.ObjectId -EndDate ((Get-Date).AddMonths(6)) -ErrorAction Stop
            $global:Secret = $AzureSecret.value

            write-host "##################################################################" -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##   Microsoft 365 Security and Compliance: Compliance Center   ##" -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##   App name  : $appname                                    ##" -ForegroundColor Green
            write-host "##   App ID    : $global:appid           ##" -ForegroundColor Green
            write-host "##   Tenant ID : $global:tenantid           ##" -ForegroundColor Green
            write-host "##   App Secret: $global:secret   ##" -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##################################################################" -ForegroundColor Green
            write-host
            Write-host "Return to the lab instructions" -ForegroundColor Yellow
            Write-host "When requested, press ENTER to continue." -ForegroundColor Yellow
            write-host
        }
        catch 
        {
            write-Debug $error[0].Exception
            logWrite 4 $false "Error creating the Azure App for HR Connector"
            exitScript
        }
    if($global:recovery -eq $false)
        {
            logWrite 4 $True "Successfully created the Azure App for HR Connector."
            $global:nextPhase++
            Write-Debug "nextPhase set to $global:nextPhase"
        }
}

# -------------------------------------------------------
# InsiderRisks - Create the CSV file (Step 42)
# -------------------------------------------------------
function InsiderRisks_CreateCSVFile
{
    $CurrentPath = Get-Location
    write-host "##################################################################" -ForegroundColor Green
    write-host "##                                                              ##" -ForegroundColor Green
    write-host "##   Microsoft 365 Security and Compliance: Compliance Center   ##" -ForegroundColor Green
    write-host "##                                                              ##" -ForegroundColor Green
    write-host "##   The CSV file was created on $CurrentPath\wks-new-HRConnector.csv" -ForegroundColor Green
    write-host "##                                                              ##" -ForegroundColor Green
    write-host "##################################################################" -ForegroundColor Green
    write-host
    Write-host "Return to the lab instructions" -ForegroundColor Yellow
    Write-host "When requested, press ENTER to continue." -ForegroundColor Yellow
    write-host

    try 
        {
            $global:HRConnectorCSVFile = "$($LogPath)HRConnector.csv"
            "HRScenarios,EmailAddress,ResignationDate,LastWorkingDate,EffectiveDate,YearsOnLevel,OldLevel,NewLevel,PerformanceRemarks,PerformanceRating,ImprovementRemarks,ImprovementRating" | out-file $HRConnectorCSVFile -Encoding utf8
            $Users = Get-AzureADuser | where-object {$null -ne $_.AssignedLicenses} | Select-Object UserPrincipalName -ErrorAction Stop

            foreach ($User in $Users)
                {
                    $EmailAddress = $User.UserPrincipalName
                    #Resignation block
                    $RandResignationDate  = Get-Random -Minimum 20 -Maximum 30
                    $ResignationDate = (Get-Date).AddDays(-$RandResignationDate).ToString("yyyy-MM-ddTH:mm:ssZ")
                    $RandLastWorkingDate = Get-Random -Minimum 10 -Maximum 20
                    $LastWorkingDate = (Get-Date).AddDays(-$RandLastWorkingDate).ToString("yyyy-MM-ddTH:mm:ssZ")
                    $RandEffectiveDate = Get-Random -Minimum 365 -Maximum 1000
                    $EffectiveDate = (Get-Date).AddDays(-$RandEffectiveDate).ToString("yyyy-MM-ddTH:mm:ssZ")
                    #Employee level block
                    $YearsOnLevel = Get-Random -Minimum 1 -Maximum 6
                    $OldLevel = Get-Random -Minimum 57 -Maximum 64
                    $NewLevel = $OldLevel--
                    #performance and performance review block
                    $RandRating = Get-Random -Minimum 1 -Maximum 4
                    Switch ($RandRating) 
                        {
                            1 
                                {
                                    $PerformanceRemarks = "Achieved all commitments and exceptional results that surpassed expectations"
                                    $PerformanceRating = "1 - Exceeded"
                                    $ImprovementRemarks = $null
                                    $ImprovementRating = $null
                                }
                            2 
                                {
                                    $PerformanceRemarks = "Achieved all commitments and expected results"
                                    $PerformanceRating = "2 - Achieved"
                                    $ImprovementRemarks = "Increase the team collaboration"
                                    $ImprovementRating = "1 - Exceeded"
                                }
                            3
                                {
                                    $PerformanceRemarks = "Failed to achieve commitments or expected results or both"
                                    $PerformanceRating = "3 - Underperformed"
                                    $ImprovementRemarks = "Increase overall performance"
                                    $ImprovementRating = "2 - Achieved"
                                }
                        }
                    "Resignation,$EmailAddress,$ResignationDate,$LastWorkingDate," | out-file $HRConnectorCSVFile -Encoding utf8 -Append -ErrorAction Stop
                    "Job level changes,$EmailAddress,,,$EffectiveDate,$YearsOnLevel,Level $OldLevel,Level $NewLevel" | out-file $HRConnectorCSVFile -Encoding utf8 -Append -ErrorAction Stop
                    "Performance review,$EmailAddress,,,$EffectiveDate,,,,$PerformanceRemarks,$PerformanceRating" | out-file $HRConnectorCSVFile -Encoding utf8 -Append -ErrorAction Stop
                    "Performance improvement plan,$EmailAddress,,,$EffectiveDate,,,,,,$ImprovementRemarks,$ImprovementRating,"  | out-file $HRConnectorCSVFile -Encoding utf8 -Append -ErrorAction Stop
                }
        }
        catch 
        {
            write-Debug $error[0].Exception
            logWrite 5 $false "Error creating the HRConnector.csv file"
            exitScript
        }
    if($global:recovery -eq $false)
        {
            logWrite 5 $True "Successfully created the HRConnector.csv file."
            $global:nextPhase++
            Write-Debug "nextPhase set to $global:nextPhase"
        }
}

# -------------------------------------------------------
# InsiderRisks - Upload CSV file (Step 43)
# -------------------------------------------------------
function InsiderRisks_UploadCSV
{

    try   
        {
            $ConnectorJobID = Read-Host "Paste the Connector job ID"
            if ($null -eq $ConnectorJobID)
                {
                    $ConnectorJobID = Read-Host "Paste the Connector job ID"
                }
            Write-Host
            write-host "##################################################################" -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##   Microsoft 365 Security and Compliance: Compliance Center   ##" -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##   App ID    : $global:appid           ##" -ForegroundColor Green
            write-host "##   Tenant ID : $global:tenantid           ##" -ForegroundColor Green
            write-host "##   App Secret: $global:secret   ##" -ForegroundColor Green
            write-host "##   JobId     : $ConnectorJobID           ##" -ForegroundColor Green
            write-host "##   CSV File  : $global:HRConnectorCSVFile           " -ForegroundColor Green
            write-host "##                                                              ##" -ForegroundColor Green
            write-host "##################################################################" -ForegroundColor Green
            Write-Host

            Set-Location -Path "$env:UserProfile\Desktop\SCLabFiles\Scripts"
            .\upload_termination_records.ps1 -tenantId $tenantId -appId $appId -appSecret $Secret -jobId $ConnectorJobID -csvFilePath $HRConnectorCSVFile
        }
        catch 
        {
            write-Debug $error[0].Exception
            logWrite 6 $false "Error uploading the HRConnector.csv file"
            exitScript
        }
    if($global:recovery -eq $false)
        {
            logWrite 6 $True "Successfully creating the HRConnector.csv file."
            $global:nextPhase++
            Write-Debug "nextPhase set to $global:nextPhase"
        }
}

# -------------------------------------------------------
# Exit function
# -------------------------------------------------------
function exitScript
{
    # Get-PSSession | Remove-PSSession
    if ($debug)
        {
            $DebugPreference = $oldDebugPreference
            Stop-Transcript
        }
    exit
}

# -------------------------------------------------------
# FUNCTION - Start-SnCCompliance
# -------------------------------------------------------

# -------------------------------------------------------
# Variable definition - General
# -------------------------------------------------------
$LogPath = "$env:UserProfile\Desktop\SCLabFiles\Scripts\"
$LogCSV = "$env:UserProfile\Desktop\SCLabFiles\Scripts\InsiderRisks_Log.csv"
$global:nextPhase = 1
$global:recovery = $false

# -----------------------------------------------------------
# Debug mode
# -----------------------------------------------------------
$oldDebugPreference = $DebugPreference
if($debug)
{
    write-debug "Debug Enabled"
    $DebugPreference = "Continue"
    Start-Transcript -Path "$($LogPath)download-debug.txt"
}

if(!(Test-Path($logCSV)))
    {
        # if log doesn't exist then must be first time we run this, so go to initialization
        Write-Debug "Entering Initialization"
        initialization
    } 
        else 
            {
                # if log already exists, check if we need to recover
                Write-Debug "Entering Recovery"
                recovery
                ConnectAzureAD
                ConnectMSOL
                ConnectEXO
                ConnectSCC
                ConnectTeams
                $tenantName = GetDomain
                Write-Debug "$tenantName Returned"
                ConnectSPO $tenantName
            }

# -------------------------------------------------------
# use variable to control phases
# -------------------------------------------------------
if($nextPhase -eq 1)
    {
        write-debug "Phase $nextPhase"
        ConnectAzureAD
    }

if($nextPhase -eq 2)
    {
        write-debug "Phase $nextPhase"
        ConnectMSOL
    }

if($nextPhase -eq 3)
    {
        write-debug "Phase $nextPhase"
        downloadscripts
    }

if($nextPhase -eq 4)
    {
        write-debug "Phase $nextPhase"
        InsiderRisks_CreateAzureApp
        $answer = Read-Host "Press ENTER to continue"
    }

if($nextPhase -eq 5)
    {
        write-debug "Phase $nextPhase"
        InsiderRisks_CreateCSVFile
        $answer = Read-Host "Press ENTER to continue"
    }

if($nextPhase -eq 6)
    {
        write-debug "Phase $nextPhase"
        InsiderRisks_UploadCSV
    }

write-host "Configurarion completed"