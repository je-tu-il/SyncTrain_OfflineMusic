import json
import os
import plistlib
import socketserver
import threading
import unittest
import urllib.request

import server


ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class TestSyncTrain(unittest.TestCase):
    def test_sync_status(self):
        self.assertFalse(server.SYNC_STATUS["internet_required"])
        self.assertTrue(len(server.PLAYLIST) >= 1)

    def test_http_endpoints_serve_health_and_playlist(self):
        orig_cwd = os.getcwd()
        os.chdir(ROOT_DIR)
        httpd = socketserver.TCPServer(("127.0.0.1", 0), server.CustomHandler)
        port = httpd.server_address[1]
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health") as resp:
                self.assertEqual(resp.status, 200)
                health = json.loads(resp.read().decode("utf-8"))
                self.assertEqual(health["status"], "healthy")
                self.assertEqual(health["service"], "SyncTrain_OfflineMusic")

            with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/sync_music") as resp:
                self.assertEqual(resp.status, 200)
                data = json.loads(resp.read().decode("utf-8"))
                self.assertFalse(data["sync"]["internet_required"])
                self.assertEqual(len(data["tracks"]), len(server.PLAYLIST))

            with urllib.request.urlopen(f"http://127.0.0.1:{port}/") as resp:
                self.assertEqual(resp.status, 200)
                html = resp.read().decode("utf-8")
                self.assertIn("SyncTrain OfflineMusic", html)
        finally:
            httpd.shutdown()
            httpd.server_close()
            os.chdir(orig_cwd)

    def test_ios_project_and_ipa_workflow_structure(self):
        required_files = [
            os.path.join(ROOT_DIR, "ios", "project.yml"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "Info.plist"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "SyncTrainApp.swift"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "AudioPlayerManager.swift"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "WebCompanionView.swift"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "ContentView.swift"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "Resources", "offline_companion.html"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "Assets.xcassets", "Contents.json"),
            os.path.join(ROOT_DIR, "ios", "SyncTrain", "Assets.xcassets", "AppIcon.appiconset", "Contents.json"),
            os.path.join(ROOT_DIR, ".github", "workflows", "build-ipa.yml"),
        ]
        for path in required_files:
            self.assertTrue(os.path.isfile(path), f"Missing iOS/CI file: {path}")

        with open(os.path.join(ROOT_DIR, "ios", "SyncTrain", "Info.plist"), "rb") as handle:
            plist = plistlib.load(handle)
        self.assertIn("audio", plist.get("UIBackgroundModes", []))
        self.assertTrue(plist.get("UIFileSharingEnabled"))
        self.assertTrue(plist.get("NSAppTransportSecurity", {}).get("NSAllowsLocalNetworking"))

        with open(os.path.join(ROOT_DIR, ".github", "workflows", "build-ipa.yml"), "r", encoding="utf-8") as handle:
            wf = handle.read()
        self.assertIn("macos-latest", wf)
        self.assertIn("xcodegen generate", wf)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", wf)
        self.assertIn("SyncTrain.ipa", wf)


if __name__ == "__main__":
    unittest.main()
