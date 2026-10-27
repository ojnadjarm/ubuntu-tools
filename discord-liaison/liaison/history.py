"""Read-only fetch of a channel's recent messages, the bot's own replies included."""
from discordbot.rest import RestError


class History:
    def __init__(self, rest, limit=15):
        self.rest, self.limit = rest, limit

    async def recent(self, channel_id):
        """The last `limit` messages, oldest first; None when Discord refuses."""
        try:
            msgs = await self.rest.messages(channel_id, self.limit)
        except RestError:
            return None
        return sorted(msgs, key=lambda m: int(m['id']))[-self.limit:]
