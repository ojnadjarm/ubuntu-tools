"""T1690: a friend's bot never gets the owner's rights: not in the allowlist, never the owner, its ✅ approves nothing."""
import os
import unittest

from discordbot.config import Config, friend_bots

from tests.test_bot import Base, ev


class TestFriendBotConfig(unittest.TestCase):
    def test_friend_bot_is_dropped_from_the_allowlist(self):
        cfg = Config.from_env({'DISCORD_ALLOWLIST': '55 77', 'DISCORD_FRIEND_BOTS': '77'})
        self.assertEqual(cfg.allowlist, frozenset({'55'}))

    def test_the_owner_is_never_a_friend_bot(self):
        self.assertEqual(friend_bots({'DISCORD_FRIEND_BOTS': '77, 1 x', 'DISCORD_OWNER_ID': '1'}), frozenset({'77'}))
        self.assertEqual(friend_bots({}), frozenset())


class TestFriendBotApproval(Base):
    async def test_friend_bot_check_mark_records_no_approval(self):
        self.bot.cfg.forum_replies = 'liaison'
        self.bot.cfg.allowlist = Config.from_env({'DISCORD_ALLOWLIST': '77', 'DISCORD_FRIEND_BOTS': '77'}).allowlist
        await self.bot.dispatch('THREAD_CREATE', ev('THREAD_CREATE'))
        await self.bot.dispatch('MESSAGE_REACTION_ADD', ev('REACTION_OWNER', user_id='77'))
        self.assertFalse(os.path.exists(os.path.join(self.bot.store.dir, 'approvals', '400.json')))
        self.assertEqual(self.pending(), [])
