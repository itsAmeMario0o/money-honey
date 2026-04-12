"""RAG pipeline: load PDFs, build a FAISS index, and retrieve context.

The design is deliberately simple. On startup we read every PDF in
KNOWLEDGE_BASE_DIR, split each document into chunks, and embed them with
a local sentence-transformers model. The chunks live in an in-memory
FAISS index. Each chat request runs a similarity search and returns the
top matches as context for the LLM.

Embeddings run in-process — no external API, no API key. This reduces
cost and egress surface area (one less FQDN for Layer 1 to allow).
"""

from __future__ import annotations

from pathlib import Path
from typing import List

from langchain_community.document_loaders import PyPDFLoader
from langchain_community.vectorstores import FAISS
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

KNOWLEDGE_BASE_DIR = Path(__file__).parent / "knowledge_base" / "pdfs"
EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 150
TOP_K = 4


def load_pdf_documents(pdf_dir: Path) -> List:
    """Load every PDF in pdf_dir and return a list of LangChain Documents."""
    documents = []
    for pdf_path in sorted(pdf_dir.glob("*.pdf")):
        loader = PyPDFLoader(str(pdf_path))
        documents.extend(loader.load())
    return documents


def split_documents(documents: List) -> List:
    """Split documents into overlapping chunks the embedding model can handle."""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )
    return splitter.split_documents(documents)


def build_index() -> FAISS | None:
    """Build a FAISS index from the PDF knowledge base.

    Returns None if there are no PDFs yet, so the app can still start.
    """
    documents = load_pdf_documents(KNOWLEDGE_BASE_DIR)
    if not documents:
        return None
    chunks = split_documents(documents)
    embeddings = HuggingFaceEmbeddings(model_name=EMBEDDING_MODEL)
    return FAISS.from_documents(chunks, embeddings)


def retrieve_context(index: FAISS, question: str, k: int = TOP_K) -> str:
    """Run a similarity search and return the top chunks as one string."""
    results = index.similarity_search(question, k=k)
    return "\n\n---\n\n".join(doc.page_content for doc in results)
