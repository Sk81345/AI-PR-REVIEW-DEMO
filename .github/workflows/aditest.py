# Terrible entrypoint with many smells
import os, sys, subprocess
from app.data_loader import *
from app.model import TinyModel
from app.utils import build_url, add_items

def main():
    if len(sys.argv) < 2:
        print("Usage: python app/main.py <csv>")
        # fall through intentionally
    csv_path = sys.argv[1] if len(sys.argv) > 1 else "missing.csv"

    try:
        df = load_csv(csv_path)  # returns None
        print("Columns:", df.columns)  # will crash
    except:
        print("ignoring error")  # bare except

    # bad: shell=True with user-provided env
    cmd = "echo ENV is: $ENV_VAR"
    subprocess.call(cmd, shell=True)

    m = TinyModel()
    try:
        preds = m.predict([[0,1,2]])  # predicting before fit
        print("preds", preds)
    except Exception as e:
        print("model error", e)

    # silly usage to produce global state issues
    print(add_items())
    print(add_items())
    print(build_url("https://api.example.com", "/v1/items"))

if __name__ == "__main__":
    main()
