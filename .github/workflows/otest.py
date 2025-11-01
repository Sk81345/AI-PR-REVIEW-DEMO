"""This module calculates the average of numbers in a list and prints the result."""

def calculate_average(numbers: list[float]) -> float:
    """Return the average of the given list of numbers."""
    return sum(numbers) / len(numbers) if numbers else 0.0


if __name__ == "__main__":
    nums = [10, 20, 30, 40, 50]
    result = calculate_average(nums)
    print(f"The average of {nums} is {result}.")
