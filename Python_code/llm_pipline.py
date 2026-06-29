##pipline for lmm text classification tasks
##lowkey muss man google colab für den gpu verwenden oder Simon fragen?
import pandas as pd
import torch
from transformers import pipeline
import sys
import json_repair



#Datensatz-Validierung mit Pydantic