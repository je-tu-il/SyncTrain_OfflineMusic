"""
SyncTrain OfflineMusic - Backend Server
Port: 8094
"""
import os, sys, json, http.server, socketserver, urllib.parse, urllib.request

PORT = 8094
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


PLAYLIST = [
    {"id": 1, "title": "Est-ce que la pub TV marche encore ?", "artist": "React @lecubenetwork", "duration": "14:20", "synced": True},
    {"id": 2, "title": "La fin des box TV ?", "artist": "React @numerama", "duration": "18:45", "synced": True},
    {"id": 3, "title": "Aura Lo-Fi Beats", "artist": "Synthwave Local", "duration": "03:12", "synced": True}
]

SYNC_STATUS = {
    "mode": "Proximité Hors-Ligne (P2P Mesh / Wi-Fi Direct)",
    "internet_required": False,
    "peers_nearby": 2,
    "last_sync": "À l'instant (Local 100%)",
    "synced_folder": "E:\\Musique"
}

def handle_get(handler, parsed):
    if parsed.path == "/api/sync_music":
        handler.send_response(200)
        handler.send_header("Content-Type", "application/json")
        handler.end_headers()
        handler.wfile.write(json.dumps({"sync": SYNC_STATUS, "tracks": PLAYLIST}).encode("utf-8"))
        return True
    return False

def handle_post(handler, parsed, payload):
    return False


class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy", "service": "SyncTrain_OfflineMusic", "port": PORT}).encode("utf-8"))
            return
        if handle_get(self, parsed):
            return
        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode("utf-8") if content_len > 0 else "{}"
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}
        if handle_post(self, parsed, payload):
            return
        self.send_response(404)
        self.end_headers()

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    os.chdir(BASE_DIR)
    with socketserver.TCPServer(("", PORT), CustomHandler) as httpd:
        print(f"[SyncTrain OfflineMusic] Serveur actif sur http://localhost:{PORT}")
        httpd.serve_forever()
