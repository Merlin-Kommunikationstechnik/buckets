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
        public string Name { get; set; }
        public bool IsContainer { get; set; }
        public int ItemCount { get; set; }
        public string Format { get; set; }
        public long SizeBytes { get; set; }
        public string PhysicalPath { get; set; }
    }

    [CmdletProvider("Buckets", ProviderCapabilities.ShouldProcess)]
    public class BucketsProvider : NavigationCmdletProvider
    {
        private static readonly char[] InvalidChars = { '/', ':', '*', '?', '"', '<', '>', '|', '.', '[', ']' };
        private static readonly byte[] GZipMagic = { 0x1F, 0x8B };
        private static readonly char Sep = Path.DirectorySeparatorChar;

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

            // Return PSDriveInfo with drive name as logical root, store physical root separately
            // This ensures all navigation methods work with logical paths
            var newDrive = new PSDriveInfo(drive.Name, this.ProviderInfo, drive.Name + ":", drive.Description, drive.Credential);
            SessionState.PSVariable.Set("__buckets_physical_root_" + drive.Name, root);
            return newDrive;
        }

        private string GetPhysicalRoot()
        {
            string varName = "__buckets_physical_root_" + PSDriveInfo.Name;
            var variable = SessionState.PSVariable.Get(varName);
            return variable?.Value as string ?? PSDriveInfo.Root;
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
        /// Handles both relative paths (users/Alice) and provider-qualified paths (Buckets::...).
        /// For leaf paths, probes .dat first, then .json.
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

            // Strip leading separators (these are provider separators, NOT filesystem roots)
            // This is critical: on Unix, "/users" would be treated as absolute by Path.IsPathRooted
            path = path.TrimStart(Sep, '/', '\\');

            if (string.IsNullOrEmpty(path))
            {
                return Directory.Exists(root) ? root : null;
            }

            // NOW check if it's a filesystem-absolute path (e.g. passed directly from the engine)
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

            // Normalize separators
            path = path.Replace('/', Sep).Replace('\\', Sep);

            string physical = Path.Combine(root, path);

            if (Directory.Exists(physical)) return physical;
            if (File.Exists(physical)) return physical;

            string datPath2 = physical + ".dat";
            if (File.Exists(datPath2)) return datPath2;

            string jsonPath2 = physical + ".json";
            if (File.Exists(jsonPath2)) return jsonPath2;

            return null;
        }

        /// <summary>
        /// Convert a physical filesystem path to a provider-logical path.
        /// </summary>
        private string ToLogicalPath(string physicalPath)
        {
            string root = GetPhysicalRoot();
            if (!physicalPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                return physicalPath;
            }

            string relative = physicalPath.Substring(root.Length).TrimStart(Sep);

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

                // Buckets module writes CLIXML as UTF-8 (not UTF-16LE)
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

        private string GetParentLogicalPath(string logicalPath)
        {
            string normalized = ToLogicalPath(logicalPath).TrimStart(Sep, '/', '\\');
            int sep = normalized.LastIndexOf(Sep);
            return sep < 0 ? "" : normalized.Substring(0, sep);
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
                var di = new DirectoryInfo(physical);
                var items = di.GetFiles("*.dat").Concat(di.GetFiles("*.json"));
                var dirs = di.GetDirectories().Where(d => d.Name != ".buckets");
                int count = items.Count() + dirs.Count();

                var info = new BucketItemInfo
                {
                    Name = di.Name,
                    IsContainer = true,
                    ItemCount = count,
                    Format = "",
                    SizeBytes = 0,
                    PhysicalPath = physical
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
            GetChildItemsInternal(path, recurse);
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

            // Subdirectories
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
                    ItemCount = count,
                    Format = "",
                    SizeBytes = 0,
                    PhysicalPath = subDir.FullName
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
                    ItemCount = 0,
                    Format = ext == ".json" ? "JSON" : "Binary",
                    SizeBytes = file.Length,
                    PhysicalPath = file.FullName
                }, logical, false);
            }
        }

        protected override void GetChildNames(string path, ReturnContainers returnContainers)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !Directory.Exists(physical)) return;

            var di = new DirectoryInfo(physical);

            if (returnContainers == ReturnContainers.ReturnAllContainers)
            {
                foreach (var subDir in di.GetDirectories().Where(d => d.Name != ".buckets").OrderBy(d => d.Name))
                {
                    WriteItemObject(subDir.Name, subDir.Name, true);
                }
            }

            foreach (var file in di.GetFiles("*.dat").Concat(di.GetFiles("*.json")).OrderBy(f => f.Name))
            {
                WriteItemObject(Path.GetFileNameWithoutExtension(file.Name), Path.GetFileNameWithoutExtension(file.Name), false);
            }
        }

        protected override bool HasChildItems(string path)
        {
            string physical = ToPhysicalPath(path);
            if (physical == null || !Directory.Exists(physical)) return false;

            var di = new DirectoryInfo(physical);
            return di.GetFiles("*.dat").Length > 0 ||
                   di.GetFiles("*.json").Length > 0 ||
                   di.GetDirectories().Length > 0;
        }

        #endregion

        #region Navigation

        protected override string MakePath(string parent, string child)
        {
            if (string.IsNullOrEmpty(parent)) return child ?? "";
            if (string.IsNullOrEmpty(child)) return parent;

            string normalized = parent.TrimEnd(Sep, '/', '\\');
            if (child == ".") return normalized;
            if (child == "..")
            {
                string driveName = PSDriveInfo.Name + ":";
                if (normalized.EndsWith(driveName, StringComparison.OrdinalIgnoreCase) && normalized.Length == driveName.Length)
                {
                    return normalized;
                }
                int lastSep = normalized.LastIndexOf(Sep);
                if (lastSep < 0) return normalized;
                normalized = normalized.Substring(0, lastSep);
                if (string.IsNullOrEmpty(normalized)) return PSDriveInfo.Name + ":";
                return normalized;
            }

            if (normalized.EndsWith(":", StringComparison.OrdinalIgnoreCase))
            {
                return normalized + Sep + child;
            }

            return normalized + Sep + child;
        }

        protected override string GetParentPath(string path, string root)
        {
            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            string driveName = PSDriveInfo.Name + ":";
            if (cleaned.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(driveName.Length);
            }
            cleaned = cleaned.TrimStart(Sep, '/', '\\');

            if (string.IsNullOrEmpty(cleaned)) return root;

            int sep = cleaned.LastIndexOf(Sep);
            if (sep < 0) return root;

            string parentRel = cleaned.Substring(0, sep);
            return string.IsNullOrEmpty(parentRel) ? root : (root + Sep + parentRel);
        }

        protected override string GetChildName(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";

            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            string driveName = PSDriveInfo.Name + ":";
            if (cleaned.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(driveName.Length);
            }
            cleaned = cleaned.TrimStart(Sep, '/', '\\');

            if (string.IsNullOrEmpty(cleaned)) return "";

            int sep = cleaned.LastIndexOf(Sep);
            return sep < 0 ? cleaned : cleaned.Substring(sep + 1);
        }

        protected override string NormalizeRelativePath(string path, string basePath)
        {
            if (string.IsNullOrEmpty(path)) return basePath ?? "";

            string cleaned = path;
            int colonColon = cleaned.IndexOf("::", StringComparison.Ordinal);
            if (colonColon >= 0) cleaned = cleaned.Substring(colonColon + 2);
            string driveName = PSDriveInfo.Name + ":";
            if (cleaned.StartsWith(driveName, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(driveName.Length);
            }
            cleaned = cleaned.TrimStart(Sep, '/', '\\');

            string root = GetPhysicalRoot();
            if (cleaned.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                cleaned = cleaned.Substring(root.Length).TrimStart(Sep, '/', '\\');
            }

            if (string.IsNullOrEmpty(cleaned)) return "";

            string[] parts = cleaned.Split(new[] { Sep, '/', '\\' }, StringSplitOptions.RemoveEmptyEntries);
            var stack = new System.Collections.Generic.List<string>();
            foreach (var part in parts)
            {
                if (part == ".") continue;
                if (part == "..")
                {
                    if (stack.Count > 0) stack.RemoveAt(stack.Count - 1);
                    continue;
                }
                stack.Add(part);
            }

            return string.Join(Sep.ToString(), stack);
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

            // If path points to non-existent location, build the physical path manually
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
                    ItemCount = 0,
                    Format = "",
                    SizeBytes = 0,
                    PhysicalPath = physical
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
                WriteItemObject(new BucketItemInfo
                {
                    Name = sanitizedKey,
                    IsContainer = false,
                    ItemCount = 0,
                    Format = format == "json" ? "JSON" : "Binary",
                    SizeBytes = new FileInfo(physical).Length,
                    PhysicalPath = physical
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
            // Convert existing to a plain dictionary for clean serialization
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
                // If base object is a dictionary, use it as the primary source
                if (pso.BaseObject is IDictionary baseDict)
                {
                    foreach (DictionaryEntry entry in baseDict)
                    {
                        result[entry.Key?.ToString() ?? ""] = entry.Value;
                    }
                    return result;
                }

                // For non-dictionary PSObjects, extract properties
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
