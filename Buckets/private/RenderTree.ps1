function RenderTree {
            param([PSCustomObject]$Node, [string]$Prefix, [bool]$IsLast, [bool]$IsRoot)

            if ($IsRoot) {
                $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                Write-Host "$($Node.Name) " -NoNewline -ForegroundColor $script:CAction
                Write-Host "($sizeStr)" -ForegroundColor DarkGray
            }
            else {
                $linePrefix = if ($IsLast) { "$Prefix└── " } else { "$Prefix├── " }

                if ($Node.Type -eq "Object") {
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host $Node.Name -ForegroundColor White
                }
                else {
                    $sizeStr = "$(TreeItemCount $Node.ObjectCount), $(TreeSize $Node.SizeBytes)"
                    Write-Host "$linePrefix" -NoNewline -ForegroundColor DarkGray
                    Write-Host "$($Node.Name) " -NoNewline -ForegroundColor Cyan
                    Write-Host "($sizeStr)" -ForegroundColor DarkGray
                }
            }

            $children = @($Node.Children)
            $bucketChildren = @($children | Where-Object { $_.Type -ne "Object" })
            $fileChildren = @($children | Where-Object { $_.Type -eq "Object" })

            $allItems = @()
            $allItems += $bucketChildren

            $truncatedFileCount = 0
            $childPrefix = if ($IsRoot) { "" } elseif ($IsLast) { "$Prefix    " } else { "$Prefix│   " }
            if ($fileChildren.Count -gt $MaxFiles) {
                $allItems += $fileChildren[0..($MaxFiles - 1)]
                $truncatedFileCount = $fileChildren.Count - $MaxFiles
            }
            else {
                $allItems += $fileChildren
            }

            for ($i = 0; $i -lt $allItems.Count; $i++) {
                $child = $allItems[$i]
                $childIsLast = $i -eq ($allItems.Count - 1)
                RenderTree -Node $child -Prefix $childPrefix -IsLast $childIsLast -IsRoot $false
            }

            if ($truncatedFileCount -gt 0) {
                Write-Host "$childPrefix└── " -NoNewline -ForegroundColor DarkGray
                Write-Host "... $truncatedFileCount more" -ForegroundColor $script:CNum
            }
        }