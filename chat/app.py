"""Streamlit UI: ask questions about Juan's drinking habits in plain English.

Run locally: `make chat` (http://localhost:8501). Every answer shows the Cube queries and rows it came from.
"""

import streamlit as st

from chat.agent import answer
from chat.cube_client import CubeClient
from chat.models import CANDIDATES, DEFAULT_MODEL, bedrock_runtime

EXAMPLES = [
    "Which beverage type does Juan drink the most?",
    "Which bar does Juan visit most, and by how much?",
    "How much has Juan saved on happy hours?",
    "Is Juan over the NHS weekly limit?",
]

st.set_page_config(page_title="Ask about Juan", page_icon="🍺")
st.title("Ask about Juan's drinking")
st.caption(
    "Answers come only from governed metrics in the Cube semantic layer (defined once in dbt). "
    "Expand any answer to see the exact queries behind it."
)

with st.sidebar:
    labels = list(CANDIDATES)
    model_ids = list(CANDIDATES.values())
    default_index = model_ids.index(DEFAULT_MODEL) if DEFAULT_MODEL in model_ids else 0
    model_label = st.selectbox("Model (Amazon Bedrock)", labels, index=default_index)
    if st.button("New conversation"):
        st.session_state.pop("history", None)
        st.session_state.pop("turns", None)
    st.markdown("**Try:**\n" + "\n".join(f"- {q}" for q in EXAMPLES))


@st.cache_resource
def clients():
    return bedrock_runtime(), CubeClient()


st.session_state.setdefault("history", [])  # Bedrock Converse messages (append-only)
st.session_state.setdefault("turns", [])  # what the UI renders

for turn in st.session_state.turns:
    with st.chat_message("user"):
        st.write(turn["question"])
    with st.chat_message("assistant"):
        st.write(turn["answer"])
        with st.expander(f"Queries ({len(turn['queries'])}) · {turn['model']}"):
            st.json(turn["queries"])

if question := st.chat_input("Ask a question about Juan's drinking habits"):
    with st.chat_message("user"):
        st.write(question)
    with st.chat_message("assistant"), st.spinner("Querying the semantic layer…"):
        model, cube = clients()
        result = answer(question, st.session_state.history, model, CANDIDATES[model_label], cube)
        st.write(result.answer)
        with st.expander(f"Queries ({len(result.queries)}) · {model_label}"):
            st.json(result.queries)
    st.session_state.turns.append(
        {"question": question, "answer": result.answer, "queries": result.queries, "model": model_label}
    )
