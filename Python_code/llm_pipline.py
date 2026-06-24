##pipline for lmm text classification tasks
##lowkey muss man google colab für den gpu verwenden oder Simon fragen?
import pandas as pd
import torch
from transformers import pipeline
import sys
import json_repair

#hugging face --> model with ca 1-2 billion parameter
#open ai ---> porbably best performence but at what cost // ethics should be fine
model_name = #

text_pipeline = pipeline(
    task="text-generation", #or text classificTION
    model=model_name,
    dtype=torch.bfloat16, # speed up computations,
    device_map="auto" # load as much of the model as possible onto the GPU(s) and falls back to the CPU if GPU memory is insufficient
)

from openAI import gpt
