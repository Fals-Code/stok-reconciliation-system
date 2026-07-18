param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$ExpectedBranch,
  [switch]$IncludeScenarioDocs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$branch = (git -C $ProjectRoot branch --show-current).Trim()

if ($ExpectedBranch -and $branch -ne $ExpectedBranch) {
  throw "Expected branch '$ExpectedBranch', found '$branch'."
}

$contractDocs = @(
  "README.md",
  "docs/02-product-requirements.md",
  "docs/04-stock-ledger-design.md",
  "docs/06-user-roles-and-flows.md",
  "docs/07-marketplace-simulator.md",
  "docs/10-fefo-batch-allocation.md"
)

$scenarioDocs = @(
  "docs/14-testing-scenarios.md",
  "docs/15-demo-script.md"
)

$docs = @($contractDocs)

if ($IncludeScenarioDocs) {
  $docs += $scenarioDocs
}

$resolvedDocs = @(
  foreach ($relativePath in $docs) {
    $fullPath = Join-Path $ProjectRoot $relativePath

    if (-not (Test-Path $fullPath)) {
      throw "Required document was not found: $relativePath"
    }

    $fullPath
  }
)

$stalePatterns = [ordered]@{
  "receipt-to-quarantine" = @(
    'physical receipt -> QUARANTINE',
    'Return received masuk quarantine',
    'RETURN_RECEIVED_QUARANTINE',
    'Return receipt quarantine',
    'Retur diterima ke quarantine',
    'retur masuk ke quarantine',
    'Receipt masuk:',
    'Flow quarantine dan identifikasi'
  )
  "legacy-transfer" = @(
    'TRANSFER_QUARANTINE_TO_SELLABLE',
    'TRANSFER_QUARANTINE_TO_DAMAGED',
    'RETURN_INSPECTION_TRANSFER',
    'Transfer `QUARANTINE` ke `SELLABLE`',
    'Transfer `QUARANTINE` ke `DAMAGED`'
  )
  "placeholder-batch" = @(
    'unidentified return batch',
    'UNIDENTIFIED_RETURN_BATCH',
    'controlled unidentified return batch',
    'REC_RETURN_BATCH_PLACEHOLDER_RELEASE'
  )
  "ambiguous-claim-basis" = @(
    'claim_deadline_at = return_or_loss_reference_at',
    'tanggal dasar yang dikonfigurasi',
    'tenggat 40 hari yang configurable'
  )
  "encoding-corruption" = @(
    'ΓÇ'
  )
}

$staleMatches = New-Object System.Collections.Generic.List[object]

foreach ($group in $stalePatterns.Keys) {
  foreach ($pattern in $stalePatterns[$group]) {
    $matches = @(
      Select-String `
        -Path $resolvedDocs `
        -Pattern $pattern `
        -SimpleMatch
    )

    foreach ($match in $matches) {
      $staleMatches.Add([pscustomobject]@{
        Group = $group
        Path = $match.Path
        LineNumber = $match.LineNumber
        Line = $match.Line.Trim()
      })
    }
  }
}

if ($staleMatches.Count -gt 0) {
  $staleMatches |
    Sort-Object Path, LineNumber, Group |
    Format-Table -AutoSize -Wrap

  throw "Phase 1 return markers remain in active documentation."
}

$phase2SourceDocs = @(
  "docs/02-product-requirements.md",
  "docs/04-stock-ledger-design.md",
  "docs/06-user-roles-and-flows.md",
  "docs/07-marketplace-simulator.md",
  "docs/10-fefo-batch-allocation.md"
)

foreach ($relativePath in $phase2SourceDocs) {
  $fullPath = Join-Path $ProjectRoot $relativePath
  $sourceMatches = @(
    Select-String `
      -Path $fullPath `
      -Pattern 'VibeDev Phase 2 Sync Update v2, 13 Juni 2026' `
      -SimpleMatch
  )

  if ($sourceMatches.Count -eq 0) {
    throw "Phase 2 source priority missing from: $relativePath"
  }
}

$requiredPatterns = @(
  'RETURN_SELLABLE_INBOUND',
  'RETURN_RECEIPT_CONSISTENCY',
  'RETURN_INSPECTION_CONSISTENCY',
  'operations.returns.created_at',
  'batch `RETURN` baru',
  'stock-neutral'
)

foreach ($pattern in $requiredPatterns) {
  $matches = @(
    Select-String `
      -Path $resolvedDocs `
      -Pattern $pattern `
      -SimpleMatch
  )

  if ($matches.Count -eq 0) {
    throw "Required Phase 2 marker was not found: $pattern"
  }

  Write-Host ("FOUND {0}: {1}" -f $matches.Count, $pattern)
}

Write-Host "PHASE 2 RETURN DOC GUARD: PASS" -ForegroundColor Green