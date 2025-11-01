# data_processor_bad.py
import json
import os

class DataProcessor:
    def __init__(self, input_file, output_file):
        self.input_file = input_file
        self.output_file = output_file

    def read_data(self)
        with open(self.input_file, "r") as f:
            data = json.load(f)
        return data

    def process_data(self, data):
        processed = []
        for item in data
            if item["value"] > 100
                processed.append(item)
            else:
                item["flag"] = True
                processed.append(item)
        return data

    def save_data(self, data):
        with open(self.output_file, "w") as f:
            json.dump(processed, f)   # ❌ variable 'processed' is not defined here!

def main():
    processor = DataProcessor("input.json", "output.json")
    data = processor.read_data()
    new_data = processor.process_data(data)
    processor.save_data(data)  # ❌ wrong variable passed (should be new_data)

if __name__ == "__main__":
    main()
