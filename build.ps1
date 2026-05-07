#!/usr/bin/env pwsh
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$csproj = Join-Path $projectRoot 'Buckets/BucketsProvider.csproj'
$outputDll = Join-Path $projectRoot 'Buckets/BucketsProvider.dll'

if (-not (Test-Path $csproj)) {
    throw "Project file not found: $csproj"
}

Write-Host "Building BucketsProvider ($Configuration)..." -ForegroundColor Cyan

dotnet build $csproj --configuration $Configuration -v q | Out-Null

$builtDll = Join-Path $projectRoot "Buckets/bin/$Configuration/net8.0/BucketsProvider.dll"
if (-not (Test-Path $builtDll)) {
    throw "Build output not found: $builtDll"
}

Copy-Item -Force $builtDll $outputDll
Write-Host "Built: $outputDll" -ForegroundColor Green
