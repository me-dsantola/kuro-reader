[CmdletBinding()]
param(
    [string]$Repository = 'me-dsantola/kuro-reader',
    [string]$KeystorePath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'YOMI\signing\yomi-release.jks'),
    [string]$KeyAlias = 'yomi'
)

$ErrorActionPreference = 'Stop'
$PreviousOutputEncoding = $OutputEncoding
$PreviousSigningPassword = $env:YOMI_SETUP_PASSWORD
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw 'Java 17 ou superior ausente. Instale com: winget install EclipseAdoptium.Temurin.17.JDK. Depois reabra o terminal.'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI ausente. Instale com: winget install GitHub.cli. Depois reabra o terminal e execute gh auth login.'
}
$Account = (& gh api user --jq .login 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Entre no GitHub CLI primeiro: gh auth login' }
$Owner = $Repository.Split('/')[0]
if ($Account.Trim() -ne $Owner) { throw "A conta conectada ($Account) precisa ser a proprietaria do repositorio $Repository." }
if ($Repository -ne 'me-dsantola/kuro-reader') { throw 'Este assistente foi preparado exclusivamente para me-dsantola/kuro-reader.' }

Write-Host "Destino: $Repository"
Write-Host "Chave local: $KeystorePath"
Write-Host 'Guarde o arquivo e a senha em um backup privado. A mesma chave sera necessaria para todas as futuras atualizacoes.'
$Password = Read-Host 'Crie/digite a senha do keystore (pelo menos 12 caracteres)' -AsSecureString
$Confirm = Read-Host 'Confirme a senha' -AsSecureString
$PlainPassword = [System.Net.NetworkCredential]::new('', $Password).Password
$PlainConfirm = [System.Net.NetworkCredential]::new('', $Confirm).Password
if ($PlainPassword.Length -lt 12 -or $PlainPassword -ne $PlainConfirm) {
    throw 'As senhas precisam coincidir e ter pelo menos 12 caracteres.'
}

function Set-YomiSecret([string]$Name, [string]$Value) {
    $Value | & gh secret set $Name --repo $Repository
    if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel configurar $Name. Nenhum valor sera exibido." }
}

try {
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $env:YOMI_SETUP_PASSWORD = $PlainPassword
    $Parent = Split-Path -Parent $KeystorePath
    [System.IO.Directory]::CreateDirectory($Parent) | Out-Null
    if (-not (Test-Path -LiteralPath $KeystorePath)) {
        & keytool -genkeypair -storetype JKS -keyalg RSA -keysize 4096 -sigalg SHA256withRSA `
            -validity 10000 -alias $KeyAlias -keystore $KeystorePath `
            -storepass:env YOMI_SETUP_PASSWORD -keypass:env YOMI_SETUP_PASSWORD `
            -dname 'CN=YOMI Release' -noprompt
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar a chave. Nenhum segredo foi enviado.' }
    } else {
        Write-Host 'Arquivo existente encontrado: ele sera reutilizado, nunca substituido.'
    }
    & keytool -list -alias $KeyAlias -keystore $KeystorePath -storepass:env YOMI_SETUP_PASSWORD *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Arquivo, alias ou senha invalidos. A chave existente foi preservada.' }
    $CheckFile = [System.IO.Path]::GetTempFileName()
    try {
        & keytool -certreq -alias $KeyAlias -keystore $KeystorePath -storepass:env YOMI_SETUP_PASSWORD `
            -keypass:env YOMI_SETUP_PASSWORD -file $CheckFile *> $null
        if ($LASTEXITCODE -ne 0) { throw 'A senha da chave privada precisa corresponder a senha informada. Nenhum segredo foi enviado.' }
    } finally { Remove-Item -LiteralPath $CheckFile -ErrorAction SilentlyContinue }
    $Encoded = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($KeystorePath))
    Set-YomiSecret 'YOMI_KEYSTORE_BASE64' $Encoded
    Set-YomiSecret 'YOMI_STORE_PASSWORD' $PlainPassword
    Set-YomiSecret 'YOMI_KEY_ALIAS' $KeyAlias
    Set-YomiSecret 'YOMI_KEY_PASSWORD' $PlainPassword
    Write-Host 'Quatro segredos configurados. Nenhum valor foi impresso.'
    Write-Host "Guarde uma copia privada de $KeystorePath e da senha. Nao envie o arquivo para o repositorio ou pelo chat."
    Write-Host 'Volte ao chat e informe apenas: os segredos foram configurados.'
} finally {
    if ($null -eq $PreviousSigningPassword) { Remove-Item Env:YOMI_SETUP_PASSWORD -ErrorAction SilentlyContinue }
    else { $env:YOMI_SETUP_PASSWORD = $PreviousSigningPassword }
    $OutputEncoding = $PreviousOutputEncoding
    $PlainPassword = $null
    $PlainConfirm = $null
    $Encoded = $null
    if ($Password) { $Password.Dispose() }
    if ($Confirm) { $Confirm.Dispose() }
}
