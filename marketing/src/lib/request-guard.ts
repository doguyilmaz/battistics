/** Disk writes require JSON and the editor's own origin. Headerless CLI
 * requests remain supported; these checks do not provide network authentication. */
export type GuardFailure = { error: string; status: number };

/**
 * Returns a failure to respond with, or null when the request is allowed.
 * Call at the top of every route handler that writes to disk.
 */
export function rejectCrossSiteWrite(req: Request): GuardFailure | null {
  // 1. Content-Type must be application/json. Not CORS-simple, so a
  //    cross-origin caller is forced into a preflight that fails.
  const contentType = req.headers.get("content-type") || "";
  if (contentType.toLowerCase().split(";")[0].trim() !== "application/json") {
    return { error: "Content-Type must be application/json", status: 415 };
  }

  // 2. Only a loopback host may write. A rebound DNS name reaches this server
  //    with its own Host and a matching Origin, so matching alone is not enough.
  const host = (req.headers.get("host") || "").toLowerCase();
  if (!isLoopback(host)) {
    return { error: "Untrusted host", status: 403 };
  }
  // Another local app (including a different port) is a different origin.
  const origin = req.headers.get("origin");
  if (origin) {
    let originHost: string;
    try {
      originHost = new URL(origin).host.toLowerCase();
    } catch {
      return { error: "Cross-origin write rejected", status: 403 };
    }
    if (originHost !== host || !isLoopback(originHost)) {
      return { error: "Cross-origin write rejected", status: 403 };
    }
  }

  // 3. Sec-Fetch-Site, when present, must not be cross-site.
  const site = req.headers.get("sec-fetch-site");
  if (site && site !== "same-origin" && site !== "none") {
    return { error: "Cross-site write rejected", status: 403 };
  }

  return null;
}

function isLoopback(host: string): boolean {
  const name = host.replace(/:\d+$/, "").replace(/^\[|\]$/g, "");
  return name === "localhost" || name === "127.0.0.1" || name === "::1";
}

/** Magic-byte sniff. Returns the real type, or null if it is neither. */
export function sniffImageType(bytes: Buffer): "image/png" | "image/jpeg" | null {
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  return null;
}
