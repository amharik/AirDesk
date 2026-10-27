(function () {
  if (location.protocol !== "file:") return;

  var NativeBlob = window.Blob;
  var NativeWorker = window.Worker;
  var wanixImport = /import\s*\{\s*WanixHandle\s*\}\s*from\s*"data:text\/javascript;base64,([^"]+)";?/;
  var moduleExports = /export\s*\{[^}]*\}\s*;?/g;
  var patchedURLs = new Set();
  var nativeCreateObjectURL = URL.createObjectURL.bind(URL);

  class FileBlob extends NativeBlob {
    constructor(parts, options) {
      if (Array.isArray(parts) && parts.length === 1 && typeof parts[0] === "string") {
        var match = parts[0].match(wanixImport);
        if (match) {
          try {
            var inlined = atob(match[1]).replace(moduleExports, "");
            var blob = super([inlined + "\n" + parts[0].replace(match[0], "")], options);
            blob.airdeskClassicWorker = true;
            return blob;
          } catch (error) {
            console.warn("AirDesk could not inline the Wanix worker module", error);
          }
        }
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
  window.Worker = FileWorker;
})();
