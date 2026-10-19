"""Overview's pinned test site: index and lesson-board links on the 8472 tailnet front, carried in /api/status."""
import unittest
from unittest import mock

from dash.services import sites as S, system


class TestSite(unittest.TestCase):
    def test_links_use_the_public_host_and_the_sites_front(self):
        self.assertEqual(S.test_site(), [
            {"name": "index", "url": "https://%s:8472/ailearning/" % S.PUBLIC_HOST},
            {"name": "lesson board", "url": "https://%s:8472/ailearning/board/" % S.PUBLIC_HOST},
        ])

    def test_status_payload_carries_them(self):
        with mock.patch.object(system, "swr", return_value={"status": {}, "agents": [], "events": []}), \
             mock.patch.object(system, "cache_meta", return_value=(False, {}, None)), \
             mock.patch.object(system.todo, "open_items", return_value=[]):
            self.assertEqual(system.payload()["test_site"], S.test_site())


if __name__ == "__main__":
    unittest.main()
