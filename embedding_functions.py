from chromadb import Documents, EmbeddingFunction, Embeddings
from sentence_transformers import SentenceTransformer
import os

class StellaEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer("dunzhang/stella_en_400M_v5", trust_remote_code=True)

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

class ModernBERTEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer("answerdotai/ModernBERT-large", trust_remote_code=True)

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

class BGEEmbeddingFunction(EmbeddingFunction[Documents]):
    def __init__(self):
        self.model = SentenceTransformer("BAAI/bge-large-en-v1.5")

    def __call__(self, input: Documents) -> Embeddings:
        return self.model.encode(input).tolist()

def get_embedding_function(model_name: str):
    model_map = {
        "stella": StellaEmbeddingFunction,
        "modernbert": ModernBERTEmbeddingFunction,
        "bge-large": BGEEmbeddingFunction
    }

    if model_name not in model_map:
        raise ValueError(f"Unknown embedding model: {model_name}. Available: {list(model_map.keys())}")

    return model_map[model_name]()