param([switch]$Headed)

$ErrorActionPreference = "Stop"
if (-not $env:PLAYWRIGHT_ADMIN_EMAIL) { $env:PLAYWRIGHT_ADMIN_EMAIL = "demo.admin@glowlab.invalid" }
$securePassword = Read-Host "Password Admin lokal untuk Playwright" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
  $env:PLAYWRIGHT_ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
  $arguments = @("playwright", "test", "tests/e2e/stocktake-cancellation.spec.ts", "--project=desktop-chromium", "--project=mobile-chromium")
  if ($Headed) { $arguments += "--headed" }
  & npx @arguments
  exit $LASTEXITCODE
}
finally {
  if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
  Remove-Item Env:PLAYWRIGHT_ADMIN_PASSWORD -ErrorAction SilentlyContinue
}
