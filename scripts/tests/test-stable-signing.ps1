$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) {
    throw 'Run this regression with Windows PowerShell 5.1.'
}

$TestFolder = Join-Path ([IO.Path]::GetTempPath()) ('yomi-signing-test-' + [Guid]::NewGuid().ToString('N'))
$TestKey = Join-Path $TestFolder 'folder with spaces\test-release.jks'
$SetupScript = Join-Path $PSScriptRoot '..\setup-stable-signing.ps1'
$PreviousTestPassword = $env:YOMI_SETUP_PASSWORD
$PreviousTestEncoding = $OutputEncoding
$SigningTestState = @{
    Password = ('Only-for-this-test-' + [Guid]::NewGuid().ToString('N'))
    Secrets = @{}
    FailSecret = $null
}

# These mocks stay in the test script's scope. No GitHub request is made and
# no test key is ever configured as a production repository secret.
function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    if (-not $AsSecureString) { throw 'Password input must stay masked.' }
    ConvertTo-SecureString $SigningTestState.Password -AsPlainText -Force
}

function gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'api' -and $args[1] -eq 'user') {
        return 'me-dsantola'
    }
    if ($args[0] -eq 'secret' -and $args[1] -eq 'set') {
        $SecretName = [string]$args[2]
        if ($SecretName -eq $SigningTestState.FailSecret) {
            $global:LASTEXITCODE = 1
            return
        }
        $SigningTestState.Secrets[$SecretName] = (@($input) -join '')
        return
    }
    throw 'Unexpected GitHub operation in signing test.'
}

function Assert-YomiTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    & $SetupScript -KeystorePath $TestKey
    Assert-YomiTest (Test-Path -LiteralPath $TestKey) 'A new keystore must be created.'
    Assert-YomiTest ($SigningTestState.Secrets.Count -eq 4) 'All four secrets must be sent.'
    Assert-YomiTest ($SigningTestState.Secrets['YOMI_KEY_ALIAS'] -eq 'yomi') 'Alias mismatch.'
    Assert-YomiTest ($SigningTestState.Secrets['YOMI_STORE_PASSWORD'] -eq $SigningTestState.Password) 'Store password mismatch.'
    Assert-YomiTest ($SigningTestState.Secrets['YOMI_KEY_PASSWORD'] -eq $SigningTestState.Password) 'Key password mismatch.'
    $UploadedKey = [Convert]::FromBase64String($SigningTestState.Secrets['YOMI_KEYSTORE_BASE64'])
    Assert-YomiTest ([Convert]::ToBase64String($UploadedKey) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($TestKey))) 'Uploaded key differs from local key.'
    Assert-YomiTest ($ErrorActionPreference -eq 'Stop') 'Native error handling must not change the caller preference.'
    Assert-YomiTest ($env:YOMI_SETUP_PASSWORD -eq $PreviousTestPassword) 'Temporary password environment was not restored.'
    Assert-YomiTest ($OutputEncoding -eq $PreviousTestEncoding) 'Console encoding was not restored.'
    Write-Host 'PASS: JKS creation and verification tolerate Java warnings under PowerShell 5.1.'

    $OriginalHash = (Get-FileHash -LiteralPath $TestKey -Algorithm SHA256).Hash
    $SigningTestState.Secrets.Clear()
    & $SetupScript -KeystorePath $TestKey
    Assert-YomiTest ($SigningTestState.Secrets.Count -eq 4) 'Retry must configure all four secrets.'
    Assert-YomiTest ((Get-FileHash -LiteralPath $TestKey -Algorithm SHA256).Hash -eq $OriginalHash) 'Retry must never replace the existing key.'
    Write-Host 'PASS: retry reuses the exact existing keystore.'

    $SigningTestState.Secrets.Clear()
    $SigningTestState.Password = 'Wrong-password-for-this-test-only'
    $Rejected = $false
    try { & $SetupScript -KeystorePath $TestKey } catch { $Rejected = $true }
    Assert-YomiTest $Rejected 'A real keytool failure must stop the assistant.'
    Assert-YomiTest ($SigningTestState.Secrets.Count -eq 0) 'A failed key check must not upload secrets.'
    Assert-YomiTest ((Get-FileHash -LiteralPath $TestKey -Algorithm SHA256).Hash -eq $OriginalHash) 'A failed check must preserve the key.'
    Assert-YomiTest ($env:YOMI_SETUP_PASSWORD -eq $PreviousTestPassword) 'Failure must restore the environment.'
    Write-Host 'PASS: invalid password remains an error and no secrets are uploaded.'
} finally {
    if ($null -eq $PreviousTestPassword) { Remove-Item Env:YOMI_SETUP_PASSWORD -ErrorAction SilentlyContinue }
    else { $env:YOMI_SETUP_PASSWORD = $PreviousTestPassword }
    $OutputEncoding = $PreviousTestEncoding
    if (Test-Path -LiteralPath $TestFolder) { Remove-Item -LiteralPath $TestFolder -Recurse -Force }
    $SigningTestState.Clear()
    $UploadedKey = $null
}
# The deliberately rejected password left keytool's exit code nonzero.
# Reaching this line means every assertion passed; unexpected failures throw.
$global:LASTEXITCODE = 0
