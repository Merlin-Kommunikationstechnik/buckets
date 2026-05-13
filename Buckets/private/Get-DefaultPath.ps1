function Get-DefaultPath {
    if ($script:BucketRoot) { return $script:BucketRoot }
    if ($env:BUCKETS_ROOT) { return $env:BUCKETS_ROOT }
    return Join-Path $HOME ".buckets"
}