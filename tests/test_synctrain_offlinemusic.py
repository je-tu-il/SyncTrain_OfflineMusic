import unittest
import server

class TestSyncTrain(unittest.TestCase):
    def test_sync_status(self):
        self.assertFalse(server.SYNC_STATUS["internet_required"])

if __name__ == "__main__":
    unittest.main()
