# ============================================================
# Gixbee - Import Path Fixer + Empty Folder Cleanup
# Run from project root: .\fix_imports.ps1
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Gixbee Import Fixer & Folder Cleanup  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$libRoot = "$PSScriptRoot\lib"
$dartFiles = Get-ChildItem -Path $libRoot -Recurse -Filter "*.dart"

$replacements = @(
    # models -> shared/models
    @{ From = "package:gixbee/models/business.dart";              To = "package:gixbee/shared/models/business.dart" },
    @{ From = "package:gixbee/models/job_post.dart";              To = "package:gixbee/shared/models/job_post.dart" },
    @{ From = "package:gixbee/models/talent_profile.dart";        To = "package:gixbee/shared/models/talent_profile.dart" },
    @{ From = "package:gixbee/models/user.dart";                  To = "package:gixbee/shared/models/user.dart" },
    @{ From = "package:gixbee/models/worker.dart";                To = "package:gixbee/shared/models/worker.dart" },

    # widgets -> shared/widgets
    @{ From = "package:gixbee/widgets/dribbble_background.dart";  To = "package:gixbee/shared/widgets/dribbble_background.dart" },
    @{ From = "package:gixbee/widgets/glass_container.dart";      To = "package:gixbee/shared/widgets/glass_container.dart" },

    # data -> repositories
    @{ From = "package:gixbee/data/auth_repository.dart";         To = "package:gixbee/repositories/auth_repository.dart" },
    @{ From = "package:gixbee/data/booking_repository.dart";      To = "package:gixbee/repositories/booking_repository.dart" },
    @{ From = "package:gixbee/data/business_repository.dart";     To = "package:gixbee/repositories/business_repository.dart" },
    @{ From = "package:gixbee/data/hiring_repository.dart";       To = "package:gixbee/repositories/hiring_repository.dart" },
    @{ From = "package:gixbee/data/master_entries_repository.dart"; To = "package:gixbee/repositories/master_entries_repository.dart" },
    @{ From = "package:gixbee/data/mock_repository.dart";         To = "package:gixbee/repositories/mock_repository.dart" },
    @{ From = "package:gixbee/data/profile_repository.dart";      To = "package:gixbee/repositories/profile_repository.dart" },
    @{ From = "package:gixbee/data/talent_repository.dart";       To = "package:gixbee/repositories/talent_repository.dart" },
    @{ From = "package:gixbee/data/wallet_repository.dart";       To = "package:gixbee/repositories/wallet_repository.dart" },
    @{ From = "package:gixbee/data/worker_repository.dart";       To = "package:gixbee/repositories/worker_repository.dart" },

    # features/common/theme_provider -> core/theme_provider
    @{ From = "package:gixbee/features/common/theme_provider.dart"; To = "package:gixbee/core/theme_provider.dart" },

    # Relative import variants (../models/, ../../models/ etc.)
    @{ From = "../models/business.dart";              To = "../shared/models/business.dart" },
    @{ From = "../models/job_post.dart";              To = "../shared/models/job_post.dart" },
    @{ From = "../models/talent_profile.dart";        To = "../shared/models/talent_profile.dart" },
    @{ From = "../models/user.dart";                  To = "../shared/models/user.dart" },
    @{ From = "../models/worker.dart";                To = "../shared/models/worker.dart" },
    @{ From = "../../models/business.dart";           To = "../../shared/models/business.dart" },
    @{ From = "../../models/job_post.dart";           To = "../../shared/models/job_post.dart" },
    @{ From = "../../models/talent_profile.dart";     To = "../../shared/models/talent_profile.dart" },
    @{ From = "../../models/user.dart";               To = "../../shared/models/user.dart" },
    @{ From = "../../models/worker.dart";             To = "../../shared/models/worker.dart" },

    @{ From = "../widgets/dribbble_background.dart";  To = "../shared/widgets/dribbble_background.dart" },
    @{ From = "../widgets/glass_container.dart";      To = "../shared/widgets/glass_container.dart" },
    @{ From = "../../widgets/dribbble_background.dart"; To = "../../shared/widgets/dribbble_background.dart" },
    @{ From = "../../widgets/glass_container.dart";   To = "../../shared/widgets/glass_container.dart" },

    @{ From = "../data/auth_repository.dart";         To = "../repositories/auth_repository.dart" },
    @{ From = "../data/booking_repository.dart";      To = "../repositories/booking_repository.dart" },
    @{ From = "../data/business_repository.dart";     To = "../repositories/business_repository.dart" },
    @{ From = "../data/hiring_repository.dart";       To = "../repositories/hiring_repository.dart" },
    @{ From = "../data/master_entries_repository.dart"; To = "../repositories/master_entries_repository.dart" },
    @{ From = "../data/mock_repository.dart";         To = "../repositories/mock_repository.dart" },
    @{ From = "../data/profile_repository.dart";      To = "../repositories/profile_repository.dart" },
    @{ From = "../data/talent_repository.dart";       To = "../repositories/talent_repository.dart" },
    @{ From = "../data/wallet_repository.dart";       To = "../repositories/wallet_repository.dart" },
    @{ From = "../data/worker_repository.dart";       To = "../repositories/worker_repository.dart" },
    @{ From = "../../data/auth_repository.dart";      To = "../../repositories/auth_repository.dart" },
    @{ From = "../../data/booking_repository.dart";   To = "../../repositories/booking_repository.dart" },
    @{ From = "../../data/business_repository.dart";  To = "../../repositories/business_repository.dart" },
    @{ From = "../../data/hiring_repository.dart";    To = "../../repositories/hiring_repository.dart" },
    @{ From = "../../data/master_entries_repository.dart"; To = "../../repositories/master_entries_repository.dart" },
    @{ From = "../../data/mock_repository.dart";      To = "../../repositories/mock_repository.dart" },
    @{ From = "../../data/profile_repository.dart";   To = "../../repositories/profile_repository.dart" },
    @{ From = "../../data/talent_repository.dart";    To = "../../repositories/talent_repository.dart" },
    @{ From = "../../data/wallet_repository.dart";    To = "../../repositories/wallet_repository.dart" },
    @{ From = "../../data/worker_repository.dart";    To = "../../repositories/worker_repository.dart" },

    @{ From = "../features/common/theme_provider.dart"; To = "../core/theme_provider.dart" },
    @{ From = "../../features/common/theme_provider.dart"; To = "../../core/theme_provider.dart" }
)

# ── Fix Imports ──────────────────────────────────────────────
Write-Host "[1/3] Scanning and fixing imports in $($dartFiles.Count) Dart files..." -ForegroundColor Yellow
Write-Host ""

$totalFixed = 0

foreach ($file in $dartFiles) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $originalContent = $content
    $fileChanged = $false
    $fileChanges = @()

    foreach ($rule in $replacements) {
        if ($content -match [regex]::Escape($rule.From)) {
            $content = $content -replace [regex]::Escape($rule.From), $rule.To
            $fileChanges += "    $($rule.From) -> $($rule.To)"
            $fileChanged = $true
            $totalFixed++
        }
    }

    if ($fileChanged) {
        Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
        $relativePath = $file.FullName.Replace("$PSScriptRoot\", "")
        Write-Host "  FIXED: $relativePath" -ForegroundColor Green
        foreach ($change in $fileChanges) {
            Write-Host $change -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

if ($totalFixed -eq 0) {
    Write-Host "  No imports needed fixing." -ForegroundColor DarkGray
} else {
    Write-Host "  Total import replacements made: $totalFixed" -ForegroundColor Green
}

Write-Host ""

# ── Remove Empty Directories ─────────────────────────────────
Write-Host "[2/3] Removing empty/stale directories..." -ForegroundColor Yellow
Write-Host ""

$staleDirs = @(
    "$libRoot\data",
    "$libRoot\models",
    "$libRoot\widgets",
    "$libRoot\src",
    "$libRoot\features\common"
)

foreach ($dir in $staleDirs) {
    if (Test-Path $dir) {
        $items = Get-ChildItem $dir -Recurse
        if ($items.Count -eq 0) {
            Remove-Item $dir -Recurse -Force
            Write-Host "  REMOVED: $($dir.Replace("$PSScriptRoot\", ''))" -ForegroundColor Red
        } else {
            Write-Host "  SKIPPED (not empty): $($dir.Replace("$PSScriptRoot\", ''))" -ForegroundColor DarkYellow
            Write-Host "    Remaining files:" -ForegroundColor DarkGray
            foreach ($item in $items) {
                Write-Host "      $($item.Name)" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "  ALREADY GONE: $($dir.Replace("$PSScriptRoot\", ''))" -ForegroundColor DarkGray
    }
}

Write-Host ""

# ── Final Verification ───────────────────────────────────────
Write-Host "[3/3] Final lib/ structure:" -ForegroundColor Yellow
Write-Host ""

function Show-Tree($path, $indent = "") {
    $items = Get-ChildItem $path | Where-Object { $_.Name -notmatch "^(\.dart_tool|build|\.idea|node_modules)$" }
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            Write-Host "$indent  [DIR]  $($item.Name)" -ForegroundColor Cyan
            Show-Tree $item.FullName "$indent  "
        } else {
            Write-Host "$indent  [FILE] $($item.Name)" -ForegroundColor White
        }
    }
}

Show-Tree $libRoot

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Done! Run 'flutter analyze' to verify." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
