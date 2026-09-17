#!/usr/bin/env python3
"""One Chrome process, three cameras, CDP Page.captureScreenshot.

Stdlib only: a handful of WebSocket frames, then the browser exits.
No puppeteer, no resident bridge. Cameras switch through window.__poemShot
so the scene is not rebuilt.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse

CTF_DEFAULT = (
    "/Users/chener/.cache/puppeteer/chrome/mac_arm-150.0.7871.24/"
    "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/"
    "Google Chrome for Testing"
)

COMMON_FLAGS = [
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-extensions",
    "--disable-background-networking",
    "--disable-sync",
    "--disable-translate",
    "--disable-features=Translate,TranslateUI,CalculateNativeWinOcclusion,MediaRouter",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-ipc-flooding-protection",
    "--hide-scrollbars",
    "--mute-audio",
    "--metrics-recording-only",
    "--password-store=basic",
    "--use-mock-keychain",
    "--noerrdialogs",
]

GPU_FLAGS = [
    "--enable-gpu",
    "--use-angle=metal",
    "--use-gl=angle",
    "--enable-gpu-rasterization",
    "--ignore-gpu-blocklist",
    "--disable-gpu-driver-bug-workarounds",
]


class WS:
    def __init__(self, url, timeout=30):
        u = urlparse(url)
        host, port = u.hostname, u.port or 80
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        path = u.path + (("?" + u.query) if u.query else "")
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "\r\n"
        )
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("websocket handshake closed")
            buf += chunk
        status = buf.split(b"\r\n", 1)[0]
        if b"101" not in status:
            raise RuntimeError("websocket handshake failed: " + status.decode("latin1", "replace"))

    def send_text(self, text):
        data = text.encode()
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        n = len(data)
        hdr = bytes([0x81])
        if n < 126:
            hdr += bytes([0x80 | n])
        elif n < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack("!H", n)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack("!Q", n)
        self.sock.sendall(hdr + mask + masked)

    def _recvn(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise RuntimeError("websocket closed")
            buf += chunk
        return buf

    def recv_text(self):
        pieces = []
        while True:
            hdr = self._recvn(2)
            opcode = hdr[0] & 0x0F
            fin = hdr[0] >> 7
            masked = hdr[1] >> 7
            n = hdr[1] & 0x7F
            if n == 126:
                n = struct.unpack("!H", self._recvn(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", self._recvn(8))[0]
            mask = self._recvn(4) if masked else b""
            data = self._recvn(n)
            if masked:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x8:
                raise RuntimeError("websocket close")
            if opcode == 0x9:
                # pong
                mask2 = os.urandom(4)
                masked2 = bytes(b ^ mask2[i % 4] for i, b in enumerate(data))
                self.sock.sendall(bytes([0x8A, 0x80 | len(data)]) + mask2 + masked2)
                continue
            if opcode == 0xA:
                continue
            pieces.append(data)
            if fin:
                return b"".join(pieces).decode("utf-8", "replace")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class CDP:
    def __init__(self, url, timeout=30):
        self.ws = WS(url, timeout=timeout)
        self._id = 0
        self.timeout = timeout

    def call(self, method, params=None, timeout=None):
        self._id += 1
        msg = {"id": self._id, "method": method}
        if params:
            msg["params"] = params
        want = self._id
        self.ws.send_text(json.dumps(msg))
        deadline = time.time() + (timeout or self.timeout)
        while True:
            remain = deadline - time.time()
            if remain <= 0:
                raise TimeoutError(method)
            self.ws.sock.settimeout(max(0.1, remain))
            raw = self.ws.recv_text()
            data = json.loads(raw)
            if data.get("id") == want:
                if "error" in data:
                    raise RuntimeError("%s: %s" % (method, data["error"]))
                return data.get("result") or {}

    def evaluate(self, expr, timeout=None):
        r = self.call(
            "Runtime.evaluate",
            {"expression": expr, "returnByValue": True, "awaitPromise": True},
            timeout=timeout,
        )
        if r.get("exceptionDetails"):
            raise RuntimeError("js: %s" % r["exceptionDetails"])
        return (r.get("result") or {}).get("value")

    def close(self):
        self.ws.close()


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_devtools(port, timeout):
    url = "http://127.0.0.1:%d/json/version" % port
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1.5) as r:
                return json.loads(r.read().decode())
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as e:
            last = e
            time.sleep(0.1)
    raise RuntimeError("devtools never came up on %s (%s)" % (url, last))


def page_ws(port, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/json/list" % port, timeout=1.5) as r:
                tabs = json.loads(r.read().decode())
            for t in tabs:
                if t.get("type") == "page" and t.get("webSocketDebuggerUrl"):
                    return t["webSocketDebuggerUrl"]
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            pass
        time.sleep(0.1)
    raise RuntimeError("no page target on port %d" % port)


def chrome_cmd(backend, chrome, profile, port, w, h):
    flags = [
        chrome,
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=%d" % port,
        "--user-data-dir=%s" % profile,
        "--window-size=%d,%d" % (w, h),
    ] + COMMON_FLAGS
    if os.environ.get("POEM_SHOT_SPREAD", "1") != "0":
        flags += [
            "--num-raster-threads=1",
            "--renderer-process-limit=1",
            "--js-flags=--single-threaded",
        ]
    if backend == "headless-gpu":
        flags += GPU_FLAGS + ["--headless=new"]
    elif backend == "swiftshader":
        flags += [
            "--headless=new",
            "--disable-gpu",
            "--use-angle=swiftshader",
            "--disable-gpu-compositing",
        ]
    else:
        raise SystemExit("unknown backend: %s" % backend)
    if os.environ.get("POEM_SHOT_DEBUG"):
        flags += ["--enable-logging=stderr", "--v=1"]
    return flags


def tree_pids(root):
    try:
        out = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    except subprocess.CalledProcessError:
        return [root]
    kids = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        pid, ppid = int(parts[0]), int(parts[1])
        kids.setdefault(ppid, []).append(pid)
    seen = {root}
    stack = [root]
    while stack:
        p = stack.pop()
        for c in kids.get(p, []):
            if c not in seen:
                seen.add(c)
                stack.append(c)
    return list(seen)


def sample_cpu(pid):
    pids = tree_pids(pid)
    try:
        out = subprocess.check_output(
            ["ps", "-o", "%cpu=", "-p", ",".join(str(p) for p in pids)],
            text=True,
        )
    except subprocess.CalledProcessError:
        return 0.0, 0.0
    total = 0.0
    mx = 0.0
    for line in out.splitlines():
        try:
            v = float(line.strip() or "0")
        except ValueError:
            continue
        total += v
        if v > mx:
            mx = v
    return total, mx


def gpu_procs(pid):
    pids = tree_pids(pid)
    try:
        out = subprocess.check_output(
            ["ps", "-o", "pid=,command=", "-p", ",".join(str(p) for p in pids)],
            text=True,
        )
    except subprocess.CalledProcessError:
        return []
    hits = []
    for line in out.splitlines():
        if "Gpu" in line or "GPU" in line or "type=gpu" in line:
            hits.append(line.strip())
    return hits


def kill_tree(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            proc.kill()


def parse_shots(items):
    shots = []
    for raw in items:
        if ":" not in raw:
            raise SystemExit("shot must be name:arg — got %r" % raw)
        name, arg = raw.split(":", 1)
        shots.append((name, arg))
    if not shots:
        raise SystemExit("no --shot given")
    return shots


def main():
    ap = argparse.ArgumentParser()
    # Headless only: a headed Chrome takes over a screen on a machine someone
    # is using. shared/shoot.sh refuses anything else before it gets here.
    ap.add_argument("--backend", required=True, choices=("headless-gpu", "swiftshader"))
    ap.add_argument("--load", required=True, help="first URL; enables ?shot=1")
    ap.add_argument("--shot", action="append", default=[], help="name:arg for window.__poemShot")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--chrome", default=os.environ.get("POEM_WORLD_CHROME", CTF_DEFAULT))
    ap.add_argument("--timeout", type=float, default=25.0)
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--height", type=int, default=600)
    ap.add_argument("--stats", default="")
    ap.add_argument("--profile", default="", help="chrome --user-data-dir; default is a fresh /tmp dir")
    ap.add_argument("--pidfile", default="", help="write the browser pid here so the caller can reap it")
    args = ap.parse_args()
    shots = parse_shots(args.shot)
    chrome = args.chrome
    if not os.path.isfile(chrome) or not os.access(chrome, os.X_OK):
        print("no Chrome for Testing at: %s" % chrome, file=sys.stderr)
        return 1
    os.makedirs(args.outdir, exist_ok=True)
    profile = args.profile or os.path.join(
        "/tmp", "pw-shot-profile-%d-%d" % (os.getpid(), time.time_ns())
    )
    os.makedirs(profile, exist_ok=True)
    port = free_port()
    cmd = chrome_cmd(args.backend, chrome, profile, port, args.width, args.height)
    logf = subprocess.DEVNULL
    log_path = ""
    if os.environ.get("POEM_SHOT_DEBUG"):
        log_path = os.path.join(profile, "chrome.log")
        logf = open(log_path, "wb")
    # A signal must reach the finally: below, or Chrome is reparented to init
    # and stays. SystemExit unwinds the try, so kill_tree(proc) still runs.
    def _bail(signum, _frame):
        raise SystemExit(128 + signum)

    for _sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            signal.signal(_sig, _bail)
        except (ValueError, OSError):
            pass

    t0 = time.time()
    proc = subprocess.Popen(
        cmd,
        stdout=logf,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    if args.pidfile:
        try:
            with open(args.pidfile, "w") as f:
                f.write("%d\n" % proc.pid)
        except OSError:
            pass
    peak_sum = 0.0
    peak_one = 0.0
    gpu_seen = []
    renderer = ""
    cdp = None
    try:
        wait_devtools(port, min(12.0, args.timeout))
        ws_url = page_ws(port, min(8.0, args.timeout))
        cdp = CDP(ws_url, timeout=args.timeout)
        cdp.call("Page.enable")
        cdp.call("Runtime.enable")
        cdp.call(
            "Emulation.setDeviceMetricsOverride",
            {
                "width": args.width,
                "height": args.height,
                "deviceScaleFactor": 1,
                "mobile": False,
            },
        )
        cdp.call("Page.navigate", {"url": args.load})
        deadline = time.time() + args.timeout
        while time.time() < deadline:
            s, m = sample_cpu(proc.pid)
            peak_sum = max(peak_sum, s)
            peak_one = max(peak_one, m)
            if not gpu_seen:
                gpu_seen = gpu_procs(proc.pid)
            try:
                hook = cdp.evaluate(
                    "typeof window.__poemShot==='function'",
                    timeout=2.0,
                )
                flag = cdp.evaluate(
                    "document.documentElement.getAttribute('data-shot-ready')"
                    "||document.body.getAttribute('data-shot-ready')",
                    timeout=2.0,
                )
            except (TimeoutError, RuntimeError):
                hook, flag = False, None
            if hook and flag == "1":
                break
            time.sleep(0.05)
        else:
            try:
                print("DEBUG_PAGE: %s" % cdp.evaluate(
                    "JSON.stringify({iw:innerWidth,ih:innerHeight,"
                    "ready:document.body&&document.body.getAttribute('data-shot-ready'),"
                    "hook:typeof window.__poemShot,cls:document.body&&document.body.className,"
                    "err:String(window.__shotErr||'')})"
                ), file=sys.stderr)
            except Exception:
                pass
            raise RuntimeError("page never became shot-ready")
        try:
            renderer = cdp.evaluate(
                """(() => {
                  const c = document.createElement('canvas');
                  const gl = c.getContext('webgl') || c.getContext('experimental-webgl');
                  if (!gl) return 'no-webgl';
                  const ext = gl.getExtension('WEBGL_debug_renderer_info');
                  return ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL))
                             : String(gl.getParameter(gl.RENDERER));
                })()"""
            ) or ""
        except (TimeoutError, RuntimeError) as e:
            renderer = "error:%s" % e
        print("GPU_RENDERER: %s" % renderer)
        print("GPU_PROCS: %d" % len(gpu_seen))
        for line in gpu_seen:
            print("  %s" % line)
        times = []
        for name, arg in shots:
            t_cam = time.time()
            js_arg = json.dumps(arg)
            cdp.evaluate(
                "document.body.removeAttribute('data-shot-ready');"
                "document.documentElement.removeAttribute('data-shot-ready');"
                "window.__poemShot(%s)" % js_arg,
                timeout=args.timeout,
            )
            cam_deadline = time.time() + args.timeout
            while time.time() < cam_deadline:
                s, m = sample_cpu(proc.pid)
                peak_sum = max(peak_sum, s)
                peak_one = max(peak_one, m)
                flag = cdp.evaluate(
                    "document.documentElement.getAttribute('data-shot-ready')"
                    "||document.body.getAttribute('data-shot-ready')",
                    timeout=2.0,
                )
                if flag == "1":
                    break
                time.sleep(0.04)
            else:
                raise RuntimeError("shot %s never set data-shot-ready" % name)
            png = cdp.call(
                "Page.captureScreenshot",
                {"format": "png", "fromSurface": True, "captureBeyondViewport": False},
                timeout=args.timeout,
            )
            blob = base64.b64decode(png["data"])
            out = os.path.join(args.outdir, name + ".png")
            with open(out, "wb") as f:
                f.write(blob)
            dt = time.time() - t_cam
            times.append((name, dt, len(blob)))
            print("  %s  %.2fs  %d bytes" % (out, dt, len(blob)))
            if not blob:
                raise RuntimeError("empty png for %s" % name)
        elapsed = time.time() - t0
        print("elapsed_s: %.2f" % elapsed)
        print("cpu_peak_tree_pct: %.1f" % peak_sum)
        print("cpu_peak_one_pct: %.1f" % peak_one)
        print("chrome_pid: %d" % proc.pid)
        if args.stats:
            with open(args.stats, "w") as f:
                json.dump(
                    {
                        "backend": args.backend,
                        "renderer": renderer,
                        "gpu_procs": gpu_seen,
                        "elapsed_s": elapsed,
                        "cpu_peak_tree_pct": peak_sum,
                        "cpu_peak_one_pct": peak_one,
                        "cameras": [{"name": n, "s": dt, "bytes": b} for n, dt, b in times],
                    },
                    f,
                    indent=2,
                )
                f.write("\n")
        return 0
    except Exception as e:
        print("FAILED: %s" % e, file=sys.stderr)
        return 2
    finally:
        if cdp is not None:
            cdp.close()
        kill_tree(proc)
        if args.pidfile:
            try:
                os.remove(args.pidfile)
            except OSError:
                pass
        if log_path:
            try:
                logf.close()
            except Exception:
                pass
        if not args.profile:
            shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
