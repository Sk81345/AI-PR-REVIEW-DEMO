# data_processor_bad.py
import json
from typing import List, Dict, Any


class DataProcessor:
    """
    A class for reading, processing, and saving JSON data.
    """

    def __init__(self, input_file: str, output_file: str):
        self.input_file = input_file
        self.output_file = output_file

    def read_data(self) -> List[Dict[str, Any]]:
        """Reads JSON data from the input file."""
        try:
            with open(self.input_file, "r") as f:
                data = json.load(f)
            return data
        except FileNotFoundError:
            print(f"❌ File not found: {self.input_file}")
            return []
        except json.JSONDecodeError:
            print(f"❌ Invalid JSON format in {self.input_file}")
            return []

    def process_data(self, data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Process data items:
        - Adds 'flag' for low values
        - Filters out values > 100
        """
        processed = []
        for item in data:
            if item.get("value", 0) > 100:
                processed.append(item)
            else:
                item["flag"] = True
                processed.append(item)
        return processed

    def save_data(self, data: List[Dict[str, Any]]) -> None:
        """Saves processed data to the output file."""
        try:
            with open(self.output_file, "w") as f:
                json.dump(data, f, indent=2)
            print(f"✅ Data saved successfully to {self.output_file}")
        except Exception as e:
            print(f"❌ Error saving file: {e}")


def main() -> None:
    processor = DataProcessor("input.json", "output.json")
    data = processor.read_data()
    if data:
        processed_data = processor.process_data(data)
        processor.save_data(processed_data)


if __name__ == "__main__":
    main()
