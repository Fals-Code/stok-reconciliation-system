[CmdletBinding()]
param(
    [string] $ProjectRoot = "D:\proyek\sistem_rekonsiliasi_stok",
    [string] $BaseUrl = "http://localhost:3000",
    [string] $Email = "demo.admin@glowlab.invalid",
    [switch] $Headed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $ProjectRoot

$previousBaseUrl = $env:PLAYWRIGHT_BASE_URL
$previousEmail = $env:PLAYWRIGHT_ADMIN_EMAIL
$previousPassword = $env:PLAYWRIGHT_ADMIN_PASSWORD

$securePassword = $null
$passwordPointer = [IntPtr]::Zero

try {
    $env:PLAYWRIGHT_BASE_URL = $BaseUrl
    $env:PLAYWRIGHT_ADMIN_EMAIL = $Email

    if (
        [string]::IsNullOrWhiteSpace(
            $env:PLAYWRIGHT_ADMIN_PASSWORD
        )
    ) {
        $securePassword = Read-Host `
            "Password akun Admin demo lokal" `
            -AsSecureString

        $passwordPointer = `
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
                $securePassword
            )

        $env:PLAYWRIGHT_ADMIN_PASSWORD = `
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                $passwordPointer
            )
    }

    if (
        [string]::IsNullOrWhiteSpace(
            $env:PLAYWRIGHT_ADMIN_PASSWORD
        )
    ) {
        throw "Password Playwright belum tersedia."
    }

    $arguments = @(
        "playwright",
        "test",
        "tests/e2e/admin-shell.spec.ts",
        "--project=desktop-chromium",
        "--project=mobile-chromium"
    )

    if ($Headed) {
        $arguments += "--headed"
    }

    & npx @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Playwright gagal dengan exit code $LASTEXITCODE."
    }
}
finally {
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $passwordPointer
        )
    }

    if ($null -eq $previousBaseUrl) {
        Remove-Item `
            Env:PLAYWRIGHT_BASE_URL `
            -ErrorAction SilentlyContinue
    }
    else {
        $env:PLAYWRIGHT_BASE_URL = $previousBaseUrl
    }

    if ($null -eq $previousEmail) {
        Remove-Item `
            Env:PLAYWRIGHT_ADMIN_EMAIL `
            -ErrorAction SilentlyContinue
    }
    else {
        $env:PLAYWRIGHT_ADMIN_EMAIL = $previousEmail
    }

    if ($null -eq $previousPassword) {
        Remove-Item `
            Env:PLAYWRIGHT_ADMIN_PASSWORD `
            -ErrorAction SilentlyContinue
    }
    else {
        $env:PLAYWRIGHT_ADMIN_PASSWORD = $previousPassword
    }

    Remove-Variable `
        securePassword, `
        passwordPointer, `
        previousBaseUrl, `
        previousEmail, `
        previousPassword `
        -ErrorAction SilentlyContinue
}