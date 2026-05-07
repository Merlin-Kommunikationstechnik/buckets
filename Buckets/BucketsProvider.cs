using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Provider;
using System.Text;
using System.Text.Json;

namespace Buckets.Provider
{
    public class BucketObjectInfo
    {
        public string LogicalPath { get; set; }
        public string PhysicalPath { get; set; }
        public string Key { get; set; }
        public string Bucket { get; set; }
        public string Format { get; set; }
        public bool Compressed { get; set; }
        public long SizeBytes { get; set; }
        public DateTime Modified { get; set; }
        public object Content { get; set; }
    }

    public class BucketItemInfo
    {
        public string Type
        {
            get
            {
                switch (ItemKind)
                {
                    case "bucket": return "b--";
                    case "array":  return "-a-";
                    case "object": return "--o";
                    default:       return IsContainer ? "b--" : "--o";
                }
            }
        }
        public DateTime LastWriteTime { get; set; }
        public DateTime CreationTime { get; set; }
        public string Size
        {
            get
            {
                if (IsContainer)
                {
                    return FormatSize(SizeBytes);
                }
                return SizeBytes > 0 ? FormatSize(SizeBytes) : "--";
            }
        }
        public string Name { get; set; }

        // Internal use only
        internal bool IsContainer { get; set; }
        internal string ItemKind { get; set; } // "bucket", "array", "object"
        internal int ItemCount { get; set; }
        internal string Format { get; set; }
        internal long SizeBytes { get; set; }
        internal string PhysicalPath { get; set; }

        private static string FormatSize(long bytes)
        {
            if (bytes == 0) return "0 B";
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            int unit = 0;
            double size = bytes;
            while (size >= 1024 && unit < units.Length - 1)
            {
                size /= 1024;
                unit++;
            }
            return (int)Math.Round(size) + " " + units[unit];
        }
    }

    [CmdletProvider("Buckets", ProviderCapabilities.ShouldProcess)]
    public class BucketsProvider : NavigationCmdletProvider, IContentCmdletProvider
    {
        private static readonly char[] InvalidChars = { '/', ':', '*', '?', '"', '<', '>', '|', '.', '[', ']' };
        private static readonly byte[] GZipMagic = { 0x1F, 0x8B };
        private static readonly char ProviderSep = Path.DirectorySeparatorChar;
        private static readonly char Sep = Path.DirectorySeparatorChar;
        private const string ArraysDir = ".arrays";

        // Static cache: drive name -> physical root path
        private static readonly Dictionary<string, string> DriveRoots = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        #region Drive Support

        protected override PSDriveInfo NewDrive(PSDriveInfo drive)
        {
            if (drive == null || string.IsNullOrEmpty(drive.Root))
            {
                WriteError(new ErrorRecord(
                    new ArgumentNullException("drive", "Drive root cannot be null or empty."),
                    "NullDrive", ErrorCategory.InvalidArgument, drive));
                return null;
            }

            string root = drive.Root;
            if (!Path.IsPathRooted(root))
            {
                var cwd = SessionState.Path.CurrentFileSystemLocation;
                if (cwd != null)
                {
                    root = Path.Combine(cwd.Path, root);
                }
            }
            root = Path.GetFullPath(root);

            if (!Directory.Exists(root))
            {
                Directory.CreateDirectory(root);
            }

            // Return PSDriveInfo with drive name as logical root
            var newDrive = new PSDriveInfo(drive.Name, this.ProviderInfo, drive.Name + ":" + ProviderSep, drive.Description, drive.Credential);
            DriveRoots[drive.Name] = root;
            SessionState.PSVariable.Set("__buckets_physical_root_" + drive.Name, root);
            return newDrive;
        }

        private string GetPhysicalRoot()
        {
            string driveName = PSDriveInfo.Name;

            // Check static cache first (works across all scopes)
            if (DriveRoots.TryGetValue(driveName, out string cachedRoot))
            {
                return cachedRoot;
            }

            // Fall back to session variable
            string varName = "__buckets_physical_root_" + driveName;
            var variable = SessionState.PSVariable.Get(varName);
            if (variable?.Value is string sessionRoot)
            {
                DriveRoots[driveName] = sessionRoot;
                return sessionRoot;
            }

            // Last resort: drive root (shouldn't happen)
            return PSDriveInfo.Root;
        }

        protected override Collection<PSDriveInfo> InitializeDefaultDrives()
        {
            return new Collection<PSDriveInfo>();
        }

        protected override PSDriveInfo RemoveDrive(PSDriveInfo drive)
        {
            return null;
        }

        #endregion

        #region Path Resolution

        /// <summary>
        /// Convert a provider-logical path to the actual filesystem path.
        /// Supports nested buckets: projects/myproject/arrayname resolves to
        /// projects/myproject/.arrays/arrayname (if myproject is a bucket with .dat/.json files).
        /// </summary>
        private string ToPhysicalPath(string path)
        {
            string root = GetPhysicalRoot();

            if (string.IsNullOrEmpty(path))
            {
                return Directory.Exists(root) ? root : null;
            }

            // Strip provider qualification: Buckets::...
            int colonColon = path.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0)
            {
                path = path.Substring(colonColon + 2);
            }

            // Strip drive prefix: buckets: or Buckets:
            string driveName = PSDriveInfo.Name + ":";
            if (path.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                path = path.Substring(driveName.Length);
            }

            // Strip leading separators
            path = path.TrimStart(Sep, '/', '\\');

            if (string.IsNullOrEmpty(path))
            {
                return Directory.Exists(root) ? root : null;
            }

            // Check if it's a filesystem-absolute path
            if (Path.IsPathRooted(path))
            {
                string normalized = Path.GetFullPath(path);
                if (Directory.Exists(normalized)) return normalized;
                if (File.Exists(normalized)) return normalized;
                string datPath = normalized + ".dat";
                if (File.Exists(datPath)) return datPath;
                string jsonPath = normalized + ".json";
                if (File.Exists(jsonPath)) return jsonPath;
                return null;
            }

            // Normalize separators and split into parts
            path = path.Replace('/', Sep).Replace('\\', Sep);
            string[] rawParts = path.Split(new[] { Sep }, StringSplitOptions.RemoveEmptyEntries);

            // Resolve .. segments (clamp to root)
            var parts = new System.Collections.Generic.List<string>();
            foreach (var part in rawParts)
            {
                if (part == ".") continue;
                if (part == "..") continue;
                parts.Add(part);
            }

            if (parts.Count == 0)
            {
                return Directory.Exists(root) ? root : null;
            }

            // Build the physical path for a prefix of parts
            string BuildPath(int count)
            {
                string p = root;
                for (int i = 0; i < count; i++) p = Path.Combine(p, parts[i]);
                return p;
            }

            // Strategy: walk from longest bucket prefix to shortest.
            // For "a/b/c/d", try:
            //   1. a/b/c is bucket? -> a/b/c/.arrays/d, a/b/c/d.dat, a/b/c/d.json
            //   2. a/b is bucket? -> a/b/.arrays/c/d, a/b/c/d.dat, a/b/c/d.json
            //   3. a is bucket? -> a/.arrays/b/c/d, a/b/c/d.dat, a/b/c/d.json
            //   4. Fall back to direct path

            for (int bucketLen = parts.Count - 1; bucketLen >= 1; bucketLen--)
            {
                string bucketDir = BuildPath(bucketLen);
                if (!Directory.Exists(bucketDir)) continue;

                // Only treat as bucket if it has .dat/.json files, or it's the first segment
                // (first segment is always a potential bucket for backward compatibility)
                bool looksLikeBucket = bucketLen == 1 || IsBucketDirectory(bucketDir);
                if (!looksLikeBucket) continue;

                // Remaining parts after bucket prefix
                int remainCount = parts.Count - bucketLen;
                if (remainCount == 0)
                {
                    // Exact bucket path
                    return bucketDir;
                }

                // Try array resolution: bucket/.arrays/<remain parts>
                string arrayPath = bucketDir;
                arrayPath = Path.Combine(arrayPath, ArraysDir);
                for (int i = bucketLen; i < parts.Count; i++)
                {
                    arrayPath = Path.Combine(arrayPath, parts[i]);
                }
                if (Directory.Exists(arrayPath)) return arrayPath;
                if (File.Exists(arrayPath)) return arrayPath;
                if (File.Exists(arrayPath + ".dat")) return arrayPath + ".dat";
                if (File.Exists(arrayPath + ".json")) return arrayPath + ".json";

                // Try direct object files: bucket/<last part>.dat/.json (only for 1 remaining part)
                if (remainCount == 1)
                {
                    string objPath = Path.Combine(bucketDir, parts[bucketLen]);
                    if (File.Exists(objPath)) return objPath;
                    if (File.Exists(objPath + ".dat")) return objPath + ".dat";
                    if (File.Exists(objPath + ".json")) return objPath + ".json";
                }

                // Try direct directory path
                string directPath = BuildPath(parts.Count);
                if (Directory.Exists(directPath)) return directPath;
                if (File.Exists(directPath)) return directPath;
            }

            // Last resort: direct path from root
            string finalPath = BuildPath(parts.Count);
            if (Directory.Exists(finalPath)) return finalPath;
            if (File.Exists(finalPath)) return finalPath;

            return null;
        }

        /// <summary>
        /// Convert a physical filesystem path to a provider-logical path.
        /// Strips .arrays/ from the path for a flattened view.
        /// Works with nested buckets at any depth.
        /// </summary>
        private string ToLogicalPath(string physicalPath)
        {
            string root = GetPhysicalRoot();
            if (!physicalPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                return physicalPath;
            }

            string relative = physicalPath.Substring(root.Length).TrimStart(Sep);

            // Find the bucket root in the physical path to properly strip .arrays/
            string bucketPhysical = FindBucketAncestor(physicalPath, root);
            if (bucketPhysical != null && IsArrayDirectory(physicalPath))
            {
                // We're inside a .arrays/ dir of a bucket
                string bucketRelative = bucketPhysical.Substring(root.Length).TrimStart(Sep);
                string arraysPrefix = bucketPhysical + Sep + ArraysDir + Sep;
                if (physicalPath.StartsWith(arraysPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    string afterArrays = physicalPath.Substring(arraysPrefix.Length);
                    string itemDir = Path.GetDirectoryName(afterArrays) ?? "";
                    string itemName = Path.GetFileName(afterArrays);
                    string itemPart = string.IsNullOrEmpty(itemDir) ? itemName : itemDir + Sep + itemName;
                    relative = bucketRelative + ProviderSep + itemPart;
                }
            }
            // Also handle .arrays/ at the first segment level (backward compat)
            else if (relative.StartsWith(ArraysDir + Sep, StringComparison.OrdinalIgnoreCase) ||
                     relative.StartsWith(ArraysDir + "\\", StringComparison.OrdinalIgnoreCase))
            {
                string arraysPrefix = ArraysDir + Sep;
                if (relative.StartsWith(arraysPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    relative = relative.Substring(arraysPrefix.Length);
                }
            }

            // Strip known extensions
            string lower = relative.ToLowerInvariant();
            if (lower.EndsWith(".dat"))
            {
                relative = relative.Substring(0, relative.Length - 4);
            }
            else if (lower.EndsWith(".json"))
            {
                relative = relative.Substring(0, relative.Length - 5);
            }

            return relative;
        }

        /// <summary>
        /// Extract the full bucket path (relative to root) from a physical path.
        /// Works with nested buckets at any depth.
        /// </summary>
        private string GetBucketNameFromPhysical(string physicalPath, string root)
        {
            string bucketPhysical = FindBucketAncestor(physicalPath, root);
            if (bucketPhysical != null)
            {
                return bucketPhysical.Substring(root.Length).TrimStart(Sep);
            }
            // Fallback: just first segment
            string relative = physicalPath.Substring(root.Length).TrimStart(Sep);
            string[] parts = relative.Split(new[] { Sep }, StringSplitOptions.RemoveEmptyEntries);
            return parts.Length > 0 ? parts[0] : "";
        }

        #endregion

        #region Serialization

        private object DeserializeFile(string physicalPath, out string format, out bool compressed)
        {
            format = "Binary";
            compressed = false;
            byte[] bytes = File.ReadAllBytes(physicalPath);
            string ext = Path.GetExtension(physicalPath).ToLowerInvariant();

            if (ext == ".dat")
            {
                if (bytes.Length >= 2 && bytes[0] == GZipMagic[0] && bytes[1] == GZipMagic[1])
                {
                    compressed = true;
                    using (var ms = new MemoryStream(bytes))
                    using (var gzip = new GZipStream(ms, CompressionMode.Decompress))
                    using (var reader = new StreamReader(gzip, Encoding.Unicode))
                    {
                        string gzXml = reader.ReadToEnd();
                        return PSSerializer.Deserialize(gzXml);
                    }
                }

                string xml = Encoding.UTF8.GetString(bytes);
                return PSSerializer.Deserialize(xml);
            }
            else if (ext == ".json")
            {
                format = "JSON";
                string json = Encoding.UTF8.GetString(bytes);
                if (json.StartsWith("\ufeff")) json = json.Substring(1);
                return PSSerializer.Deserialize(json);
            }

            throw new InvalidOperationException($"Unsupported format: {ext}");
        }

        private void SerializeFile(object value, string physicalPath, string format)
        {
            string dir = Path.GetDirectoryName(physicalPath);
            if (!Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            if (format.Equals("json", StringComparison.OrdinalIgnoreCase))
            {
                TrySerializeJson(value, physicalPath);
            }
            else
            {
                string xml = PSSerializer.Serialize(value);
                File.WriteAllBytes(physicalPath, Encoding.UTF8.GetBytes(xml));
            }
        }

        internal object DeserializeFileInternal(string physicalPath, out string format, out bool compressed)
        {
            return DeserializeFile(physicalPath, out format, out compressed);
        }

        internal void SerializeFileInternal(object value, string physicalPath, string format)
        {
            SerializeFile(value, physicalPath, format);
        }

        private void TrySerializeJson(object value, string physicalPath)
        {
            try
            {
                object serializable = ConvertToSerializable(value);
                var options = new JsonSerializerOptions
                {
                    WriteIndented = true,
                    Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                };
                string json = JsonSerializer.Serialize(serializable, options);
                File.WriteAllText(physicalPath, json, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                string datPath = Path.ChangeExtension(physicalPath, ".dat");
                WriteWarning($"JSON serialization failed: {ex.Message}. Falling back to binary ({datPath}).");
                string xml = PSSerializer.Serialize(value);
                File.WriteAllBytes(datPath, Encoding.Unicode.GetBytes(xml));
            }
        }

        private object ConvertToSerializable(object value)
        {
            if (value is IDictionary dict)
            {
                var result = new Dictionary<string, object>();
                foreach (DictionaryEntry entry in dict)
                {
                    result[entry.Key?.ToString() ?? ""] = ConvertToSerializable(entry.Value);
                }
                return result;
            }

            var pso = value as PSObject;
            if (pso != null)
            {
                var result = new Dictionary<string, object>();
                foreach (var prop in pso.Properties.Where(p => p.IsGettable))
                {
                    result[prop.Name] = ConvertToSerializable(prop.Value);
                }
                return result;
            }

            if (value is IEnumerable enumerable && value is not string)
            {
                var list = new List<object>();
                foreach (var item in enumerable)
                {
                    list.Add(ConvertToSerializable(item));
                }
                return list;
            }

            return value;
        }

        #endregion

        #region Helpers

        private string SanitizeKey(string key)
        {
            string result = key;
            foreach (var ch in InvalidChars)
            {
                result = result.Replace(ch.ToString(), "_");
            }
            return result;
        }

        /// <summary>
        /// Determine if a physical directory is a bucket (has .dat/.json files).
        /// Works at any depth, enabling nested buckets.
        /// </summary>
        private bool IsBucketDirectory(string physicalDir)
        {
            if (!Directory.Exists(physicalDir)) return false;
            var di = new DirectoryInfo(physicalDir);
            return di.GetFiles("*.dat").Length > 0 || di.GetFiles("*.json").Length > 0;
        }

        /// <summary>
        /// Determine if a physical directory is inside .arrays/
        /// </summary>
        private bool IsArrayDirectory(string physicalDir)
        {
            string normalized = physicalDir.Replace('\\', Sep);
            return normalized.Contains(Sep + ArraysDir + Sep) ||
                   normalized.EndsWith(Sep + ArraysDir);
        }

        /// <summary>
        /// Determine if we're at the drive root (not inside any bucket).
        /// </summary>
        private bool IsDriveRoot(string physicalDir, string root)
        {
            return string.Equals(Path.GetFullPath(physicalDir), Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Find the nearest bucket ancestor directory for a physical path.
        /// Walks up from the given directory toward root, returning the first
        /// directory that is a bucket (has .dat/.json files).
        /// Returns null if no bucket ancestor found.
        /// </summary>
        private string FindBucketAncestor(string physicalPath, string root)
        {
            // Start with parent directory if path is a file
            string current = File.Exists(physicalPath) ? Path.GetDirectoryName(physicalPath) : physicalPath;
            while (!string.IsNullOrEmpty(current) && current.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                if (IsBucketDirectory(current)) return current;
                string parent = Path.GetDirectoryName(current);
                if (string.IsNullOrEmpty(parent) || parent == current) break;
                current = parent;
            }
            return null;
        }

        /// <summary>
        /// Count nested bucket directories and their arrays recursively.
        /// Returns the total number of array directories in all nested buckets.
        /// </summary>
        private int CountNestedBuckets(string directory, string root)
        {
            int count = 0;
            var di = new DirectoryInfo(directory);
            foreach (var subDir in di.GetDirectories())
            {
                if (subDir.Name == ".buckets" || subDir.Name == ArraysDir) continue;
                if (IsBucketDirectory(subDir.FullName))
                {
                    string arraysPath = Path.Combine(subDir.FullName, ArraysDir);
                    if (Directory.Exists(arraysPath))
                    {
                        count += new DirectoryInfo(arraysPath).GetDirectories().Length;
                    }
                }
                count += CountNestedBuckets(subDir.FullName, root);
            }
            return count;
        }

        /// <summary>
        /// Recursively calculate total size of .dat and .json files in a directory tree.
        /// Skips .arrays/ directories (their files are counted at the bucket level).
        /// </summary>
        private long GetDirectorySize(string directory)
        {
            long total = 0;
            try
            {
                var di = new DirectoryInfo(directory);
                foreach (var file in di.GetFiles("*.dat"))
                {
                    total += file.Length;
                }
                foreach (var file in di.GetFiles("*.json"))
                {
                    total += file.Length;
                }
                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ".buckets" && d.Name != ArraysDir))
                {
                    total += GetDirectorySize(subDir.FullName);
                }
                // Also count .arrays/ files directly (they belong to this bucket)
                string arraysPath = Path.Combine(directory, ArraysDir);
                if (Directory.Exists(arraysPath))
                {
                    total += GetDirectorySize(arraysPath);
                }
            }
            catch { }
            return total;
        }

        private string GetBucketName(string logicalPath)
        {
            string normalized = ToLogicalPath(logicalPath).TrimStart(Sep, '/', '\\');
            int sep = normalized.IndexOf(Sep);
            return sep < 0 ? normalized : normalized.Substring(0, sep);
        }

        private string GetKeyName(string logicalPath)
        {
            string normalized = ToLogicalPath(logicalPath).TrimStart(Sep, '/', '\\');
            int sep = normalized.LastIndexOf(Sep);
            return sep < 0 ? normalized : normalized.Substring(sep + 1);
        }

        #endregion

        #region Core Provider Methods

        protected override bool IsValidPath(string path)
        {
            return true;
        }

        protected override bool ItemExists(string path)
        {
            return ToPhysicalPath(path) != null;
        }

        protected override bool IsItemContainer(string path)
        {
            string physical = ToPhysicalPath(path);
            return physical != null && Directory.Exists(physical);
        }

        protected override void GetItem(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null)
            {
                WriteError(new ErrorRecord(
                    new ItemNotFoundException($"Item not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            if (Directory.Exists(physical))
            {
                string root = GetPhysicalRoot();
                bool isDriveRoot = IsDriveRoot(physical, root);
                bool isBucket = IsBucketDirectory(physical);
                bool isArrayDir = IsArrayDirectory(physical);

                string itemKind;
                if (isDriveRoot) itemKind = "bucket";
                else if (isBucket) itemKind = "bucket";
                else if (isArrayDir) itemKind = "array";
                else itemKind = "bucket";

                var di = new DirectoryInfo(physical);
                var files = di.GetFiles("*.dat").Concat(di.GetFiles("*.json"));
                var dirs = di.GetDirectories().Where(d => d.Name != ".buckets" && d.Name != ArraysDir);
                int arrayCount = 0;
                if (isBucket || isDriveRoot)
                {
                    string arraysPath = isDriveRoot ? "" : Path.Combine(physical, ArraysDir);
                    if (isDriveRoot)
                    {
                        foreach (var bucketDir in di.GetDirectories().Where(d => d.Name != ".buckets"))
                        {
                            string bucketArrays = Path.Combine(bucketDir.FullName, ArraysDir);
                            if (Directory.Exists(bucketArrays))
                            {
                                arrayCount += new DirectoryInfo(bucketArrays).GetDirectories().Length;
                            }
                            // Also count nested buckets in subdirectories
                            arrayCount += CountNestedBuckets(bucketDir.FullName, root);
                        }
                    }
                    else
                    {
                        arrayCount = Directory.Exists(arraysPath) ? new DirectoryInfo(arraysPath).GetDirectories().Length : 0;
                        arrayCount += CountNestedBuckets(physical, root);
                    }
                }
                int count = files.Count() + dirs.Count() + arrayCount;

                var info = new BucketItemInfo
                {
                    Name = di.Name,
                    IsContainer = true,
                    ItemKind = itemKind,
                    ItemCount = count,
                    Format = "",
                    SizeBytes = GetDirectorySize(physical),
                    PhysicalPath = physical,
                    LastWriteTime = di.LastWriteTime,
                    CreationTime = di.CreationTime
                };

                WriteItemObject(info, ToLogicalPath(physical), true);
            }
            else
            {
                try
                {
                    object content = DeserializeFile(physical, out string format, out bool compressed);
                    var fi = new FileInfo(physical);
                    var info = new BucketObjectInfo
                    {
                        LogicalPath = ToLogicalPath(physical),
                        PhysicalPath = physical,
                        Key = GetKeyName(path),
                        Bucket = GetBucketName(path),
                        Format = format,
                        Compressed = compressed,
                        SizeBytes = fi.Length,
                        Modified = fi.LastWriteTime,
                        Content = content
                    };

                    WriteItemObject(info, ToLogicalPath(physical), false);
                }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(
                        new RuntimeException($"Failed to deserialize: {ex.Message}"),
                        "DeserializeFailed", ErrorCategory.ReadError, path));
                }
            }
        }

        protected override void GetChildItems(string path, bool recurse)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !Directory.Exists(physical))
            {
                return;
            }

            uint currentDepth = 0;
            EnumerateDirectory(physical, recurse, null, ref currentDepth);
        }

        protected override void GetChildItems(string path, bool recurse, uint depth)
        {
            GetChildItemsInternal(path, recurse, depth);
        }

        private void GetChildItemsInternal(string path, bool recurse, uint? depthLimit = null)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !Directory.Exists(physical))
            {
                return;
            }

            uint currentDepth = 0;
            EnumerateDirectory(physical, recurse, depthLimit, ref currentDepth);
        }

        private void EnumerateDirectory(string directory, bool recurse, uint? depthLimit, ref uint currentDepth)
        {
            if (depthLimit.HasValue && currentDepth >= depthLimit.Value) return;

            var di = new DirectoryInfo(directory);
            string root = GetPhysicalRoot();
            bool isDriveRoot = IsDriveRoot(directory, root);
            bool isBucket = IsBucketDirectory(directory);

            if (isDriveRoot)
            {
                // At drive root: show bucket directories (b--)
                foreach (var bucketDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    int directFiles = bucketDir.GetFiles("*.dat").Length + bucketDir.GetFiles("*.json").Length;
                    var arraysPath = Path.Combine(bucketDir.FullName, ArraysDir);
                    int arrayCount = Directory.Exists(arraysPath) ? new DirectoryInfo(arraysPath).GetDirectories().Length : 0;
                    int nestedArrays = CountNestedBuckets(bucketDir.FullName, root);
                    int count = directFiles + arrayCount + nestedArrays;

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = bucketDir.Name,
                        IsContainer = true,
                        ItemKind = "bucket",
                        ItemCount = count,
                        Format = "",
                        SizeBytes = GetDirectorySize(bucketDir.FullName),
                        PhysicalPath = bucketDir.FullName,
                        LastWriteTime = bucketDir.LastWriteTime,
                        CreationTime = bucketDir.CreationTime
                    }, bucketDir.Name, true);

                    if (recurse)
                    {
                        currentDepth++;
                        EnumerateDirectory(bucketDir.FullName, recurse, depthLimit, ref currentDepth);
                        currentDepth--;
                    }
                }
            }
            else if (isBucket)
            {
                // At a bucket (any depth): show files, arrays, and nested bucket subdirectories

                // Regular files (--o)
                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string ext = Path.GetExtension(file.Name).ToLowerInvariant();
                    string logical = ToLogicalPath(file.FullName);

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = Path.GetFileNameWithoutExtension(file.Name),
                        IsContainer = false,
                        ItemKind = "object",
                        ItemCount = 0,
                        Format = ext == ".json" ? "JSON" : "Binary",
                        SizeBytes = file.Length,
                        PhysicalPath = file.FullName,
                        LastWriteTime = file.LastWriteTime,
                        CreationTime = file.CreationTime
                    }, logical, false);
                }

                // Array directories from .arrays/ (-a-)
                string arraysPath = Path.Combine(directory, ArraysDir);
                if (Directory.Exists(arraysPath))
                {
                    var arraysDir = new DirectoryInfo(arraysPath);
                    foreach (var arrayDir in arraysDir.GetDirectories().OrderBy(d => d.Name))
                    {
                        var files = arrayDir.GetFiles("*.dat").Concat(arrayDir.GetFiles("*.json"));
                        int count = files.Count();

                        // Logical path: full bucket path + arrayname
                        string bucketRelative = directory.Substring(root.Length).TrimStart(Sep);
                        string logical = bucketRelative.Replace(Sep, ProviderSep) + ProviderSep + arrayDir.Name;

                        WriteItemObject(new BucketItemInfo
                        {
                            Name = arrayDir.Name,
                            IsContainer = true,
                            ItemKind = "array",
                            ItemCount = count,
                            Format = "",
                            SizeBytes = GetDirectorySize(arrayDir.FullName),
                            PhysicalPath = arrayDir.FullName,
                            LastWriteTime = arrayDir.LastWriteTime,
                            CreationTime = arrayDir.CreationTime
                        }, logical, true);

                        if (recurse)
                        {
                            currentDepth++;
                            EnumerateDirectory(arrayDir.FullName, recurse, depthLimit, ref currentDepth);
                            currentDepth--;
                        }
                    }
                }

                // Nested bucket subdirectories (b--)
                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ArraysDir && d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    if (IsBucketDirectory(subDir.FullName))
                    {
                        int subFiles = subDir.GetFiles("*.dat").Length + subDir.GetFiles("*.json").Length;
                        string subArrays = Path.Combine(subDir.FullName, ArraysDir);
                        int subArrayCount = Directory.Exists(subArrays) ? new DirectoryInfo(subArrays).GetDirectories().Length : 0;
                        int subNested = CountNestedBuckets(subDir.FullName, root);
                        int subCount = subFiles + subArrayCount + subNested;

                        string logical = subDir.FullName.Substring(root.Length).TrimStart(Sep).Replace(Sep, ProviderSep);

                        WriteItemObject(new BucketItemInfo
                        {
                            Name = subDir.Name,
                            IsContainer = true,
                            ItemKind = "bucket",
                            ItemCount = subCount,
                            Format = "",
                            SizeBytes = GetDirectorySize(subDir.FullName),
                            PhysicalPath = subDir.FullName,
                            LastWriteTime = subDir.LastWriteTime,
                            CreationTime = subDir.CreationTime
                        }, logical, true);

                        if (recurse)
                        {
                            currentDepth++;
                            EnumerateDirectory(subDir.FullName, recurse, depthLimit, ref currentDepth);
                            currentDepth--;
                        }
                    }
                }
            }
            else if (IsArrayDirectory(directory))
            {
                // Inside an array directory: show array item files (--o)
                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string ext = Path.GetExtension(file.Name).ToLowerInvariant();
                    string logical = ToLogicalPath(file.FullName);

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = Path.GetFileNameWithoutExtension(file.Name),
                        IsContainer = false,
                        ItemKind = "object",
                        ItemCount = 0,
                        Format = ext == ".json" ? "JSON" : "Binary",
                        SizeBytes = file.Length,
                        PhysicalPath = file.FullName,
                        LastWriteTime = file.LastWriteTime,
                        CreationTime = file.CreationTime
                    }, logical, false);
                }
            }
            else
            {
                // General subdirectory (not a bucket, not array): show subdirectories as potential buckets
                foreach (var subDir in di.GetDirectories().OrderBy(d => d.Name))
                {
                    if (subDir.Name == ".buckets" || subDir.Name == ArraysDir) continue;

                    bool subIsBucket = IsBucketDirectory(subDir.FullName);
                    var files = subDir.GetFiles("*.dat").Concat(subDir.GetFiles("*.json"));
                    int fileCount = files.Count();
                    int subCount = fileCount;
                    string subArraysPath = Path.Combine(subDir.FullName, ArraysDir);
                    if (Directory.Exists(subArraysPath))
                    {
                        subCount += new DirectoryInfo(subArraysPath).GetDirectories().Length;
                    }
                    subCount += CountNestedBuckets(subDir.FullName, root);

                    string logical = ToLogicalPath(subDir.FullName);

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = subDir.Name,
                        IsContainer = true,
                        ItemKind = subIsBucket ? "bucket" : "bucket",
                        ItemCount = subCount,
                        Format = "",
                        SizeBytes = GetDirectorySize(subDir.FullName),
                        PhysicalPath = subDir.FullName,
                        LastWriteTime = subDir.LastWriteTime,
                        CreationTime = subDir.CreationTime
                    }, logical, true);

                    if (recurse)
                    {
                        currentDepth++;
                        EnumerateDirectory(subDir.FullName, recurse, depthLimit, ref currentDepth);
                        currentDepth--;
                    }
                }

                // Files
                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string ext = Path.GetExtension(file.Name).ToLowerInvariant();
                    string logical = ToLogicalPath(file.FullName);

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = Path.GetFileNameWithoutExtension(file.Name),
                        IsContainer = false,
                        ItemKind = "object",
                        ItemCount = 0,
                        Format = ext == ".json" ? "JSON" : "Binary",
                        SizeBytes = file.Length,
                        PhysicalPath = file.FullName,
                        LastWriteTime = file.LastWriteTime,
                        CreationTime = file.CreationTime
                    }, logical, false);
                }
            }
        }

        protected override void GetChildNames(string path, ReturnContainers returnContainers)
        {
            string physical = ToPhysicalPath(path);
            
            // Fallback: if path doesn't resolve, use the physical root directly
            if (physical == null || !Directory.Exists(physical))
            {
                physical = GetPhysicalRoot();
                if (!Directory.Exists(physical)) return;
            }

            var di = new DirectoryInfo(physical);
            string root = GetPhysicalRoot();
            bool isDriveRoot = IsDriveRoot(physical, root);
            bool isBucket = IsBucketDirectory(physical);

            if (isDriveRoot)
            {
                foreach (var bucketDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    string logicalPath = PSDriveInfo.Name + ":" + ProviderSep + bucketDir.Name;
                    WriteItemObject(bucketDir.Name, logicalPath, true);
                }
            }
            else if (isBucket)
            {
                // Build the parent path from the physical directory
                string bucketRelative = physical.Substring(root.Length).TrimStart(Sep);
                string parentPath = PSDriveInfo.Name + ":" + ProviderSep + bucketRelative.Replace(Sep, ProviderSep);

                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, parentPath + ProviderSep + name, false);
                }

                string arraysPath = Path.Combine(physical, ArraysDir);
                if (Directory.Exists(arraysPath))
                {
                    var arraysDir = new DirectoryInfo(arraysPath);
                    foreach (var arrayDir in arraysDir.GetDirectories().OrderBy(d => d.Name))
                    {
                        WriteItemObject(arrayDir.Name, parentPath + ProviderSep + arrayDir.Name, true);
                    }
                }

                // Nested bucket subdirectories
                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ArraysDir && d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    if (IsBucketDirectory(subDir.FullName))
                    {
                        string subLogical = subDir.FullName.Substring(root.Length).TrimStart(Sep).Replace(Sep, ProviderSep);
                        WriteItemObject(subDir.Name, PSDriveInfo.Name + ":" + ProviderSep + subLogical, true);
                    }
                }
            }
            else if (IsArrayDirectory(physical))
            {
                string bucketName = GetBucketNameFromPhysical(physical, root);
                string arrayName = di.Name;
                string parentPath = PSDriveInfo.Name + ":" + ProviderSep + bucketName.Replace(Sep, ProviderSep) + ProviderSep + arrayName;

                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, parentPath + ProviderSep + name, false);
                }
            }
            else
            {
                string relativePhysical = physical.Substring(root.Length).TrimStart(Sep, '/', '\\');
                string relativeLogical = relativePhysical.Replace('/', ProviderSep).Replace('\\', ProviderSep);
                string prefix = PSDriveInfo.Name + ":" + ProviderSep + relativeLogical;

                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    WriteItemObject(subDir.Name, prefix + ProviderSep + subDir.Name, true);
                }

                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, prefix + ProviderSep + name, false);
                }
            }
        }

        protected override bool HasChildItems(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !Directory.Exists(physical)) return false;

            var di = new DirectoryInfo(physical);
            string root = GetPhysicalRoot();
            bool isDriveRoot = IsDriveRoot(physical, root);
            bool isBucket = IsBucketDirectory(physical);

            if (isDriveRoot)
            {
                return di.GetDirectories().Any(d => d.Name != ".buckets");
            }

            if (isBucket)
            {
                if (di.GetFiles("*.dat").Length > 0 || di.GetFiles("*.json").Length > 0) return true;
                string arraysPath = Path.Combine(physical, ArraysDir);
                if (Directory.Exists(arraysPath) && new DirectoryInfo(arraysPath).GetDirectories().Length > 0) return true;
                return di.GetDirectories().Any(d => d.Name != ArraysDir && d.Name != ".buckets");
            }

            return di.GetFiles("*.dat").Length > 0 ||
                   di.GetFiles("*.json").Length > 0 ||
                   di.GetDirectories().Length > 0;
        }

        #endregion

        #region Navigation

        protected override string GetChildName(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";

            string physRoot = GetPhysicalRoot();
            if (path.StartsWith(physRoot, StringComparison.OrdinalIgnoreCase))
            {
                path = ToLogicalPath(path);
            }

            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            string driveName = PSDriveInfo.Name + ":";
            if (cleaned.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(driveName.Length);
            }
            cleaned = cleaned.TrimStart(ProviderSep, '/', '\\');

            if (string.IsNullOrEmpty(cleaned)) return "";

            int sep = cleaned.LastIndexOf(ProviderSep);
            if (sep < 0) sep = cleaned.LastIndexOf('/');
            if (sep < 0) sep = cleaned.LastIndexOf('\\');
            return sep < 0 ? cleaned : cleaned.Substring(sep + 1);
        }

        protected override string MakePath(string parent, string child)
        {
            if (string.IsNullOrEmpty(parent)) return child ?? "";
            if (string.IsNullOrEmpty(child)) return parent;

            string driveName = PSDriveInfo.Name + ":";
            string physRoot = GetPhysicalRoot();

            // Convert physical paths to logical first
            if (parent.StartsWith(physRoot, StringComparison.OrdinalIgnoreCase))
            {
                parent = ToLogicalPath(parent);
                parent = driveName + ProviderSep + parent;
            }

            string normalized = parent.TrimEnd(ProviderSep, '/', '\\');
            if (child == ".") return normalized;
            if (child == "..")
            {
                if (normalized.EndsWith(driveName, StringComparison.OrdinalIgnoreCase) && normalized.Length == driveName.Length)
                {
                    return normalized;
                }
                int lastSep = normalized.LastIndexOf(ProviderSep);
                if (lastSep < 0) lastSep = normalized.LastIndexOf('/');
                if (lastSep < 0) return normalized;
                normalized = normalized.Substring(0, lastSep);
                if (string.IsNullOrEmpty(normalized)) return driveName;
                return normalized;
            }

            // Clamp ".." parent to drive root
            if (normalized == "..")
            {
                return driveName + ProviderSep + child;
            }

            // If child is already fully qualified, return it as-is
            if (child.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                return child;
            }

            if (normalized.EndsWith(":", StringComparison.OrdinalIgnoreCase))
            {
                return normalized + ProviderSep + child;
            }

            return normalized + ProviderSep + child;
        }

        protected override string GetParentPath(string path, string root)
        {
            string driveName = PSDriveInfo.Name + ":";
            string physRoot = GetPhysicalRoot();

            // Convert physical paths to logical first
            if (path.StartsWith(physRoot, StringComparison.OrdinalIgnoreCase))
            {
                path = ToLogicalPath(path);
                path = driveName + ProviderSep + path;
            }

            // Normalize separators to forward slash (consistent across platforms)
            char sep = '/';
            string normalized = path.Replace('\\', sep);

            // Check if the path is just a separator or empty (drive root)
            string trimmedNorm = normalized.TrimEnd(sep).TrimStart(sep);
            if (string.IsNullOrEmpty(trimmedNorm))
            {
                // At drive root - return the root path as-is
                string rootPath = root ?? "";
                if (!string.IsNullOrEmpty(rootPath) && !rootPath.EndsWith(sep.ToString()))
                {
                    rootPath = rootPath + sep;
                }
                return rootPath.Replace('\\', sep);
            }

            // Ensure root has trailing separator
            string rootPath2 = root ?? "";
            if (!string.IsNullOrEmpty(rootPath2) && !rootPath2.EndsWith(sep.ToString()))
            {
                rootPath2 = rootPath2 + sep;
            }
            rootPath2 = rootPath2.Replace('\\', sep);

            // Check if path equals root
            string trimmedNormalized = normalized.TrimEnd(sep);
            string trimmedRoot = rootPath2.TrimEnd(sep);
            if (string.Equals(trimmedNormalized, trimmedRoot, StringComparison.OrdinalIgnoreCase))
            {
                return rootPath2;
            }

            // Find the last separator and return everything before it
            int lastIndex = trimmedNormalized.LastIndexOf(sep);

            if (lastIndex != -1)
            {
                if (lastIndex == 0) ++lastIndex;
                return trimmedNormalized.Substring(0, lastIndex);
            }

            return rootPath2;
        }

        protected override string NormalizeRelativePath(string path, string basePath)
        {
            if (string.IsNullOrEmpty(path)) return basePath ?? "";

            string drivePrefix = PSDriveInfo.Name + ":";
            string root = GetPhysicalRoot();

            // Handle physical filesystem paths - convert to logical
            if (path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                string logical = ToLogicalPath(path);
                path = drivePrefix + ProviderSep + logical;
            }

            // Handle provider-qualified paths like "buckets:/../something" or "buckets:\something"
            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);

            // Strip drive prefix
            if (cleaned.StartsWith(drivePrefix, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(drivePrefix.Length);
            }
            cleaned = cleaned.TrimStart(ProviderSep, '/', '\\');

            // Also normalize basePath to get its relative portion
            string cleanedBase = basePath ?? "";
            int baseColonColon = cleanedBase.IndexOf("::", StringComparison.Ordinal);
            if (baseColonColon >= 0) cleanedBase = cleanedBase.Substring(baseColonColon + 2);
            if (cleanedBase.StartsWith(drivePrefix, StringComparison.OrdinalIgnoreCase))
            {
                cleanedBase = cleanedBase.Substring(drivePrefix.Length);
            }
            cleanedBase = cleanedBase.TrimStart(ProviderSep, '/', '\\');

            // Strip basePath from path to get the truly relative portion
            if (!string.IsNullOrEmpty(cleanedBase) && cleaned.StartsWith(cleanedBase, StringComparison.OrdinalIgnoreCase))
            {
                string afterBase = cleaned.Substring(cleanedBase.Length);
                cleaned = afterBase.TrimStart(ProviderSep, '/', '\\');
            }

            // Remove . and .. segments (clamp to root)
            string[] parts = cleaned.Split(new[] { ProviderSep, '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
            var stack = new System.Collections.Generic.List<string>();
            foreach (var part in parts)
            {
                if (part == "." || part == "..") continue;
                stack.Add(part);
            }

            return string.Join(ProviderSep.ToString(), stack);
        }

        #endregion

        #region Write Operations

        protected override void NewItem(string path, string itemTypeName, object newItemValue)
        {
            if (string.IsNullOrEmpty(path))
            {
                WriteError(new ErrorRecord(new ArgumentException("Path cannot be empty."),
                    "EmptyPath", ErrorCategory.InvalidArgument, path));
                return;
            }

            if (!ShouldProcess(path, "New Item")) return;

            string physical = ToPhysicalPath(path);
            bool wantContainer = string.Equals(itemTypeName, "directory", StringComparison.OrdinalIgnoreCase);

            if (physical == null)
            {
                string root = GetPhysicalRoot();
                string logical = path;

                int colonColon = logical.IndexOf("::", StringComparison.Ordinal);
                if (colonColon >= 0) logical = logical.Substring(colonColon + 2);

                string driveName = PSDriveInfo.Name + ":";
                if (logical.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
                {
                    logical = logical.Substring(driveName.Length);
                }
                logical = logical.TrimStart(Sep, '/', '\\', ' ');
                if (!string.IsNullOrEmpty(logical))
                {
                    logical = logical.Replace('/', Sep).Replace('\\', Sep);
                    physical = Path.Combine(root, logical);
                }
            }

            if (wantContainer)
            {
                if (!Directory.Exists(physical))
                {
                    Directory.CreateDirectory(physical);
                }
                WriteItemObject(new BucketItemInfo
                {
                    Name = GetChildName(path),
                    IsContainer = true,
                    ItemKind = "bucket",
                    ItemCount = 0,
                    Format = "",
                    SizeBytes = 0,
                    PhysicalPath = physical,
                    LastWriteTime = DateTime.Now,
                    CreationTime = DateTime.Now
                }, ToLogicalPath(physical), true);
            }
            else
            {
                string format = "binary";
                if (!string.IsNullOrEmpty(itemTypeName) && itemTypeName.Equals("json", StringComparison.OrdinalIgnoreCase))
                {
                    format = "json";
                }

                string ext = format == "json" ? ".json" : ".dat";
                if (string.IsNullOrEmpty(Path.GetExtension(physical)))
                {
                    physical = Path.ChangeExtension(physical, ext);
                }

                string dir = Path.GetDirectoryName(physical);
                string key = Path.GetFileNameWithoutExtension(physical);
                string sanitizedKey = SanitizeKey(key);

                if (string.IsNullOrEmpty(sanitizedKey))
                {
                    WriteError(new ErrorRecord(new ArgumentException("Key is empty after sanitization."),
                        "EmptyKey", ErrorCategory.InvalidArgument, path));
                    return;
                }

                physical = Path.Combine(dir, sanitizedKey + ext);

                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                if (File.Exists(physical))
                {
                    WriteError(new ErrorRecord(new IOException($"Item already exists: {ToLogicalPath(physical)}"),
                        "ItemAlreadyExists", ErrorCategory.ResourceExists, path));
                    return;
                }

                SerializeFile(newItemValue, physical, format);
                var fi = new FileInfo(physical);
                WriteItemObject(new BucketItemInfo
                {
                    Name = sanitizedKey,
                    IsContainer = false,
                    ItemKind = "object",
                    ItemCount = 0,
                    Format = format == "json" ? "JSON" : "Binary",
                    SizeBytes = fi.Length,
                    PhysicalPath = physical,
                    LastWriteTime = fi.LastWriteTime,
                    CreationTime = fi.CreationTime
                }, ToLogicalPath(physical), false);
            }
        }

        protected override void SetItem(string path, object value)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null)
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Item not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            if (Directory.Exists(physical))
            {
                WriteError(new ErrorRecord(new InvalidOperationException("Cannot set value on a container."),
                    "ContainerSetError", ErrorCategory.InvalidOperation, path));
                return;
            }

            try
            {
                DeserializeFile(physical, out string format, out _);
                object existing = DeserializeFile(physical, out _, out _);
                object merged = MergeObjects(existing, value);
                SerializeFile(merged, physical, format);

                object updated = DeserializeFile(physical, out _, out _);
                var fi = new FileInfo(physical);
                WriteItemObject(new BucketObjectInfo
                {
                    LogicalPath = ToLogicalPath(physical),
                    PhysicalPath = physical,
                    Key = GetKeyName(path),
                    Bucket = GetBucketName(path),
                    Format = format,
                    Compressed = false,
                    SizeBytes = fi.Length,
                    Modified = fi.LastWriteTime,
                    Content = updated
                }, ToLogicalPath(physical), false);
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(new RuntimeException($"Failed to set item: {ex.Message}"),
                    "SetItemFailed", ErrorCategory.WriteError, path));
            }
        }

        private object MergeObjects(object existing, object newValue)
        {
            var existingDict = ToDictionary(existing);

            if (newValue is IDictionary newDict)
            {
                foreach (DictionaryEntry entry in newDict)
                {
                    existingDict[entry.Key?.ToString() ?? ""] = entry.Value;
                }
                return existingDict;
            }

            var psoNew = newValue as PSObject;
            if (psoNew != null)
            {
                foreach (var prop in psoNew.Properties.Where(p => p.IsGettable))
                {
                    existingDict[prop.Name] = prop.Value;
                }
                return existingDict;
            }

            return newValue;
        }

        private Dictionary<string, object> ToDictionary(object value)
        {
            var result = new Dictionary<string, object>();

            if (value is IDictionary dict)
            {
                foreach (DictionaryEntry entry in dict)
                {
                    result[entry.Key?.ToString() ?? ""] = entry.Value;
                }
                return result;
            }

            var pso = value as PSObject;
            if (pso != null)
            {
                if (pso.BaseObject is IDictionary baseDict)
                {
                    foreach (DictionaryEntry entry in baseDict)
                    {
                        result[entry.Key?.ToString() ?? ""] = entry.Value;
                    }
                    return result;
                }

                var skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                {
                    "Equals", "GetHashCode", "GetType", "ToString",
                    "pstypenames", "psadapted", "psbase", "psextended", "psobject"
                };
                foreach (var prop in pso.Properties.Where(p => p.IsGettable && !skip.Contains(p.Name)))
                {
                    result[prop.Name] = prop.Value;
                }

                return result;
            }

            return result;
        }

        protected override void RemoveItem(string path, bool recurse)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null)
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Item not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            if (!ShouldProcess(path, "Remove Item")) return;

            if (File.Exists(physical))
            {
                File.Delete(physical);
            }
            else if (Directory.Exists(physical))
            {
                if (!IsSafeBucketDirectory(physical))
                {
                    WriteWarning($"Bucket '{path}' contains non-bucket files. Refusing to remove.");
                    return;
                }
                Directory.Delete(physical, true);
            }
        }

        private bool IsSafeBucketDirectory(string path)
        {
            var di = new DirectoryInfo(path);
            foreach (var file in di.GetFiles())
            {
                string ext = file.Extension.ToLowerInvariant();
                if (ext != ".dat" && ext != ".json") return false;
            }
            foreach (var subDir in di.GetDirectories())
            {
                if (subDir.Name == ArraysDir)
                {
                    foreach (var subSubDir in subDir.GetDirectories())
                    {
                        foreach (var file in subSubDir.GetFiles())
                        {
                            string ext = file.Extension.ToLowerInvariant();
                            if (ext != ".dat" && ext != ".json") return false;
                        }
                    }
                }
                else if (!IsBucketDirectory(subDir.FullName))
                {
                    // Subdirectory that is not .arrays/ and not a bucket itself
                    return false;
                }
                // If it is a bucket subdirectory, that's OK - nested buckets are safe
            }
            return true;
        }

        protected override void MoveItem(string path, string destination)
        {
            string srcPhysical = ToPhysicalPath(path);
            if (srcPhysical == null)
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Source not found: {path}"),
                    "SourceNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            string destPhysical = ToPhysicalPath(destination);
            if (destPhysical != null && Directory.Exists(destPhysical))
            {
                destPhysical = Path.Combine(destPhysical, Path.GetFileName(srcPhysical));
            }
            else if (destPhysical == null)
            {
                string root = GetPhysicalRoot();
                string logical = destination;
                int colonColon = logical.IndexOf("::", StringComparison.Ordinal);
                if (colonColon >= 0) logical = logical.Substring(colonColon + 2);
                string driveName = PSDriveInfo.Name + ":";
                if (logical.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
                {
                    logical = logical.Substring(driveName.Length);
                }
                logical = logical.TrimStart(Sep, '/', '\\', ' ');
                if (!string.IsNullOrEmpty(logical))
                {
                    logical = logical.Replace('/', Sep).Replace('\\', Sep);
                    destPhysical = Path.Combine(root, logical);
                }

                if (File.Exists(srcPhysical))
                {
                    string ext = Path.GetExtension(srcPhysical);
                    if (string.IsNullOrEmpty(Path.GetExtension(destPhysical)))
                    {
                        destPhysical = Path.ChangeExtension(destPhysical, ext);
                    }
                }
            }

            if (!ShouldProcess($"{path} -> {destination}", "Move Item")) return;

            string destDir = Path.GetDirectoryName(destPhysical);
            if (!Directory.Exists(destDir)) Directory.CreateDirectory(destDir);

            if (File.Exists(srcPhysical)) File.Move(srcPhysical, destPhysical);
            else if (Directory.Exists(srcPhysical)) Directory.Move(srcPhysical, destPhysical);
        }

        protected override void CopyItem(string path, string destination, bool recurse)
        {
            string srcPhysical = ToPhysicalPath(path);
            if (srcPhysical == null)
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Source not found: {path}"),
                    "SourceNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            string destPhysical = ToPhysicalPath(destination);
            if (destPhysical != null && Directory.Exists(destPhysical))
            {
                destPhysical = Path.Combine(destPhysical, Path.GetFileName(srcPhysical));
            }
            else if (destPhysical == null)
            {
                string root = GetPhysicalRoot();
                string logical = destination;
                int colonColon = logical.IndexOf("::", StringComparison.Ordinal);
                if (colonColon >= 0) logical = logical.Substring(colonColon + 2);
                string driveName = PSDriveInfo.Name + ":";
                if (logical.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
                {
                    logical = logical.Substring(driveName.Length);
                }
                logical = logical.TrimStart(Sep, '/', '\\', ' ');
                if (!string.IsNullOrEmpty(logical))
                {
                    logical = logical.Replace('/', Sep).Replace('\\', Sep);
                    destPhysical = Path.Combine(root, logical);
                }

                if (File.Exists(srcPhysical))
                {
                    string ext = Path.GetExtension(srcPhysical);
                    if (string.IsNullOrEmpty(Path.GetExtension(destPhysical)))
                    {
                        destPhysical = Path.ChangeExtension(destPhysical, ext);
                    }
                }
            }

            if (!ShouldProcess($"{path} -> {destination}", "Copy Item")) return;

            if (File.Exists(srcPhysical))
            {
                string destDir = Path.GetDirectoryName(destPhysical);
                if (!Directory.Exists(destDir)) Directory.CreateDirectory(destDir);
                File.Copy(srcPhysical, destPhysical, true);
            }
            else if (Directory.Exists(srcPhysical))
            {
                CopyDirectory(srcPhysical, destPhysical, recurse);
            }
        }

        private void CopyDirectory(string source, string destination, bool recurse)
        {
            if (!Directory.Exists(destination)) Directory.CreateDirectory(destination);
            var di = new DirectoryInfo(source);
            foreach (var file in di.GetFiles()) file.CopyTo(Path.Combine(destination, file.Name), true);
            if (recurse)
            {
                foreach (var subDir in di.GetDirectories())
                {
                    CopyDirectory(subDir.FullName, Path.Combine(destination, subDir.Name), recurse);
                }
            }
        }

        protected override void RenameItem(string path, string newName)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null)
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Item not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            string sanitized = SanitizeKey(newName);
            if (string.IsNullOrEmpty(sanitized))
            {
                WriteError(new ErrorRecord(new ArgumentException("New name is empty after sanitization."),
                    "EmptyName", ErrorCategory.InvalidArgument, newName));
                return;
            }

            if (!ShouldProcess($"{path} -> {newName}", "Rename Item")) return;

            string parent = Path.GetDirectoryName(physical);
            string newNameWithExt = File.Exists(physical) ? sanitized + Path.GetExtension(physical) : sanitized;
            string newPhysical = Path.Combine(parent, newNameWithExt);

            if (File.Exists(newPhysical) || Directory.Exists(newPhysical))
            {
                WriteError(new ErrorRecord(new IOException($"Target already exists: {newNameWithExt}"),
                    "TargetExists", ErrorCategory.ResourceExists, newName));
                return;
            }

            File.Move(physical, newPhysical);
        }

        #endregion

        #region Content Cmdlet Provider

        public IContentReader GetContentReader(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !File.Exists(physical))
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Object not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return null;
            }

            if (Directory.Exists(physical))
            {
                WriteError(new ErrorRecord(new InvalidOperationException("Get-Content cannot be used on a bucket directory. Use Get-Item to retrieve objects."),
                    "NotAnObject", ErrorCategory.InvalidType, path));
                return null;
            }

            return new BucketContentReader(physical, this);
        }

        public IContentWriter GetContentWriter(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null)
            {
                physical = ResolveNewObjectPath(path);
                if (physical == null)
                {
                    WriteError(new ErrorRecord(new ItemNotFoundException($"Cannot resolve path: {path}"),
                        "PathNotFound", ErrorCategory.ObjectNotFound, path));
                    return null;
                }
            }

            if (Directory.Exists(physical))
            {
                WriteError(new ErrorRecord(new InvalidOperationException("Set-Content cannot be used on a bucket directory."),
                    "NotAnObject", ErrorCategory.InvalidType, path));
                return null;
            }

            return new BucketContentWriter(physical, this);
        }

        public void ClearContent(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !File.Exists(physical))
            {
                WriteError(new ErrorRecord(new ItemNotFoundException($"Object not found: {path}"),
                    "ItemNotFound", ErrorCategory.ObjectNotFound, path));
                return;
            }

            if (ShouldProcess($"Clear content of {path}", "Clear-Content"))
            {
                File.Delete(physical);
            }
        }

        public object GetContentReaderDynamicParameters(string path) => null;
        public object GetContentWriterDynamicParameters(string path) => null;
        public object ClearContentDynamicParameters(string path) => null;

        private string ResolveNewObjectPath(string path)
        {
            string root = GetPhysicalRoot();

            string driveName = PSDriveInfo.Name + ":";
            if (path.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                path = path.Substring(driveName.Length);
            }

            path = path.TrimStart(Sep, '/', '\\');
            if (string.IsNullOrEmpty(path)) return null;

            string normalized = path.Replace('/', Sep).Replace('\\', Sep);
            string[] parts = normalized.Split(new[] { Sep }, StringSplitOptions.RemoveEmptyEntries);

            // Last part is the key, rest is the bucket path
            if (parts.Length < 2) return null;

            string bucketPath = root;
            for (int i = 0; i < parts.Length - 1; i++)
            {
                bucketPath = Path.Combine(bucketPath, parts[i]);
            }

            string key = parts[parts.Length - 1];
            string sanitized = SanitizeKey(key);
            if (string.IsNullOrEmpty(sanitized)) return null;

            if (!Directory.Exists(bucketPath))
            {
                Directory.CreateDirectory(bucketPath);
            }

            // Default to .dat if no extension specified
            string ext = Path.GetExtension(sanitized);
            if (string.IsNullOrEmpty(ext))
            {
                // Check if bucket has .json files
                var jsonCount = new DirectoryInfo(bucketPath).GetFiles("*.json").Length;
                var datCount = new DirectoryInfo(bucketPath).GetFiles("*.dat").Length;
                ext = jsonCount > datCount ? ".json" : ".dat";
                sanitized = sanitized + ext;
            }

            return Path.Combine(bucketPath, sanitized);
        }

        #endregion
    }

    public class BucketContentReader : IContentReader
    {
        private readonly string _physicalPath;
        private readonly BucketsProvider _provider;
        private bool _read;

        public BucketContentReader(string physicalPath, BucketsProvider provider)
        {
            _physicalPath = physicalPath;
            _provider = provider;
            _read = false;
        }

        public IList Read(long readCount)
        {
            if (_read) return new object[0];
            _read = true;

            try
            {
                object content = _provider.DeserializeFileInternal(_physicalPath, out _, out _);
                return new object[] { content };
            }
            catch (Exception ex)
            {
                _provider.WriteError(new ErrorRecord(
                    new RuntimeException($"Failed to read content: {ex.Message}"),
                    "ReadError", ErrorCategory.ReadError, _physicalPath));
                return new object[0];
            }
        }

        public void Seek(long offset, SeekOrigin origin)
        {
            // Object storage doesn't support seeking
        }

        public void Close()
        {
        }

        public void Dispose()
        {
        }
    }

    public class BucketContentWriter : IContentWriter
    {
        private readonly string _physicalPath;
        private readonly BucketsProvider _provider;
        private readonly System.Collections.Generic.List<object> _buffer;

        public BucketContentWriter(string physicalPath, BucketsProvider provider)
        {
            _physicalPath = physicalPath;
            _provider = provider;
            _buffer = new System.Collections.Generic.List<object>();
        }

        public IList Write(IList items)
        {
            if (items != null)
            {
                foreach (var item in items)
                {
                    _buffer.Add(item);
                }
            }
            return new object[0];
        }

        public void Seek(long offset, SeekOrigin origin)
        {
            // Object storage doesn't support seeking
        }

        public void Close()
        {
            if (_buffer.Count == 0) return;

            try
            {
                object value = _buffer.Count == 1 ? _buffer[0] : _buffer.ToArray();
                string ext = Path.GetExtension(_physicalPath).ToLowerInvariant();
                string format = ext == ".json" ? "json" : "binary";

                string dir = Path.GetDirectoryName(_physicalPath);
                if (!Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                _provider.SerializeFileInternal(value, _physicalPath, format);
            }
            catch (Exception ex)
            {
                _provider.WriteError(new ErrorRecord(
                    new RuntimeException($"Failed to write content: {ex.Message}"),
                    "WriteError", ErrorCategory.WriteError, _physicalPath));
            }
        }

        public void Dispose()
        {
            Close();
        }
    }
}
