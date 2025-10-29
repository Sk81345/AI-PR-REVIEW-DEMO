"""This module finds the largest number in a list and prints the result."""

def find_max(numbers: list[int]) -> int:
    """Return the largest number in the given list."""
    return max(numbers)


if __name__ == "__main__":
    nums = [3, 8, 1, 10, 5]
    result = find_max(nums)
    print(f"The largest number in {nums} is {result}.")
