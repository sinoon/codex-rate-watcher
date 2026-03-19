from setuptools import setup

APP = ["app.py"]
OPTIONS = {
  "argv_emulation": False,
  "plist": {
    "CFBundleDisplayName": "Codex Rate Watcher",
    "CFBundleName": "Codex Rate Watcher",
    "CFBundleIdentifier": "io.github.codex-rate-watcher",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "LSUIElement": True,
  },
}

setup(
  app=APP,
  options={"py2app": OPTIONS},
  setup_requires=["py2app"],
)
