"""This module performs a simple string operation and prints the result."""

def reverse_string(text: str) -> str:
    """Return the reversed version of the given string."""
    return text[::-1]


if __name__ == "__main__":
    sample_text = "Hello"
    result = reverse_string(sample_text)
    print(f"The reverse of '{sample_text}' is '{result}'.")
