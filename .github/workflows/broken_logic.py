# broken_logic.py


def calculate_discount(price: float, discount: float) -> float:
    """
    Calculate the discounted price.
    Ensures discount is between 0 and 100.
    """
    if not 0 <= discount <= 100:
        raise ValueError("Discount must be between 0 and 100.")

    discounted_price = price - (price * discount / 100)
    return round(discounted_price, 2)


def greet_user(name: str) -> None:
    """Print a friendly greeting."""
    print(f"Hello, {name}!")


def buggy_function() -> None:
    """
    Demonstrates correct iteration and type-safe operations.
    """
    for i in range(5):
        print(i)
    final_result = f"{i + 5}"  # renamed to avoid shadowing
    print(f"Final result: {final_result}")


if __name__ == "__main__":
    try:
        result = calculate_discount(100, 20)
        print(f"Discounted price: {result}")
        greet_user("Shyam")
        buggy_function()
    except ValueError as ve:
        print(f"Value error: {ve}")
    except Exception as e:
        print(f"Unexpected error: {e}")
