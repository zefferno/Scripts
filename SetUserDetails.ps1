# ------------------------------------------------------------------------------
# AUTHOR: Mor Kalfon
#
# CREATED: 28-02-2016
#
# UPDATED: 28-02-2016
#
# DESCRIPTION:
#
# This script updates list of Active Directory users properites from a given 
# Comma Seperated Values (CSV) file.
# ------------------------------------------------------------------------------

Param (
    [Parameter(Mandatory=$True)]
    [string]$csvFile,
    [Parameter(Mandatory=$True)]
    [string]$domainSearchBase,
    [switch]$details
)

Import-Module ActiveDirectory

$notExist = New-Object System.Collections.ArrayList

function Write-Line {
    for($i=0; $i -le 80; $i++) { Write-Host "-" -NoNewline }
    Write-Host
}

Write-Host "Script is processing..."
Write-Line

# Load the file to CSV object
$csv = Import-Csv -Path $csvFile

# Iterate users and update the attributes in AD
foreach ($c in $csv) {
    # Get the AD user object      
    $user = Get-ADUser -Filter "SamAccountName -eq '$($c.SamAccountName)'" -Properties * -SearchBase "DC=my,DC=local,dc=domain"
    if ($user) {
        if ($verbose) { Write-Host "Username: $($c.SamAccountName)" }
        # Set user properties
        $user.Company = $c.Company
        $user.HomePhone = $c.HomePhone
        $user.Mobile = $c.Mobile
        # Write changes
        Set-ADUser -instance $user
    } else {
        if ($verbose) { Write-Host "ERROR: $($c.SamAccountName) does not exists." -ForegroundColor Red }
        [void]$notExist.Add($($c.SamAccountName))
    }
}

Write-Line
    
if ($notExist.Count -gt 0) {
    Write-Host "Script error!"
    Write-Host "FAILURE: Unable to update the following users:"
    foreach ($user in $notExist) {
        Write-Host $user
    }
} else {
    Write-Host "Script completed sucessfully."
}
