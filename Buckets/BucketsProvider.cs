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
        public string Mode
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
        public long? Length => IsContainer ? (long?)null : SizeBytes;
        public string Name { get; set; }

        // Internal use only
        internal bool IsContainer { get; set; }
        internal string ItemKind { get; set; } // "bucket", "array", "object"
        internal int ItemCount { get; set; }
        internal string Format { get; set; }
        internal long SizeBytes { get; set; }
        internal string PhysicalPath { get; set; }
    }

    [CmdletProvider("Buckets", ProviderCapabilities.ShouldProcess)]
    public class BucketsProvider : NavigationCmdletProvider
    {
        private static readonly char[] InvalidChars = { '/', ':', '*', '?', '"', '<', '>', '|', '.', '[', ']' };
        private static readonly byte[] GZipMagic = { 0x1F, 0x8B };
        private static readonly char ProviderSep = '\\';
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
            var newDrive = new PSDriveInfo(drive.Name, this.ProviderInfo, drive.Name + ":", drive.Description, drive.Credential);
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
        /// Flattens .arrays/: bucket/arrayname resolves to bucket/.arrays/arrayname
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
                if (part == "..") continue; // Clamp to root - ignore .. at drive level
                parts.Add(part);
            }

            if (parts.Count == 1)
            {
                // Single part: bucket name
                string physical = Path.Combine(root, parts[0]);
                if (Directory.Exists(physical)) return physical;
                return null;
            }

            // Two parts: bucket/arrayname -> bucket/.arrays/arrayname
            if (parts.Count == 2)
            {
                // First try: bucket/arrayname/.arrays/arrayname (array dir with items)
                string arrayDir = Path.Combine(root, parts[0], ArraysDir, parts[1]);
                if (Directory.Exists(arrayDir)) return arrayDir;

                // Second try: bucket/arrayname.dat (object in bucket root)
                string objFile = Path.Combine(root, parts[0], parts[1]);
                if (File.Exists(objFile)) return objFile;
                string datFile = objFile + ".dat";
                if (File.Exists(datFile)) return datFile;
                string jsonFile = objFile + ".json";
                if (File.Exists(jsonFile)) return jsonFile;

                // Third try: plain directory (bucket itself, or legacy)
                string bucketDir = Path.Combine(root, parts[0]);
                if (Directory.Exists(bucketDir))
                {
                    string subDir = Path.Combine(bucketDir, parts[1]);
                    if (Directory.Exists(subDir)) return subDir;
                }

                return null;
            }

            // Three+ parts: bucket/arrayname/item or bucket/subdir/item
            if (parts.Count >= 3)
            {
                // If second part looks like an array path, insert .arrays/
                string withArrays = Path.Combine(root, parts[0], ArraysDir);
                for (int i = 1; i < parts.Count; i++)
                {
                    withArrays = Path.Combine(withArrays, parts[i]);
                }
                if (Directory.Exists(withArrays)) return withArrays;
                if (File.Exists(withArrays)) return withArrays;
                string datPath = withArrays + ".dat";
                if (File.Exists(datPath)) return datPath;
                string jsonPath = withArrays + ".json";
                if (File.Exists(jsonPath)) return jsonPath;

                // Fall back to direct path
                string direct = Path.Combine(root, path);
                if (Directory.Exists(direct)) return direct;
                if (File.Exists(direct)) return direct;
            }

            return null;
        }

        /// <summary>
        /// Convert a physical filesystem path to a provider-logical path.
        /// Strips .arrays/ from the path for a flattened view.
        /// </summary>
        private string ToLogicalPath(string physicalPath)
        {
            string root = GetPhysicalRoot();
            if (!physicalPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                return physicalPath;
            }

            string relative = physicalPath.Substring(root.Length).TrimStart(Sep);

            // Strip .arrays/ from the path (flattening)
            string arraysPrefix = ArraysDir + Sep;
            if (relative.StartsWith(arraysPrefix, StringComparison.OrdinalIgnoreCase))
            {
                // bucket/.arrays/arrayname -> bucket/arrayname
                relative = relative.Substring(arraysPrefix.Length);
                string[] parts = relative.Split(new[] { Sep }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length >= 1)
                {
                    // We need the bucket name - find it from the physical path
                    string bucketName = GetBucketNameFromPhysical(physicalPath, root);
                    if (parts.Length == 1)
                    {
                        relative = bucketName + ProviderSep + parts[0];
                    }
                    else
                    {
                        relative = bucketName + ProviderSep + string.Join(ProviderSep.ToString(), parts);
                    }
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
        /// Extract bucket name from a physical path by walking up from root.
        /// </summary>
        private string GetBucketNameFromPhysical(string physicalPath, string root)
        {
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
        /// Determine if a physical directory is at the bucket root level (direct child of drive root).
        /// </summary>
        private bool IsBucketRoot(string physicalDir, string root)
        {
            string relative = physicalDir.Substring(root.Length).TrimStart(Sep);
            // Root itself has empty relative path; bucket roots have exactly one segment
            return !string.IsNullOrEmpty(relative) && !relative.Contains(Sep.ToString());
        }

        /// <summary>
        /// Determine if we're at the drive root (not inside any bucket).
        /// </summary>
        private bool IsDriveRoot(string physicalDir, string root)
        {
            return string.Equals(Path.GetFullPath(physicalDir), Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase);
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
                bool isBucketRoot = IsBucketRoot(physical, root);
                bool isArrayDir = IsArrayDirectory(physical);

                string itemKind;
                if (isDriveRoot) itemKind = "bucket"; // Drive root itself
                else if (isBucketRoot) itemKind = "bucket";
                else if (isArrayDir) itemKind = "array";
                else itemKind = "bucket";

                var di = new DirectoryInfo(physical);
                var files = di.GetFiles("*.dat").Concat(di.GetFiles("*.json"));
                var dirs = di.GetDirectories().Where(d => d.Name != ".buckets");
                int arrayCount = 0;
                if (isDriveRoot || isBucketRoot)
                {
                    string arraysPath = isDriveRoot ? "" : Path.Combine(physical, ArraysDir);
                    // For drive root, count arrays across all buckets
                    if (isDriveRoot)
                    {
                        foreach (var bucketDir in dirs)
                        {
                            string bucketArrays = Path.Combine(bucketDir.FullName, ArraysDir);
                            if (Directory.Exists(bucketArrays))
                            {
                                arrayCount += new DirectoryInfo(bucketArrays).GetDirectories().Length;
                            }
                        }
                    }
                    else
                    {
                        arrayCount = Directory.Exists(arraysPath) ? new DirectoryInfo(arraysPath).GetDirectories().Length : 0;
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
                    SizeBytes = 0,
                    PhysicalPath = physical,
                    LastWriteTime = di.LastWriteTime
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
            bool isBucketRoot = IsBucketRoot(directory, root);

            if (isDriveRoot)
            {
                // At drive root: show bucket directories (b--)
                foreach (var bucketDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    var files = bucketDir.GetFiles("*.dat").Concat(bucketDir.GetFiles("*.json"));
                    var arraysPath = Path.Combine(bucketDir.FullName, ArraysDir);
                    int arrayCount = Directory.Exists(arraysPath) ? new DirectoryInfo(arraysPath).GetDirectories().Length : 0;
                    int count = files.Count() + arrayCount;

                    WriteItemObject(new BucketItemInfo
                    {
                        Name = bucketDir.Name,
                        IsContainer = true,
                        ItemKind = "bucket",
                        ItemCount = count,
                        Format = "",
                        SizeBytes = 0,
                        PhysicalPath = bucketDir.FullName,
                        LastWriteTime = bucketDir.LastWriteTime
                    }, bucketDir.Name, true);

                    if (recurse)
                    {
                        currentDepth++;
                        EnumerateDirectory(bucketDir.FullName, recurse, depthLimit, ref currentDepth);
                        currentDepth--;
                    }
                }
            }
            else if (isBucketRoot)
            {
                // At bucket root: show regular files (objects) and array dirs (from .arrays/)
                // Hide .arrays/ itself

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
                        LastWriteTime = file.LastWriteTime
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

                        // Logical path: bucket/arrayname (not bucket/.arrays/arrayname)
                        string logical = di.Name + Sep + arrayDir.Name;

                        WriteItemObject(new BucketItemInfo
                        {
                            Name = arrayDir.Name,
                            IsContainer = true,
                            ItemKind = "array",
                            ItemCount = count,
                            Format = "",
                            SizeBytes = 0,
                            PhysicalPath = arrayDir.FullName,
                            LastWriteTime = arrayDir.LastWriteTime
                        }, logical, true);

                        if (recurse)
                        {
                            currentDepth++;
                            EnumerateDirectory(arrayDir.FullName, recurse, depthLimit, ref currentDepth);
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
                        LastWriteTime = file.LastWriteTime
                    }, logical, false);
                }
            }
            else
            {
                // General subdirectory (not bucket root, not array): show contents normally
                foreach (var subDir in di.GetDirectories().OrderBy(d => d.Name))
                {
                    if (subDir.Name == ".buckets") continue;

                    var files = subDir.GetFiles("*.dat").Concat(subDir.GetFiles("*.json"));
                    var subDirs = subDir.GetDirectories().Where(d => d.Name != ".buckets");
                    int count = files.Count() + subDirs.Count();

                    string logical = ToLogicalPath(subDir.FullName);
                    WriteItemObject(new BucketItemInfo
                    {
                        Name = subDir.Name,
                        IsContainer = true,
                        ItemKind = "bucket",
                        ItemCount = count,
                        Format = "",
                        SizeBytes = 0,
                        PhysicalPath = subDir.FullName,
                        LastWriteTime = subDir.LastWriteTime
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
                        LastWriteTime = file.LastWriteTime
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
            bool isBucketRoot = IsBucketRoot(physical, root);

            if (isDriveRoot)
            {
                foreach (var bucketDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    WriteItemObject(bucketDir.Name, bucketDir.Name, true);
                }
            }
            else if (isBucketRoot)
            {
                string bucketName = di.Name;

                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, name, false);
                }

                string arraysPath = Path.Combine(physical, ArraysDir);
                if (Directory.Exists(arraysPath))
                {
                    var arraysDir = new DirectoryInfo(arraysPath);
                    foreach (var arrayDir in arraysDir.GetDirectories().OrderBy(d => d.Name))
                    {
                        WriteItemObject(arrayDir.Name, arrayDir.Name, true);
                    }
                }
            }
            else if (IsArrayDirectory(physical))
            {
                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, name, false);
                }
            }
            else
            {
                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    WriteItemObject(subDir.Name, subDir.Name, true);
                }

                foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
                {
                    string name = Path.GetFileNameWithoutExtension(file.Name);
                    WriteItemObject(name, name, false);
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
            bool isBucketRoot = IsBucketRoot(physical, root);

            if (isDriveRoot)
            {
                return di.GetDirectories().Any(d => d.Name != ".buckets");
            }

            if (isBucketRoot)
            {
                // Has files or arrays
                if (di.GetFiles("*.dat").Length > 0 || di.GetFiles("*.json").Length > 0) return true;
                string arraysPath = Path.Combine(physical, ArraysDir);
                return Directory.Exists(arraysPath) && new DirectoryInfo(arraysPath).GetDirectories().Length > 0;
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

            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            if (cleaned.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(driveName.Length);
            }
            cleaned = cleaned.TrimStart(ProviderSep, '/', '\\');

            if (string.IsNullOrEmpty(cleaned)) return driveName;

            int sep = cleaned.LastIndexOf(ProviderSep);
            if (sep < 0) sep = cleaned.LastIndexOf('/');
            if (sep < 0) sep = cleaned.LastIndexOf('\\');
            if (sep < 0) return driveName;

            string parentRel = cleaned.Substring(0, sep);
            return string.IsNullOrEmpty(parentRel) ? driveName : (driveName + ProviderSep + parentRel);
        }

        protected override string NormalizeRelativePath(string path, string basePath)
        {
            if (string.IsNullOrEmpty(path)) return basePath ?? "";

            string drivePrefix = PSDriveInfo.Name + ":";
            string root = GetPhysicalRoot();

            // Convert physical paths to logical first
            if (path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                return ToLogicalPath(path);
            }

            // Clean up provider-qualified paths
            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            if (cleaned.StartsWith(drivePrefix, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(drivePrefix.Length);
            }
            cleaned = cleaned.TrimStart(ProviderSep, '/', '\\');

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
                    LastWriteTime = DateTime.Now
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
                    LastWriteTime = fi.LastWriteTime
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
                if (subDir.Name != ".arrays") return false;
                foreach (var subSubDir in subDir.GetDirectories())
                {
                    foreach (var file in subSubDir.GetFiles())
                    {
                        string ext = file.Extension.ToLowerInvariant();
                        if (ext != ".dat" && ext != ".json") return false;
                    }
                }
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
    }
}
