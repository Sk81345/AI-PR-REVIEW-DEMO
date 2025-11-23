"""This module performs a simple math operation and prints the result."""
def greet(name: str) -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"

def add_numbers(a: int, b: int) -> int:
    """Return the sum of two integers."""
    return a + b

if __name__ == "__main__":
    print(greet("Shyam"))
    print(add_numbers(5, 7))
