import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("server", Path(__file__).parents[1] / "server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

class Request:
    def __init__(self, host, origin=None):
        self.headers = {"Host": host}
        if origin is not None:
            self.headers["Origin"] = origin

class ServerBoundaryTests(unittest.TestCase):
    def test_accepts_loopback_hosts(self):
        handler = object.__new__(server.Handler)
        handler.headers = Request("127.0.0.1:8341").headers
        self.assertTrue(handler._allowed())
        handler.headers = Request("localhost:8341", "http://localhost:8341").headers
        self.assertTrue(handler._allowed())

    def test_rejects_host_origin_mismatch(self):
        handler = object.__new__(server.Handler)
        handler.headers = Request("attacker.example", "http://localhost:8341").headers
        self.assertFalse(handler._allowed())
        handler.headers = Request("127.0.0.1:8341", "https://attacker.example").headers
        self.assertFalse(handler._allowed())

    def test_only_public_assets_are_mapped(self):
        self.assertIn("/", server.ASSETS)
        self.assertIn("/app.js", server.ASSETS)
        self.assertNotIn("/.gitignore", server.ASSETS)
        self.assertNotIn("/server.py", server.ASSETS)

if __name__ == "__main__": unittest.main()
