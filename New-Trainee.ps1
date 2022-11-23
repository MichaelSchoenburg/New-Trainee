[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $Givenname,

    [Parameter(Mandatory = $false)]
    [string]
    $Surname
)

<#
.SYNOPSIS
    New-Trainee

.DESCRIPTION
    Automated trainee account(s) creation.

.LINK
    GitHub: https://github.com/MichaelSchoenburg/New-Trainee

.NOTES
    Author: Michael Schönburg
    
    Script can be run either interactively or one can pass all variables and process the output.

    This projects code loosely follows the PowerShell Practice and Style guide, as well as Microsofts PowerShell scripting performance considerations.
    Style guide: https://poshcode.gitbook.io/powershell-practice-and-style/
    Performance Considerations: https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations?view=powershell-7.1
#>

#region INITIALIZATION
<# 
    Libraries, Modules, ...
#>

#endregion INITIALIZATION
#region DECLARATIONS
<#
    Declare local variables and global variables
#>



#endregion DECLARATIONS
#region FUNCTIONS
<# 
    Declare Functions
#>

function Write-ConsoleLog {
    <#
    .SYNOPSIS
    Logs an event to the console.
    
    .DESCRIPTION
    Writes text to the console with the current date (US format) in front of it.
    
    .PARAMETER Text
    Event/text to be outputted to the console.
    
    .EXAMPLE
    Write-ConsoleLog -Text 'Subscript XYZ called.'
    
    Long form
    .EXAMPLE
    Log 'Subscript XYZ called.
    
    Short form
    #>
    [alias('Log')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
        Position = 0)]
        [string]
        $Text
    )

    # Save current VerbosePreference
    $VerbosePreferenceBefore = $VerbosePreference

    # Enable verbose output
    $VerbosePreference = 'Continue'

    # Write verbose output
    Write-Verbose "$( Get-Date -Format 'MM/dd/yyyy HH:mm:ss' ) - $( $Text )"

    # Restore current VerbosePreference
    $VerbosePreference = $VerbosePreferenceBefore
}

#endregion FUNCTIONS
#region EXECUTION
<# 
    Script entry point
#>

<# 
    Name query
#>

if (-not $Givenname) {
    $Givenname = Read-Host -Prompt 'Givenname of the trainee'
}
if (-not $Surname) {
    $Surname = Read-Host -Prompt 'Surname of the trainee'
}

<# 
    Read Data from INI file
#>

log 'Loading .\UserParameter.ini...'

# Get sensitive info from INI file
$RawString = Get-Content ".\UserParameters.ini" | Out-String

# The following line of code makes no sense at first glance 
# but it's only because the first '\\' is a regex pattern and the second isn't. )
$StringToConvert = $RawString -replace '\\', '\\'

# And now conversion works.
$ini = ConvertFrom-StringData $StringToConvert

$Accountpassword = ConvertTo-SecureString -String $ini.Accountpassword -AsPlainText -Force
$HomeDirectory = $ini.HomeDirectory
$ScriptPath = $ini.ScriptPath
$User = $ini.User
$Password = ConvertTo-SecureString -String $ini.Password -AsPlainText -Force

<# 
    Connect to Domain Controller
#>

$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password
$ComputerName = 'CV-SV-DCS-01'

<# 
    Set Initials
#>

log 'Reading AD users from domain controller to build unique initials...'

# Get all initials that need to be considered (only active users)
$UsersActive = Invoke-Command -ComputerName $ComputerName -Credential $cred -ScriptBlock { Get-ADUser -Filter 'enabled -eq $true' -Properties Initials }
$UsersPersonnel = $UsersActive.Where( { ( $_.Givenname -ne $null ) -and ( $_.Surname -ne $null ) } )
$UsersPersonnelNoInitials = $UsersPersonnel.Where( { $_.Initials -eq $null } )
$UsersPersonnelWithInitials = $UsersPersonnel.Where( { $_.Initials -ne $null } )
$InitialsAll = $UsersPersonnel.Initials

# Add letters from the surname to the initials such as that the initials become unique
$Initials = "$( $Givenname[0] )$( $Surname[0] )"
$i = 1

while ( $InitialsAll -contains $Initials ) {
    $i++
    $Initials = "$( $Givenname[0] )$( $Surname.Substring( 0, $i ) )"
}

<# 
    Create new user
#>

# Splatting all arguments for better readability
$Splat = @{
    Path = "OU=Office 365,OU=Anwender, OU=CV,DC=CENTER,DC=local"
    Name = "$( $Givenname ) $( $Surname )"
    Displayname = "$( $Givenname ) $( $Surname )  #  IT-Center Engels"
    GivenName = $Givenname
    Surname = $Surname
    Initials = $Initials
    UserPrincipalName = "$( $Initials )@itc-engels.de" # Benutzeranmeldename
    SamAccountName = $Initials # Benutzeranmeldename (Prä-Windows 2000)
    Accountpassword = ( ConvertTo-SecureString -AsPlainText -Force $Accountpassword )
    ChangePasswordAtLogon = $true
    Enabled = $true
    HomeDrive = "P"
    HomeDirectory = $HomeDirectory
    ScriptPath = $ScriptPath
    Company = "IT-Center Engels"
    Title = "Praktikant"
    AccountExpirationDate = ( Get-Date ).AddDays(14)
}

log 'Creating new AD user on domain controller...'

Invoke-Command -ComputerName $ComputerName -Credential $cred -ArgumentList $Splat -ScriptBlock {
    $SplatRemote = $Using:Splat

    New-ADUser @SplatRemote
}

<# 
    Sync to Azure
#>

log 'Starting AD sync on domain controller...'

Invoke-Command -ComputerName $ComputerName -Credential $cred -ScriptBlock {
    Import-Module "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync\ADSync.psd1"
    Start-ADSyncSyncCycle -PolicyType Delta
}

<# 
    Licensing in Azure
#>

Connect-AzureAD -TenantId "4b4a1eed-012a-4f33-b583-d62bac354bef" -ApplicationId "b5fd2bea-5822-4da8-852e-6a32abe0ae5b" -CertificateThumbprint "3D81C7F406DFC9423B330AD98CD1BBE0B1685429"

# Onboarding App:
# Connect-AzureAD -TenantId "4b4a1eed-012a-4f33-b583-d62bac354bef" -ApplicationId 'd1186226-581c-44e6-a96b-78d7b90cc8cf' -CertificateThumbprint "3D81C7F406DFC9423B330AD98CD1BBE0B1685429"

# Wait for synchronization
log 'Checking if Azure AD user exists...'

while ($null -eq ($AzureAdUser = Get-AzureAduser -SearchString "$( $Givenname ) $( $Surname )")) {
    Log 'Waiting 60 sec for sync...'
    Start-Sleep -Seconds 60
}

log 'Assigning license to Azure AD user...'

# SKUs for our subscribed licenses
$LicSku = @{
    'Office 365 E3'             = '05e9a617-0261-4cee-bb44-138d3ef5d965'
    'Microsoft 365 Business'    = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
}

$License = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$License.SkuId = $LicSku.'Office 365 E3'
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.AddLicenses = $License

Set-AzureADUser -ObjectId $AzureAdUser.ObjectId -UsageLocation 'DE'
Set-AzureADUserLicense -ObjectId $AzureAdUser.ObjectId -AssignedLicenses $Licenses

# Ggf. Aufwand abwägen wie Zeitaufwändig dies per Formular und Erfolgsrückmeldung in MS Teams oben drauf wäre

#endregion EXECUTION
