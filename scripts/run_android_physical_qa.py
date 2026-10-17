#!/usr/bin/env python3
"""Explicit Together-only physical QA. Never uninstall, clear data or use connectedAndroidTest.

Artifacts contain device metadata/logs and must stay in ignored qa/results, never GitHub.
The device must already be USB-authorized. A loopback Worker and adb reverse are required.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.parse
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.together.android.debug"
RUNNER = PACKAGE + ".test/com.together.android.IsolatedAndroidTestRunner"
DEBUG_CERT = "d02df7cd7e848b78acd6325fe4d29ce4deea21d12f6901cc0e76ce8ffa97205c"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def loopback(value):
    u = urllib.parse.urlparse(value)
    if not (u.scheme == "http" and u.hostname == "127.0.0.1" and u.port and
            1024 <= u.port <= 65535 and not u.path and not u.query and
            not u.fragment and not u.username and not u.password):
        raise ValueError("Explicit http://127.0.0.1:<port> test service required")
    return u


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


class PhysicalRun:
    def __init__(self, serial, model, relay, out):
        if not re.fullmatch(r"[A-Za-z0-9_-]{5,80}", serial) or serial.startswith("emulator-"):
            raise ValueError("Explicit physical device serial required")
        self.serial, self.model, self.relay = serial, model, relay
        self.port = "tcp:" + str(loopback(relay).port)
        self.out = Path(out).resolve()
        if not self.out.is_relative_to(ROOT / "qa/results/android-phase-c"):
            raise ValueError("Physical artifacts must stay in the ignored Phase C directory")
        self.out.mkdir(parents=True, exist_ok=True)
        self.adb_path = os.environ.get("ANDROID_ADB", str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
        self.run_id = uuid.uuid4().hex.upper()

    def adb(self, *args, timeout=90, check=True, input=None):
        r = subprocess.run([self.adb_path, "-s", self.serial, *args], input=input,
                           capture_output=True, timeout=timeout)
        if check and r.returncode:
            raise RuntimeError("adb failed: " + " ".join(args[:4]) + "\n" + r.stderr.decode(errors="replace"))
        return r

    def preflight(self):
        require(self.adb("get-state").stdout.strip() == b"device", "Device offline or unauthorized")
        require(self.adb("shell", "getprop", "ro.product.model").stdout.decode().strip() == self.model, "Unexpected phone")
        require(self.adb("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1", "Not physical hardware")
        require(self.adb("shell", "getprop", "ro.product.manufacturer").stdout.decode().strip().lower() == "samsung", "Expected the authorized Samsung")
        require(self.adb("shell", "pm", "path", PACKAGE, check=False).stdout.startswith(b"package:"), "Install the verified baseline first")

    def certificate(self, apk):
        tool = Path(os.environ.get("ANDROID_HOME", str(Path.home()/"Library/Android/sdk"))) / "build-tools/36.1.0/apksigner"
        r = subprocess.run([str(tool), "verify", "--print-certs", str(apk)], capture_output=True, text=True, check=True)
        signatures = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([a-f0-9]{64})", r.stdout)
        require(signatures == [DEBUG_CERT], "Unexpected signing identity; never uninstall to bypass")
        return signatures[0]

    def manifest(self, apk, expected):
        tool = Path(os.environ.get("ANDROID_HOME", str(Path.home()/"Library/Android/sdk"))) / "build-tools/36.1.0/aapt2"
        text = subprocess.check_output([str(tool),"dump","badging",str(apk)],text=True)
        package = re.search(r"^package: name='([^']+)'",text,re.M)
        require(package is not None and package.group(1)==expected,"Unexpected APK application ID; refusing installation")
        require("application-debuggable" in text,"Only the isolated Debug build may be installed")

    def install(self):
        self.preflight()
        path = self.adb("shell", "pm", "path", PACKAGE).stdout.decode().splitlines()[0].removeprefix("package:").strip()
        saved = self.out / "installed-before.apk"
        self.adb("pull", path, str(saved))
        self.certificate(saved)
        self.manifest(saved, PACKAGE)
        apks = [ROOT/"apps/android/app/build/outputs/apk/debug/app-debug.apk",
                ROOT/"apps/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"]
        records = []
        for apk, expected in zip(apks, [PACKAGE, PACKAGE+".test"]):
            cert = self.certificate(apk)
            self.manifest(apk, expected)
            r = self.adb("install", "-r", str(apk))
            require(b"Success" in r.stdout, r.stdout.decode(errors="replace"))
            records.append(dict(path=str(apk), sha256=digest(apk), bytes=apk.stat().st_size, certificate=cert))
        (self.out/"install.json").write_text(json.dumps(dict(status="PASS",replaceOnly=True,dataCleared=False,apks=records),indent=2))

    def args(self, classes, extra=None):
        require(all(re.fullmatch(r"com\.together\.android\.[A-Za-z0-9_$]+(?:#[A-Za-z0-9_$]+)?",c) for c in classes.split(",")),"Only Together instrumentation test classes are allowed")
        args = ["shell", "am", "instrument", "-w", "-r", "-e", "class", classes,
                "-e", "physicalQa", "explicit-test-app-only", "-e", "expectedModel", self.model,
                "-e", "qaRunId", self.run_id, "-e", "relayURL", self.relay,
                "-e", "captureDirectory", "together-phase-c-candidates", "-e", "capturePrefix", "samsung-light"]
        for k, v in (extra or {}).items():
            args += ["-e", k, str(v)]
        return args + [RUNNER]

    def instrument(self, classes, label, extra=None, timeout=900):
        self.preflight()
        before = self.adb("reverse", "--list").stdout.decode()
        same_port = [l for l in before.splitlines() if l.split()[-2:-1] == [self.port]]
        require(not same_port or all(l.split()[-2:] == [self.port, self.port] for l in same_port), "Do not replace another reverse mapping")
        added = not same_port
        if added:
            self.adb("reverse", self.port, self.port)
        uid_text = self.adb("shell", "cmd", "package", "list", "packages", "-U", PACKAGE).stdout.decode()
        uid = re.search(r"package:" + re.escape(PACKAGE) + r" uid:(\d+)\b", uid_text).group(1)
        log_file = (self.out/(label+"-logcat.txt")).open("wb")
        logger = subprocess.Popen([self.adb_path,"-s",self.serial,"logcat","--uid",uid,"-v","threadtime","-T","1"],stdout=log_file,stderr=subprocess.STDOUT)
        start = time.monotonic()
        try:
            timed_out = False
            with (self.out/(label+".log")).open("wb") as stream:
                child = subprocess.Popen([self.adb_path,"-s",self.serial,*self.args(classes,extra)],stdout=stream,stderr=subprocess.STDOUT)
                try: returncode = child.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    # Stop only this authorized test app. Never clear a store or kill adb globally.
                    self.adb("shell","am","force-stop",PACKAGE,check=False)
                    try: child.wait(timeout=10)
                    except subprocess.TimeoutExpired: child.terminate(); child.wait(timeout=10)
                    returncode = -1
            raw = (self.out/(label+".log")).read_text(errors="replace")
            # AndroidJUnitRunner uses -2/-1 for failures, -3 for assumptions. Exit code alone is insufficient.
            codes = [int(v) for v in re.findall(r"INSTRUMENTATION_STATUS_CODE: (-?\d+)", raw)]
            summary = dict(label=label,elapsedSeconds=round(time.monotonic()-start,3),passed=codes.count(0),failed=codes.count(-1)+codes.count(-2),skipped=codes.count(-3),runId=self.run_id)
            summary["runnerTimedOut"] = timed_out
            summary["status"] = "PASS" if returncode==0 and "OK (" in raw and summary["failed"]==0 and summary["passed"] and not timed_out else "FAIL"
            (self.out/(label+".json")).write_text(json.dumps(summary,indent=2))
            print(json.dumps(summary),flush=True)
            return summary
        finally:
            logger.terminate()
            try: logger.wait(timeout=10)
            except subprocess.TimeoutExpired: logger.kill(); logger.wait()
            log_file.close()
            if added:
                self.adb("reverse","--remove",self.port,check=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--serial",required=True)
    p.add_argument("--expect-model",required=True)
    p.add_argument("--relay",required=True)
    p.add_argument("--authorize-physical-test-app",action="store_true",required=True)
    p.add_argument("--install",action="store_true")
    p.add_argument("--classes")
    p.add_argument("--label",default="instrumentation")
    p.add_argument("--extra",action="append",default=[],help="instrumentation key=value")
    p.add_argument("--timeout",type=int,default=900)
    args = p.parse_args()
    require(re.fullmatch(r"[a-z0-9-]+",args.label), "Use a lowercase artifact label without path separators")
    run = PhysicalRun(args.serial,args.expect_model,args.relay,ROOT/"qa/results/android-phase-c"/args.label)
    if args.install: run.install()
    if args.classes:
        result=run.instrument(args.classes,args.label,dict(x.split("=",1) for x in args.extra),args.timeout)
        raise SystemExit(0 if result["status"]=="PASS" else 1)
    run.preflight()


if __name__=="__main__":
    main()
