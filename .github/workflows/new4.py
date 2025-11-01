"""This module calculates the factorial of a number and prints the result."""

def factorial(n: int) -> int:
    """Return the factorial of a given non-negative integer."""
    return 1 if n <= 1 else n * factorial(n - 1)
teste

if __name__ == "__main__":
    number = 5
    result = factorial(number)
    print(f"The factorial of {number} is {result}.")
