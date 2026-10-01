"""Bedrock model candidates for the chat app (D-020) and the Bedrock client factory.

Inference runs in us-east-1 (D-021): af-south-1 has no open-weight models and only global cross-region Claude.
Credentials come from the standard AWS chain: `aws login` profile locally, the EC2 instance role on AWS.
"""

import os

import boto3
from botocore.config import Config

BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")

# label -> Bedrock model ID (or inference profile ID). The bake-off decides the default (docs/bakeoff.md).
# Claude Sonnet/Opus 5.5 were candidates but were dropped by the human (D-027): gpt-oss passed 7/7 and Claude
# needed an extra Bedrock access step. To re-add: "Claude Sonnet 5.5": "us.anthropic.claude-sonnet-5-5".
CANDIDATES: dict[str, str] = {
    "OpenAI gpt-oss-120b (open-weight)": "openai.gpt-oss-120b-1:0",
}
DEFAULT_MODEL = os.environ.get("CHAT_MODEL_ID", CANDIDATES["OpenAI gpt-oss-120b (open-weight)"])


# Region the AWS session itself lives in. `aws login` credentials refresh through the sign-in service, which
# needs a region even though Bedrock calls go to BEDROCK_REGION (NoRegionError otherwise, once creds expire).
SESSION_REGION = os.environ.get("AWS_REGION", "af-south-1")


def bedrock_runtime():
    session = boto3.Session(profile_name=os.environ.get("AWS_PROFILE") or None, region_name=SESSION_REGION)
    return session.client(
        "bedrock-runtime",
        region_name=BEDROCK_REGION,
        config=Config(retries={"max_attempts": 4, "mode": "adaptive"}, read_timeout=120),
    )
