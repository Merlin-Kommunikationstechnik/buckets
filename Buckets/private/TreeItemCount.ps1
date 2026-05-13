function TreeItemCount {
            param([int]$Count)
            if ($Count -eq 1) { "1 item" } else { "$Count items" }
        }