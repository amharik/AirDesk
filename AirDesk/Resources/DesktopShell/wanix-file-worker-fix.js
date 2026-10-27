(function () {
  var isFile = location.protocol === "file:";
  var NativeBlob = window.Blob;
  var NativeWorker = window.Worker;
  var wanixImport = /import\s*\{\s*WanixHandle\s*\}\s*from\s*"data:text\/javascript;base64,([^"]+)";?/;
  var moduleExports = /export\s*\{[^}]*\}\s*;?/g;
  var patchedURLs = new Set();
  var nativeCreateObjectURL = URL.createObjectURL.bind(URL);
  var openCall = "callback(null, await sys.openFile(path, flags, mode));";
  var openPatch = [
    "callback(null, await (async () => {",
    "  const O_CREATE = 64, O_TRUNC = 512, O_EXCL = 128;",
    "  let fd;",
    "  if (flags & O_CREATE) {",
    "    if (flags & O_EXCL) {",
    "      try { await sys.stat(path); throw fsErr('file already exists', 'EEXIST'); }",
    "      catch (error) {",
    "        const message = String(error && error.message || error).toLowerCase();",
    "        if (!message.includes('does not exist') && !message.includes('no such file')) throw error;",
    "      }",
    "    }",
    "    if (flags & O_TRUNC) {",
    "      await sys.create(path);",
    "      fd = await sys.openFile(path, flags & ~(O_CREATE | O_TRUNC), mode);",
    "    } else {",
    "      try { fd = await sys.openFile(path, flags & ~O_CREATE, mode); }",
    "      catch (error) {",
    "        const message = String(error && error.message || error).toLowerCase();",
    "        if (message.includes('does not exist') || message.includes('no such file')) {",
    "          await sys.create(path);",
    "          fd = await sys.openFile(path, flags & ~O_CREATE, mode);",
    "        } else {",
    "          throw error;",
    "        }",
    "      }",
    "    }",
    "  } else {",
    "    fd = await sys.openFile(path, flags, mode);",
    "  }",
    "  return fd;",
    "})());"
  ].join("\n");
  var replacements = [
    [openCall, openPatch],
    ["await sys.chmod(path, mode);", "await sys.chmod(path, Number(mode));"],
    ["await sys.chown(path, uid, gid);", "await sys.chown(path, Number(uid), Number(gid));"],
    ["await sys.fchmod(fd, mode);", "await sys.fchmod(fd, Number(mode));"],
    ["await sys.fchown(fd, uid, gid);", "await sys.fchown(fd, Number(uid), Number(gid));"],
    ["await sys.ftruncate(fd, length);", "await sys.ftruncate(fd, Number(length));"],
    ["await sys.truncate(path, length);", "await sys.truncate(path, Number(length));"],
    ["await sys.chtimes(path, atime, mtime);", "await sys.chtimes(path, Number(atime) + 1e-6, Number(mtime) + 1e-6);"],
  ];

  function patchWorker(source) {
    for (var index = 0; index < replacements.length; index++) {
      source = source.replace(replacements[index][0], replacements[index][1]);
    }
    return source;
  }

  class FileBlob extends NativeBlob {
    constructor(parts, options) {
      if (Array.isArray(parts) && parts.length === 1 && typeof parts[0] === "string") {
        var source = patchWorker(parts[0]);
        var match = isFile ? source.match(wanixImport) : null;
        if (match) {
          try {
            var inlined = atob(match[1]).replace(moduleExports, "");
            var blob = super([inlined + "\n" + source.replace(match[0], "")], options);
            blob.airdeskClassicWorker = true;
            return blob;
          } catch (error) {
            console.warn("AirDesk could not inline the Wanix worker module", error);
          }
        }
        if (source !== parts[0]) return super([source], options);
      }
      return super(parts, options);
    }
  }

  class FileWorker extends NativeWorker {
    constructor(url, options) {
      if (typeof url === "string" && patchedURLs.has(url) && options && options.type === "module") {
        options = Object.assign({}, options, { type: "classic" });
      }
      super(url, options);
    }
  }

  URL.createObjectURL = function (object) {
    var url = nativeCreateObjectURL(object);
    if (object && object.airdeskClassicWorker) patchedURLs.add(url);
    return url;
  };

  window.Blob = FileBlob;
  if (isFile) window.Worker = FileWorker;
})();
