[CmdletBinding()]
param(
    [string] $ProjectRoot = "D:\proyek\sistem_rekonsiliasi_stok",
    [string] $BaseUrl = "http://localhost:3000",
    [string] $Email = "demo.admin@glowlab.invalid",
    [SecureString] $Password,
    [switch] $KeepServer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
$script:StartedServer = $false
$script:ServerProcess = $null
$script:PlainPassword = $null
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "FAIL", "SKIP")]
        [string] $Status,

        [string] $Detail = ""
    )

    switch ($Status) {
        "PASS" { $script:PassCount += 1 }
        "FAIL" { $script:FailCount += 1 }
        "SKIP" { $script:SkipCount += 1 }
    }

    $script:Results.Add(
        [pscustomobject]@{
            Test   = $Name
            Status = $Status
            Detail = $Detail
        }
    )

    $prefix = "[{0}]" -f $Status
    Write-Host ("{0,-8} {1}" -f $prefix, $Name)

    if ($Detail) {
        Write-Host ("         {0}" -f $Detail)
    }
}

function Invoke-SmokeTest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Test
    )

    try {
        $detail = & $Test

        if ($null -eq $detail) {
            $detail = ""
        }

        Add-Result -Name $Name -Status "PASS" -Detail ([string] $detail)
    } catch {
        Add-Result -Name $Name -Status "FAIL" -Detail $_.Exception.Message
    }
}

function Read-EnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Environment file not found: $Path"
    }

    $map = @{}

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()

        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $separator = $line.IndexOf("=")

        if ($separator -lt 1) {
            continue
        }

        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $map[$name] = $value
    }

    return $map
}

function Get-PlainTextPassword {
    param(
        [Parameter(Mandatory = $true)]
        [SecureString] $SecurePassword
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecurePassword
    )

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Test-ServerReady {
    try {
        Invoke-WebRequest `
            -Uri "$BaseUrl/login" `
            -UseBasicParsing `
            -TimeoutSec 3 |
            Out-Null

        return $true
    } catch {
        return $false
    }
}

function Get-FinalUri {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if (
        $Response.BaseResponse -and
        $Response.BaseResponse.PSObject.Properties.Name -contains "ResponseUri"
    ) {
        return $Response.BaseResponse.ResponseUri
    }

    if (
        $Response.BaseResponse -and
        $Response.BaseResponse.RequestMessage -and
        $Response.BaseResponse.RequestMessage.RequestUri
    ) {
        return $Response.BaseResponse.RequestMessage.RequestUri
    }

    return [uri]$Response.BaseResponse
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [string] $Expected,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Text.Contains($Expected)) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [string] $Unexpected,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if ($Text.Contains($Unexpected)) {
        throw $Message
    }
}

function Get-AppPage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Microsoft.PowerShell.Commands.WebRequestSession] $Session
    )

    $parameters = @{
        Uri             = "$BaseUrl$Path"
        UseBasicParsing = $true
        TimeoutSec      = 30
    }

    if ($Session) {
        $parameters.WebSession = $Session
    }

    return Invoke-WebRequest @parameters
}

try {
    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "Project directory not found: $ProjectRoot"
    }

    Set-Location $ProjectRoot

    Write-Host ""
    Write-Host "Admin Shell PowerShell Smoke Test"
    Write-Host "Project : $ProjectRoot"
    Write-Host "Base URL: $BaseUrl"
    Write-Host "Email   : $Email"
    Write-Host ""

    $envPath = Join-Path $ProjectRoot ".env.local"
    $envMap = Read-EnvFile -Path $envPath

    $supabaseUrl = [string]$envMap["NEXT_PUBLIC_SUPABASE_URL"]
    $publishableKey = [string]$envMap["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"]

    if (-not $supabaseUrl) {
        $supabaseUrl = "http://127.0.0.1:54321"
    }

    $supabaseUrl = $supabaseUrl.TrimEnd("/")

    if (
        -not $publishableKey -or
        $publishableKey.Contains("REPLACE_ME")
    ) {
        throw "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is not valid."
    }

    if (-not $Password) {
        $Password = Read-Host `
            "Enter local Admin password" `
            -AsSecureString
    }

    $script:PlainPassword = Get-PlainTextPassword -SecurePassword $Password

    if (-not (Test-ServerReady)) {
        $serverLog = Join-Path `
            $env:TEMP `
            "stok-admin-shell-smoke-next.log"

        if (Test-Path -LiteralPath $serverLog) {
            Remove-Item -LiteralPath $serverLog -Force
        }

        Write-Host "Next.js is not running. Starting npm run dev..."

        $command = 'npm run dev > "{0}" 2>&1' -f $serverLog

        $script:ServerProcess = Start-Process `
            -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/s", "/c", $command) `
            -WorkingDirectory $ProjectRoot `
            -WindowStyle Hidden `
            -PassThru

        $script:StartedServer = $true

        $deadline = (Get-Date).AddSeconds(60)

        while ((Get-Date) -lt $deadline) {
            if (Test-ServerReady) {
                break
            }

            Start-Sleep -Milliseconds 750
        }

        if (-not (Test-ServerReady)) {
            $tail = ""

            if (Test-Path -LiteralPath $serverLog) {
                $tail = (
                    Get-Content -LiteralPath $serverLog -Tail 30
                ) -join [Environment]::NewLine
            }

            throw "Next.js did not become ready. Log:`n$tail"
        }

        Write-Host "Next.js is ready."
    } else {
        Write-Host "Using the existing Next.js server."
    }

    Write-Host ""
    Write-Host "Running tests..."
    Write-Host ""

    Invoke-SmokeTest `
        -Name "Source contract: one ADMIN role" `
        -Test {
            $authPath = Join-Path $ProjectRoot "src\lib\auth.ts"
            $authText = [System.IO.File]::ReadAllText($authPath)

            Assert-Contains `
                -Text $authText `
                -Expected 'role_code: "ADMIN"' `
                -Message 'ADMIN role contract was not found in src/lib/auth.ts.'

            Assert-NotContains `
                -Text $authText `
                -Unexpected 'role_code: "OPERATOR"' `
                -Message 'OPERATOR role is still active in src/lib/auth.ts.'

            Assert-NotContains `
                -Text $authText `
                -Unexpected 'role_code: "VIEWER"' `
                -Message 'VIEWER role is still active in src/lib/auth.ts.'

            return "Only ADMIN is active in the auth contract."
        }

    Invoke-SmokeTest `
        -Name "Source contract: mobile drawer safeguards" `
        -Test {
            $shellPath = Join-Path `
                $ProjectRoot `
                "src\app\app-shell\app-shell.tsx"

            $shellText = [System.IO.File]::ReadAllText($shellPath)

            $requiredMarkers = @(
                'aria-controls="mobile-navigation"',
                'accountMenuRef.current?.removeAttribute("open")',
                'event.key === "Escape"',
                'z-[60]'
            )

            foreach ($marker in $requiredMarkers) {
                Assert-Contains `
                    -Text $shellText `
                    -Expected $marker `
                    -Message "Missing mobile shell safeguard: $marker"
            }

            return "Drawer, Escape, account close, and layer markers exist."
        }

    Invoke-SmokeTest `
        -Name "Git diff whitespace check" `
        -Test {
            $output = & git diff --check 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw ($output -join [Environment]::NewLine)
            }

            return "No whitespace errors."
        }

    Invoke-SmokeTest `
        -Name "Anonymous login page has no Admin shell" `
        -Test {
            $response = Get-AppPage -Path "/login"
            $finalUri = Get-FinalUri -Response $response

            if ([int]$response.StatusCode -ne 200) {
                throw "Expected HTTP 200, received $($response.StatusCode)."
            }

            if ($finalUri.AbsolutePath -ne "/login") {
                throw "Expected /login, received $($finalUri.AbsolutePath)."
            }

            Assert-NotContains `
                -Text $response.Content `
                -Unexpected "Keluar dari akun" `
                -Message "Admin account menu leaked into the login page."

            Assert-NotContains `
                -Text $response.Content `
                -Unexpected "Ledger-first stock control" `
                -Message "Admin sidebar leaked into the login page."

            return "Login page is outside the authenticated shell."
        }

    Invoke-SmokeTest `
        -Name "Anonymous protected route redirects to login" `
        -Test {
            $response = Get-AppPage -Path "/"
            $finalUri = Get-FinalUri -Response $response

            if ($finalUri.AbsolutePath -ne "/login") {
                throw "Anonymous request ended at $($finalUri.AbsolutePath)."
            }

            return "Protected route ended at /login."
        }

    $tokenResponse = $null

    Invoke-SmokeTest `
        -Name "Supabase password login" `
        -Test {
            $headers = @{
                apikey = $publishableKey
            }

            $body = @{
                email    = $Email
                password = $script:PlainPassword
            } | ConvertTo-Json -Compress

            $script:TokenResponse = Invoke-RestMethod `
                -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
                -Method Post `
                -Headers $headers `
                -ContentType "application/json" `
                -Body $body

            if (
                -not $script:TokenResponse.access_token -or
                -not $script:TokenResponse.refresh_token
            ) {
                throw "Supabase did not return complete session tokens."
            }

            return "Auth token issued for $Email."
        }

    if (
        $script:Results |
        Where-Object {
            $_.Test -eq "Supabase password login" -and
            $_.Status -eq "PASS"
        }
    ) {
        $tokenResponse = $script:TokenResponse
    }

    $profile = $null

    if ($tokenResponse) {
        Invoke-SmokeTest `
            -Name "Current Admin profile" `
            -Test {
                $headers = @{
                    apikey         = $publishableKey
                    Authorization  = "Bearer $($tokenResponse.access_token)"
                    "Accept-Profile" = "api"
                }

                $profiles = @(
                    Invoke-RestMethod `
                        -Uri "$supabaseUrl/rest/v1/current_admin_profile?select=*" `
                        -Method Get `
                        -Headers $headers
                )

                if ($profiles.Count -ne 1) {
                    throw "Expected one active Admin profile, found $($profiles.Count)."
                }

                $script:Profile = $profiles[0]

                if ($script:Profile.role_code -ne "ADMIN") {
                    throw "Unexpected role: $($script:Profile.role_code)"
                }

                if (-not $script:Profile.organization_id) {
                    throw "Admin profile has no organization_id."
                }

                return (
                    "ADMIN profile active for organization {0}." -f
                    $script:Profile.organization_code
                )
            }

        if (
            $script:Results |
            Where-Object {
                $_.Test -eq "Current Admin profile" -and
                $_.Status -eq "PASS"
            }
        ) {
            $profile = $script:Profile
        }
    } else {
        Add-Result `
            -Name "Current Admin profile" `
            -Status "SKIP" `
            -Detail "Password login failed."
    }

    $appSession = $null

    if ($tokenResponse -and $profile) {
        $appUri = [uri]$BaseUrl
        $appSession = New-Object `
            Microsoft.PowerShell.Commands.WebRequestSession

        $accessCookie = New-Object System.Net.Cookie(
            "glowlab_access_token",
            [string]$tokenResponse.access_token,
            "/",
            $appUri.Host
        )

        $refreshCookie = New-Object System.Net.Cookie(
            "glowlab_refresh_token",
            [string]$tokenResponse.refresh_token,
            "/",
            $appUri.Host
        )

        $appSession.Cookies.Add($accessCookie)
        $appSession.Cookies.Add($refreshCookie)

        Invoke-SmokeTest `
            -Name "Authenticated /login redirects to dashboard" `
            -Test {
                $response = Get-AppPage `
                    -Path "/login" `
                    -Session $appSession

                $finalUri = Get-FinalUri -Response $response

                if ($finalUri.AbsolutePath -ne "/") {
                    throw "Expected dashboard redirect, received $($finalUri.AbsolutePath)."
                }

                return "Authenticated user ended at /."
            }

        $routes = @(
            "/",
            "/marketplace",
            "/returns",
            "/reconciliation",
            "/stocktakes",
            "/stocktakes/new"
        )

        foreach ($route in $routes) {
            Invoke-SmokeTest `
                -Name "Authenticated route: $route" `
                -Test {
                    $response = Get-AppPage `
                        -Path $route `
                        -Session $appSession

                    $finalUri = Get-FinalUri -Response $response

                    if ([int]$response.StatusCode -ne 200) {
                        throw "Expected HTTP 200, received $($response.StatusCode)."
                    }

                    if ($finalUri.AbsolutePath -ne $route) {
                        throw "Route ended at $($finalUri.AbsolutePath)."
                    }

                    Assert-Contains `
                        -Text $response.Content `
                        -Expected "Ledger-first stock control" `
                        -Message "Shared Admin shell marker was not rendered."

                    Assert-Contains `
                        -Text $response.Content `
                        -Expected "Keluar dari akun" `
                        -Message "Admin account control was not rendered."

                    Assert-Contains `
                        -Text $response.Content `
                        -Expected "ADMIN" `
                        -Message "ADMIN role marker was not rendered."

                    return "HTTP 200 with shared Admin shell."
                }
        }

        $stocktakeListResponse = $null

        try {
            $stocktakeListResponse = Get-AppPage `
                -Path "/stocktakes" `
                -Session $appSession
        } catch {
            $stocktakeListResponse = $null
        }

        if ($stocktakeListResponse) {
            $detailMatch = [regex]::Match(
                $stocktakeListResponse.Content,
                'href="/stocktakes/(?!new)([^"/?#]+)"'
            )

            if ($detailMatch.Success) {
                $detailPath = "/stocktakes/{0}" -f $detailMatch.Groups[1].Value

                Invoke-SmokeTest `
                    -Name "Authenticated stocktake detail route" `
                    -Test {
                        $response = Get-AppPage `
                            -Path $detailPath `
                            -Session $appSession

                        $finalUri = Get-FinalUri -Response $response

                        if ([int]$response.StatusCode -ne 200) {
                            throw "Expected HTTP 200, received $($response.StatusCode)."
                        }

                        if ($finalUri.AbsolutePath -ne $detailPath) {
                            throw "Detail route ended at $($finalUri.AbsolutePath)."
                        }

                        Assert-Contains `
                            -Text $response.Content `
                            -Expected "Kembali ke daftar" `
                            -Message "Stocktake context back link was not rendered."

                        return "Detail route loaded: $detailPath"
                    }
            } else {
                Add-Result `
                    -Name "Authenticated stocktake detail route" `
                    -Status "SKIP" `
                    -Detail "No stocktake detail link exists in current local data."
            }
        } else {
            Add-Result `
                -Name "Authenticated stocktake detail route" `
                -Status "SKIP" `
                -Detail "Stocktake list could not be read."
        }

        Invoke-SmokeTest `
            -Name "Session removal protects routes again" `
            -Test {
                $clearedSession = New-Object `
                    Microsoft.PowerShell.Commands.WebRequestSession

                $response = Get-AppPage `
                    -Path "/" `
                    -Session $clearedSession

                $finalUri = Get-FinalUri -Response $response

                if ($finalUri.AbsolutePath -ne "/login") {
                    throw "Cleared session ended at $($finalUri.AbsolutePath)."
                }

                return "Route protection restored after cookies are absent."
            }
    } else {
        $routeTests = @(
            "Authenticated /login redirects to dashboard",
            "Authenticated route: /",
            "Authenticated route: /marketplace",
            "Authenticated route: /returns",
            "Authenticated route: /reconciliation",
            "Authenticated route: /stocktakes",
            "Authenticated route: /stocktakes/new",
            "Authenticated stocktake detail route",
            "Session removal protects routes again"
        )

        foreach ($testName in $routeTests) {
            Add-Result `
                -Name $testName `
                -Status "SKIP" `
                -Detail "Authenticated session was not available."
        }
    }

    Write-Host ""
    Write-Host "Summary"
    Write-Host "-------"
    Write-Host ("PASS: {0}" -f $script:PassCount)
    Write-Host ("FAIL: {0}" -f $script:FailCount)
    Write-Host ("SKIP: {0}" -f $script:SkipCount)
    Write-Host ""

    $script:Results |
        Format-Table -AutoSize |
        Out-String |
        Write-Host

    if ($script:FailCount -gt 0) {
        Write-Host "SMOKE TEST RESULT: FAIL"
        exit 1
    }

    Write-Host "SMOKE TEST RESULT: PASS"
    Write-Host ""
    Write-Host "Not covered by HTTP PowerShell smoke test:"
    Write-Host "- visual desktop sidebar layout"
    Write-Host "- opening and closing the mobile drawer"
    Write-Host "- Escape key behavior in an actual browser"
    Write-Host "- account menu overlap in an actual browser"
    Write-Host "- browser console and hydration warnings"
} finally {
    $script:PlainPassword = $null

    if (
        $script:StartedServer -and
        $script:ServerProcess -and
        -not $KeepServer
    ) {
        Write-Host ""
        Write-Host "Stopping the Next.js server started by this script..."

        & taskkill.exe `
            /PID $script:ServerProcess.Id `
            /T `
            /F |
            Out-Null
    }
}
