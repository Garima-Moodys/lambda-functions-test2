# Copyright (c) Microsoft. All rights reserved.

<#
.SYNOPSIS
Downloads the given $Version of vsdbg for the given $RuntimeID and installs it to the given $InstallPath

.DESCRIPTION
The following script will download vsdbg and install vsdbg, the .NET Core Debugger

.PARAMETER Version
Specifies the version of vsdbg to install. Can be 'latest', 'vs2022', 'vs2019', 'vs2017u5', 'vs2017u1', or a specific version string i.e. 15.0.25930.0

.PARAMETER RuntimeID
Specifies the .NET Runtime ID of the vsdbg that will be downloaded. Example: linux-x64. Defaults to win7-x64.

.Parameter InstallPath
Specifies the path where vsdbg will be installed. Defaults to the directory containing this script.

.INPUTS
None. You cannot pipe inputs to GetVsDbg.

.EXAMPLE
C:\PS> .\GetVsDbg.ps1 -Version latest -RuntimeID linux-x64 -InstallPath .\vsdbg

.LINK
For more information about using this script with Visual Studio Code see: https://github.com/OmniSharp/omnisharp-vscode/wiki/Attaching-to-remote-processes

For more information about using this script with Visual Studio see: https://github.com/Microsoft/MIEngine/wiki/Offroad-Debugging-of-.NET-Core-on-Linux---OSX-from-Visual-Studio

To report issues, see: https://github.com/omnisharp/omnisharp-vscode/issues
#>

Param (
    [Parameter(Mandatory=$true, ParameterSetName="ByName")]
    [string]
    [ValidateSet("latest", "vs2022", "vs2019", "vs2017u1", "vs2017u5")]
    $Version,

    [Parameter(Mandatory=$true, ParameterSetName="ByNumber")]
    [string]
    [ValidatePattern("\d+\.\d+\.\d+.*")]
    $VersionNumber,

    [Parameter(Mandatory=$false)]
    [string]
    $RuntimeID,

    [Parameter(Mandatory=$false)]
    [string]
    $InstallPath = (Split-Path -Path $MyInvocation.MyCommand.Definition)
)

$ErrorActionPreference="Stop"

# In a separate method to prevent locking zip files.
function DownloadAndExtract([string]$url, [string]$targetLocation) {
    Add-Type -assembly "System.IO.Compression.FileSystem"
    Add-Type -assembly "System.IO.Compression"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Try {
        $zipStream = (New-Object System.Net.WebClient).OpenRead($url)
    }
    Catch {
        Write-Host "Info: Opening stream failed, trying again with proxy settings."
        $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $webClient = New-Object System.Net.WebClient
        $webClient.UseDefaultCredentials = $false
        $webClient.proxy = $proxy

        $zipStream = $webClient.OpenRead($url)
    }
    
    $zipArchive = New-Object System.IO.Compression.ZipArchive -ArgumentList $zipStream
    [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($zipArchive, $targetLocation)
    $zipArchive.Dispose()
    $zipStream.Dispose()
}

# Checks if the existing version is the latest version.
function IsLatest([string]$installationPath, [string]$runtimeId, [string]$version) {
    $SuccessRidFile = Join-Path -Path $installationPath -ChildPath "success_rid.txt"
    if (Test-Path $SuccessRidFile) {
        $LastRid = Get-Content -Path $SuccessRidFile
        if ($LastRid -ne $runtimeId) {
            return $false
        }
    } else {
        return $false
    }

    $SuccessVersionFile = Join-Path -Path $installationPath -ChildPath "success_version.txt"
    if (Test-Path $SuccessVersionFile) {
        $LastVersion = Get-Content -Path $SuccessVersionFile
        if ($LastVersion -ne $version) {
            return $false
        }
    } else {
        return $false
    }

    return $true
}

function WriteSuccessInfo([string]$installationPath, [string]$runtimeId, [string]$version) {
    $SuccessRidFile = Join-Path -Path $installationPath -ChildPath "success_rid.txt"
    $runtimeId | Out-File -Encoding ascii $SuccessRidFile

    $SuccessVersionFile = Join-Path -Path $installationPath -ChildPath "success_version.txt"
    $version | Out-File -Encoding ascii $SuccessVersionFile
}

$ExplitVersionNumberUsed = $false
if ($Version -eq "latest") {
    $VersionNumber = "17.13.20213.2"
} elseif ($Version -eq "vs2022") {
    $VersionNumber = "17.13.20213.2"
} elseif ($Version -eq "vs2019") {
    $VersionNumber = "17.13.20213.2"
} elseif ($Version -eq "vs2017u5") {
    $VersionNumber = "17.13.20213.2"
} elseif ($Version -eq "vs2017u1") {
    $VersionNumber = "15.1.10630.1"
} else {
    $ExplitVersionNumberUsed = $true
}
Write-Host "Info: Using vsdbg version '$VersionNumber'"

if (-not $RuntimeID) {
    $RuntimeID = "win7-x64"
} elseif (-not $ExplitVersionNumberUsed) {
    $legacyLinuxRuntimeIds = @{ 
        "debian.8-x64" = "";
        "rhel.7.2-x64" = "";
        "centos.7-x64" = "";
        "fedora.23-x64" = "";
        "opensuse.13.2-x64" = "";
        "ubuntu.14.04-x64" = "";
        "ubuntu.16.04-x64" = "";
        "ubuntu.16.10-x64" = "";
        "fedora.24-x64" = "";
        "opensuse.42.1-x64" = "";
    }

    # Remap the old distro-specific runtime ids unless the caller specified an exact build number.
    # We don't do this in the exact build number case so that old builds can be used.
    if ($legacyLinuxRuntimeIds.ContainsKey($RuntimeID.ToLowerInvariant())) {
        $RuntimeID = "linux-x64"
    }
}
Write-Host "Info: Using Runtime ID '$RuntimeID'"

# if we were given a relative path, assume its relative to the script directory and create an absolute path
if (-not([System.IO.Path]::IsPathRooted($InstallPath))) {
    $InstallPath = Join-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Definition) -ChildPath $InstallPath
}

if (IsLatest $InstallPath $RuntimeID $VersionNumber) {
    Write-Host "Info: Latest version of VsDbg is present. Skipping downloads"
} else {
    if (Test-Path $InstallPath) {
        Write-Host "Info: $InstallPath exists, deleting."
        Remove-Item $InstallPath -Force -Recurse -ErrorAction Stop
    }
 
    $target = ("vsdbg-" + $VersionNumber).Replace('.','-') + "/vsdbg-" + $RuntimeID + ".zip"
    $url = "https://vsdebugger-cyg0dxb6czfafzaz.b01.azurefd.net/" + $target

    DownloadAndExtract $url $InstallPath

    WriteSuccessInfo $InstallPath $RuntimeID $VersionNumber
    Write-Host "Info: Successfully installed vsdbg at '$InstallPath'"
}

# SIG # Begin signature block
# MIImNwYJKoZIhvcNAQcCoIImKDCCJiQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA50gn5atQ+vXkv
# Irx1+HPWhyaVzvVMejDyamHuPkGj9KCCC2cwggTvMIID16ADAgECAhMzAAAFp7iP
# +5ddNYTsAAAAAAWnMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTAwHhcNMjQwODIyMTkyNTU3WhcNMjUwNzA1MTkyNTU3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCWGlTKjYt60rB8oNyPWJUGQV2NGwlRXKJg3484q2nJiv9+Frz96fGoXlblIeJ3
# xqQxEoCEDYjjbYClgx31MZcoRqJD0sKjNtYDKA0NiSdOJQut3+HN0rSx74yqobDB
# P8AKAyWANZitUQHnPH1EkTXMdRlnJnD1RtFljMYOJnrxfqrAdtNNxU1pIYYmY6oD
# 8dye81i9RHxSJGEgfMnEIpn/1ySkikTV+NOHFj1QH7+SHZWYNcdgL48QSa1jC30A
# i6MKLh91FOsCsuNU0cTC6z6QkP51l9dU8B+xnvZa2/WzvJhByZnjXS+tVeN2KB5E
# p0seOtuFwvI6KoOXrETKCDg7AgMBAAGjggFuMIIBajAfBgNVHSUEGDAWBgorBgEE
# AYI3PQYBBggrBgEFBQcDAzAdBgNVHQ4EFgQUUhW6zVNwhzmLbscozYppwd8fKxIw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwODY1KzUwMjcwMzAfBgNVHSMEGDAWgBTm/F97uyIAWORyTrX0
# IXQjMubvrDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpL2NybC9wcm9kdWN0cy9NaWNDb2RTaWdQQ0FfMjAxMC0wNy0wNi5jcmww
# WgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpL2NlcnRzL01pY0NvZFNpZ1BDQV8yMDEwLTA3LTA2LmNydDAMBgNV
# HRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IBAQAl1cQIQ+FD/ubaWIiMg8wQtEx3
# SksQ5r6qAgferOe6TZ5bmTcMj2VUkHLrvmhScoRe9pQ/CqwZ676YuM90tiqPrMDj
# XO8kLCA+kTeDZoKQL0MI2ShbDhXrDIsui9hGNhd8PwGTWQksnoO4HxqGG2Mfiqsn
# OgMo9HimmTF2/H1XLc/g2TPpF8GyXAco7khch4l1hIIpmVEZN6ZFCk2/kOf7m2sC
# l8h5+BWQDmSaECtI2xc5SLbqot1isWvFiERtaw9xQb31MWYas2l2/XdcbH7QFYpK
# pG4dDZhKIdlRVmYpUyRaNOZWNwNc7G6bzKIC3HAGFOIEc4aDQu2yT/q0yJ7WMIIG
# cDCCBFigAwIBAgIKYQxSTAAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0
# IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzA2MjA0MDE3
# WhcNMjUwNzA2MjA1MDE3WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDEw
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6Q5kUHlntcTj/QkATJ6U
# rPdWaOpE2M/FWE+ppXZ8bUW60zmStKQe+fllguQX0o/9RJwI6GWTzixVhL99COMu
# K6hBKxi3oktuSUxrFQfe0dLCiR5xlM21f0u0rwjYzIjWaxeUOpPOJj/s5v40mFfV
# HV1J9rIqLtWFu1k/+JC0K4N0yiuzO0bj8EZJwRdmVMkcvR3EVWJXcvhnuSUgNN5d
# pqWVXqsogM3Vsp7lA7Vj07IUyMHIiiYKWX8H7P8O7YASNUwSpr5SW/Wm2uCLC0h3
# 1oVH1RC5xuiq7otqLQVcYMa0KlucIxxfReMaFB5vN8sZM4BqiU2jamZjeJPVMM+V
# HwIDAQABo4IB4zCCAd8wEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFOb8X3u7
# IgBY5HJOtfQhdCMy5u+sMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjR
# PZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNy
# bDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGd
# BgNVHSAEgZUwgZIwgY8GCSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggr
# BgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQA
# ZQBtAGUAbgB0AC4gHTANBgkqhkiG9w0BAQsFAAOCAgEAGnTvV08pe8QWhXi4UNMi
# /AmdrIKX+DT/KiyXlRLl5L/Pv5PI4zSp24G43B4AvtI1b6/lf3mVd+UC1PHr2M1O
# HhthosJaIxrwjKhiUUVnCOM/PB6T+DCFF8g5QKbXDrMhKeWloWmMIpPMdJjnoUdD
# 8lOswA8waX/+0iUgbW9h098H1dlyACxphnY9UdumOUjJN2FtB91TGcun1mHCv+KD
# qw/ga5uV1n0oUbCJSlGkmmzItx9KGg5pqdfcwX7RSXCqtq27ckdjF/qm1qKmhuyo
# EESbY7ayaYkGx0aGehg/6MUdIdV7+QIjLcVBy78dTMgW77Gcf/wiS0mKbhXjpn92
# W9FTeZGFndXS2z1zNfM8rlSyUkdqwKoTldKOEdqZZ14yjPs3hdHcdYWch8ZaV4XC
# v90Nj4ybLeu07s8n07VeafqkFgQBpyRnc89NT7beBVaXevfpUk30dwVPhcbYC/GO
# 7UIJ0Q124yNWeCImNr7KsYxuqh3khdpHM2KPpMmRM19xHkCvmGXJIuhCISWKHC1g
# 2TeJQYkqFg/XYTyUaGBS79ZHmaCAQO4VgXc+nOBTGBpQHTiVmx5mMxMnORd4hzbO
# TsNfsvU9R1O24OXbC2E9KteSLM43Wj5AQjGkHxAIwlacvyRdUQKdannSF9PawZSO
# B3slcUSrBmrm1MbfI5qWdcUxghomMIIaIgIBATCBlTB+MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBT
# aWduaW5nIFBDQSAyMDEwAhMzAAAFp7iP+5ddNYTsAAAAAAWnMA0GCWCGSAFlAwQC
# AQUAoIGuMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsx
# DjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBHX745jmYTSHtrHZod4jB/
# UC2QfCN0kDByjKkY8eLGPTBCBgorBgEEAYI3AgEMMTQwMqAUgBIATQBpAGMAcgBv
# AHMAbwBmAHShGoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEB
# AQUABIIBAD76F7geMlzm0u9wRWzpor6ZpjvHbR8qwSh0jHzZzATUHYMWPc/4pBUX
# Do6j+leS9aPNzf759AFqOtc6BDsSWZeXtaHhjYnjddOEw6wKWdA5UETo1rdgqP1Y
# 77HGq3lErEK3pwhD0n+dPbzXZ+TWSMSClaSnO19HrRkCb1E32t4O5uoeMpTVR3Za
# oAsy6Lho/JueKHwd9ZKM5yA9+BSKBqxiQ6w4tTL3nvAH3EtLLx0sz3QqDmtIFgHq
# elTCu9mzvAYos67rXI7w/3G4eKe+ek4Ajbk7sSWr84mkRrbsza52bkTsGIS4NHJn
# E6CbeCBx/nPVTJ/LvG8Cz/2Hzyj6qCahghewMIIXrAYKKwYBBAGCNwMDATGCF5ww
# gheYBgkqhkiG9w0BBwKggheJMIIXhQIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBWgYL
# KoZIhvcNAQkQAQSgggFJBIIBRTCCAUECAQEGCisGAQQBhFkKAwEwMTANBglghkgB
# ZQMEAgEFAAQg/MJMM0JmGOQq+9fPSld2pCxq9wd2D0tm9r+PSz7fRt4CBmeaqRJH
# URgTMjAyNTAyMTMyMTUyMzcuODY1WjAEgAIB9KCB2aSB1jCB0zELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IEly
# ZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBF
# U046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WgghH+MIIHKDCCBRCgAwIBAgITMwAAAf7QqMJ7NCELAQABAAAB/jAN
# BgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0y
# NDA3MjUxODMxMThaFw0yNTEwMjIxODMxMThaMIHTMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBP
# cGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MDFB
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALy8IRcVpagON6JbBODw
# noGeJkn7B9mE0ihGL/Bp99+tgZmsnHX+U97UMaT9zVputmB1IniEF8PtLuKpWsuA
# DdyKJyPuOzaYvX6OdsXQFzF9KRq3NHqlvEVjd2381zyr9OztfIth4w8i7ssGMigP
# RZlm3j42oX/TMHfEIMoJD7cA61UBi8jpMjN1U4hyqoRrvQQhlUXR1vZZjzK61JT1
# omFfS1QgeVWHfgBFLXX6gHapc1cQOdxIMUqoaeiW3xCp03XHz+k/DIq9B68E07Vd
# odsgwbY120CGqsnCjm+t9xn0ZJ9teizgwYN+z/8cIaHV0/NWQtmhze3sRA5pm4lr
# LIxrxSZJYtoOnbdNXkoTohpoW6J69Kl13AXqjW+kKBfI1/7g1bWPaby+I/GhFkuP
# YSlB9Js7ArnCK8FEvsfDLk9Ln+1VwhTRW4glDUU6H8SdweOeHhiYS9H8FE0W4Mgm
# 6S4CjCg4gkbm+uQ4Wng71AACU/dykgqHhQqJJT2r24EMmoRmQy/71gFY1+W/Cc4Z
# cvYBgnSv6ouovnMWdEvMegdsoz22X3QVXx/zQaf9S5+8W3jhEwDp+zk/Q91BrdKv
# ioloGONh5y48oZdWwLuR34K8gDtwwmiHVdrY75CWstqjpxew4I/GutCkE/UIHyX8
# F5692Som2DI2lGwjSA58c9spAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUb857ifUl
# NoOZf+f2/uQgYm2xxd0wHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAIk+DVLztpcP
# tHQzLbAbsZl9qN5VUKp0JLiEwBiBgoCPrJe2amTkw3fC6sbB+Blgj087XN7a/AIA
# b7GCM1oxcIqAowkDg6taATFjcxLCs3JB8QM2KOUs3uzj5DANwwMVauEkkfMvk0Qt
# hnDndCUXmdZT5YZT5fVyPs/DoLTj5kJyy4j/as6Ux8Bc3vrG6kp/HHpHbjGXS8hy
# ZNzYsNwJ4JVP1k8xrEAHXIfUlVeCx4n1J5sE39ItO4irU5TZKt28dYsloOze4xmQ
# AUVk9pl/mAFR5Stu7fZ/lrWG5+nDiTV+i7B/MT1QUWACEVZFrDMhAHaD/Xan2mc8
# Fxpo7lUPd9TYcx44xvhH8NdfA145N1at6lCNa3t+MzDE0c2WRMPNhbqRd74lzUdw
# 1TpUvSR+MeXpnyDWtbrkmnOheAniQg9RmpH0uw+WsjbGmdnvrAVIetilU5YRLEER
# 2UcAk8W4sdWOIicPjwzS3NB39fal9l4l9LtkjPQlk047M/UrwoyCksQmRQjb/86S
# iJbB8e4UDUB0jGyodP8MJ/OroiACxI2s1LMxNPl+q3Dmw31OIfzv9L5mxdwTEfuO
# awGTABEybEQz8RyQqP+VxoVnYPy6CeV1gazgy+OGDazexUZxxAAK9OrH5amfHnld
# xbgynT+YdfVlJxlsDtR/2Y1MzqFRold4MIIHcTCCBVmgAwIBAgITMwAAABXF52ue
# AptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgz
# MjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxO
# dcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQ
# GOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq
# /XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVW
# Te/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7
# mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De
# +JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM
# 9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEz
# OUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2
# ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqv
# UAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q
# 4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcV
# AgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXS
# ZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaA
# FNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8y
# MDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8
# qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7p
# Zmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2C
# DPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BA
# ljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJ
# eBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1
# MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz
# 138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1
# V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLB
# gqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0l
# lOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFx
# BmoQtB1VM1izoXBm8qGCA1kwggJBAgEBMIIBAaGB2aSB1jCB0zELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IEly
# ZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBF
# U046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAIRjRw/2u0NG0C1lRvSbhsYC0V7HoIGD
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEL
# BQACBQDrWEQWMCIYDzIwMjUwMjEzMTAxMjM4WhgPMjAyNTAyMTQxMDEyMzhaMHcw
# PQYKKwYBBAGEWQoEATEvMC0wCgIFAOtYRBYCAQAwCgIBAAICBR8CAf8wBwIBAAIC
# EmAwCgIFAOtZlZYCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAK
# MAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAC4LvWGnY
# R6aCjBWLwa9SnqqUQWywaxt1BMvOvDpoNYdMg3fAliD91jFOE211iMA6B6XG2mrq
# zkxOx/w3/PPxZ+bziBLuXghKwWOclp8gs8JD39xH1EWBdq2PwF2GsdZVPNA3YtDv
# TF/Y0CO2Pyp4rV8y0ntsUjJhYE7Ie60WjShyWBszrukqIX0qqTttFun7yuQfHZR0
# utotCy3LhM8dJ+dVPv7KrMzVI5+eoijAlwIR5JR3ctl7o0drd18K+SVowp5GM7zl
# UqLQ0sGld3Ik01e/Z8u5UdhlYckFsfHWD/QzhC22hEFd+UNGEV4V/R8lwC+kD/qc
# LpMRO0FJa8Oa7DGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAAB/tCowns0IQsBAAEAAAH+MA0GCWCGSAFlAwQCAQUAoIIBSjAa
# BgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIHQQ5q9G
# Jbg8H+J2eVgtNyzuF4H+dXPPMKgThpHZoxJKMIH6BgsqhkiG9w0BCRACLzGB6jCB
# 5zCB5DCBvQQgEYXM3fxTyJ8Y0fdptoT1qnPrxjhtfvyNFrZArLcodHkwgZgwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAf7QqMJ7NCELAQAB
# AAAB/jAiBCDGaFk4sqO86Yw4b5a6x2eb+xS7X5/YV5XKKmXPuc93vDANBgkqhkiG
# 9w0BAQsFAASCAgC21kdl2Qd0aFz8MbB+5Ckhs3NU/bYSkdNssIt5ucJL7DkrUovC
# RB02EFIhHqG00sR85ORtBVBGREVZYYxafohPH6lHyaP1MWQZmnoXHN1LXYD35n3k
# kyRsQqoFsShybgr/2PcG4ALnUEpem1WGsmYCCLjwZ0veLdCzt2D00hYFPckApMkC
# gvqq8ZKwVIQcCZjZL02/DbokqCQKXotYzRvmYqBQ0WbxI+pSWnbCSsTWqTavFjvF
# yy0Zm/CTZ8i5njUavLQKuhN4ef1x8ryyET+phfqP5xZtAMm7juYgUWIIuUbxSnSH
# L05hBxGlMRAKbH17BJ8yJ4Dz2q1h7l2qpnBXa0pgi6qmHdoUewph2NL1YnbQIBnw
# RhtS7E+Zr2tVRfYg/mMDeUeifopqWIVk4TLc1ugLPCie+jv9oCwvKWsv1Ru8pHH9
# fyXP/w4qBy/D6eBP6gFEJbF6VmDnbgCMbpQqmDUg2ngtAscApBz1xSrHK+cXabVs
# 7Rx0JDZZXFaA44HtI5VDejkNnREPnPrFaPaXjdahUMTqPKq3kSAyfjkf0TI0W2eZ
# 3ZKbta527ZUFi7uLrxVdTVAlzyrduAxGAFgt38QfJQP309O4+gTyiVjM9rMctr+d
# 53AwDguvzX1Os09OPM0C1Fbl54zGcJaJDesLzijqP1TZPKY9QaUYKv8oig==
# SIG # End signature block
