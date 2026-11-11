"""The image-model grant (T1632): words that ask for an AI, generated or concept image; shared by concept-img and the liaison."""
import re

GRANT = re.compile(r"(?i)\b(ai|ia|a\.i|i\.a|generated|generad[ao]s?|concept\w*|image model|modelo de imagen|openrouter|"
                   r"nano banana|gemini|seedream|midjourney|dall-?e|stable diffusion|artificial intelligence|"
                   r"inteligencia artificial)\b")
