"""This module finds the largest number in a list and prints the result."""

from typing import List  # For compatibility with Python versions <3.9

def find_max(numbers: List[int]) -> int:  # Added function name
    """Return the largest number in the given list."""
    return max(numbers)  # 'max' is used correctly

if __name__ == "__main__":
    nums = [3, 8, 1, 10, 5]
    result = find_max(nums)  # Use the corrected function name
    print(f"The largest number in {nums} is {result}.")
