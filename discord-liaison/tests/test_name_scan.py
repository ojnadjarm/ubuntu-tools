"""T1754-B D481: the liaison's post refuses a text holding the owner's name or e-mail (fixture identity, fake Discord)."""
import os
import unittest
from unittest import mock

from tests.test_liaison import Base

import chat_guard  # noqa: E402  (lib/ is on the path once liaison.cli is imported)

ID = {'HARNESS_OWNER_NAME': 'Ann Example Smithers', 'HARNESS_OWNER_EMAIL': 'ann@example.org'}


class TestNameScan(Base):
    async def asyncSetUp(self):
        await super().asyncSetUp()
        p = mock.patch.dict(os.environ, ID)
        p.start()
        self.addCleanup(p.stop)
        chat_guard.owner_names.cache_clear()
        self.addCleanup(chat_guard.owner_names.cache_clear)

    async def test_owner_name_or_email_refused_nothing_sent(self):
        for text in ('firmado: Ann Example Smithers', 'según smithers', 'escribe a ANN@example.org'):
            rc, out = await self.run_cli('post', '400', text)
            self.assertEqual(rc, 3, text)
            self.assertEqual(out.strip(), "refused: the text holds the owner's name or e-mail (D481); write it without them")
        self.assertEqual(self.fake.sent('400'), [])

    async def test_other_text_still_posts(self):
        rc, _ = await self.run_cli('post', '400', 'Ann lo revisa mañana')
        self.assertEqual((rc, len(self.fake.sent('400'))), (0, 1))


if __name__ == '__main__':
    unittest.main()
