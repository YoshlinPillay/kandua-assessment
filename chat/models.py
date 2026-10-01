"""Bedrock model candidates for the chat app (D-020) and the Bedrock client factory.

Inference runs in us-east-1 (D-021): af-south-1 has no open-weight models and only global cross-region Claude.
Credentials come from the standard AWS chain: `aws login` profile locally, the EC2 instance role on AWS.
"""

import os

import boto3
from botocore.config import Config

BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")

# label -> Bedrock model ID (or inference profile ID). The bake-off decides the default (docs/bakeoff.md).
CANDIDATES: dict[str, str] = {
    "OpenAI gpt-oss-120b (open-weight)": "openai.gpt-oss-120b-1:0",
    "Claude Sonnet 5.5": "us.anthropic.claude-sonnet-5-5",
    "Claude Opus 5.5": "us.anthropic.claude-opus-5-5",
}
DEFAULT_MODEL = os.environ.get("CHAT_MODEL_ID", CANDIDATES["OpenAI gpt-oss-120b (open-weight)"])


def bedrock_runtime():
    session = boto3.Session(profile_name=os.environ.get("AWS_PROFILE") or None)
    return session.client(
        "bedrock-runtime",
        region_name=BEDROCK_REGION,
        config=Config(retries={"max_attempts": 4, "mode": "adaptive"}, read_timeout=120),
    )
