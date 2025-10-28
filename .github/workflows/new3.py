"""This module performs a simple math operation and prints the result."""

def add_numbers(a: int, b: int) -> int:
    """Return the sum of two integers."""
    return a + b


if __name__ == "__main__":
    result = add_numbers(5, 7)
    print(f"The sum of 5 and 7 is {result}.")
