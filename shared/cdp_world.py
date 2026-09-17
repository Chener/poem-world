#!/usr/bin/env python3
"""One Chrome process, every camera, window.__world() printed to a file.

The picture-free half of cdp_shot.py: same browser plumbing, but instead of
Page.captureScreenshot it evaluates the page's scene-data debug port and writes
a few kB of JSON. The polish loop's hard gates read that JSON; only the
aesthetic gate needs a picture.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cdp_shot import (  # noqa: E402  (same directory, classic script style)
    CDP,
    CTF_DEFAULT,
    chrome_cmd,
    free_port,
    kill_tree,
    page_ws,
    parse_shots,
    wait_devtools,
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", required=True,
                    choices=("headed-metal", "headless-gpu", "swiftshader"))
    ap.add_argument("--load", required=True, help="first URL; enables ?shot=1")
    ap.add_argument("--shot", action="append", default=[],
                    help="name:arg for window.__poemShot")
    ap.add_argument("--out", required=True, help="JSON file to write")
    ap.add_argument("--chrome", default=os.environ.get("POEM_WORLD_CHROME", CTF_DEFAULT))
    ap.add_argument("--timeout", type=float, default=25.0)
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--height", type=int, default=600)
    args = ap.parse_args()
    shots = parse_shots(args.shot)
    chrome = args.chrome
    if not os.path.isfile(chrome) or not os.access(chrome, os.X_OK):
        print("no Chrome for Testing at: %s" % chrome, file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    profile = os.path.join("/tmp", "pw-world-profile-%d-%d" % (os.getpid(), time.time_ns()))
    os.makedirs(profile, exist_ok=True)
    port = free_port()
    cmd = chrome_cmd(args.backend, chrome, profile, port, args.width, args.height)
    t0 = time.time()
    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True
    )
    cdp = None
    try:
        wait_devtools(port, min(12.0, args.timeout))
        ws_url = page_ws(port, min(8.0, args.timeout))
        cdp = CDP(ws_url, timeout=args.timeout)
        cdp.call("Page.enable")
        cdp.call("Runtime.enable")
        cdp.call(
            "Emulation.setDeviceMetricsOverride",
            {"width": args.width, "height": args.height,
             "deviceScaleFactor": 1, "mobile": False},
        )
        cdp.call("Page.navigate", {"url": args.load})
        deadline = time.time() + args.timeout
        while time.time() < deadline:
            try:
                hook = cdp.evaluate(
                    "typeof window.__poemShot==='function'"
                    "&&typeof window.__world==='function'", timeout=2.0)
                flag = cdp.evaluate(
                    "document.documentElement.getAttribute('data-shot-ready')"
                    "||document.body.getAttribute('data-shot-ready')", timeout=2.0)
            except (TimeoutError, RuntimeError):
                hook, flag = False, None
            if hook and flag == "1":
                break
            time.sleep(0.05)
        else:
            raise RuntimeError("page never exposed both __poemShot and __world")

        cams = []
        for name, arg in shots:
            cdp.evaluate(
                "document.body.removeAttribute('data-shot-ready');"
                "document.documentElement.removeAttribute('data-shot-ready');"
                "window.__poemShot(%s)" % json.dumps(arg),
                timeout=args.timeout,
            )
            cam_deadline = time.time() + args.timeout
            while time.time() < cam_deadline:
                flag = cdp.evaluate(
                    "document.documentElement.getAttribute('data-shot-ready')"
                    "||document.body.getAttribute('data-shot-ready')", timeout=2.0)
                if flag == "1":
                    break
                time.sleep(0.04)
            else:
                raise RuntimeError("camera %s never set data-shot-ready" % name)
            data = cdp.evaluate("JSON.stringify(window.__world())", timeout=args.timeout)
            world = json.loads(data)
            if world.get("error"):
                raise RuntimeError("__world() threw for %s: %s" % (name, world["error"]))
            world["shot"] = name
            cams.append(world)

        out = {"url": args.load, "backend": args.backend, "cameras": cams}
        with open(args.out, "w") as f:
            json.dump(out, f, indent=1, sort_keys=False)
            f.write("\n")
        print("%s  %d cameras  %d bytes  %.2fs"
              % (args.out, len(cams), os.path.getsize(args.out), time.time() - t0))
        return 0
    except Exception as e:
        print("FAILED: %s" % e, file=sys.stderr)
        return 2
    finally:
        if cdp is not None:
            cdp.close()
        kill_tree(proc)
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
