"""This module converts temperatures from Celsius to Fahrenheit and prints the result."""
def celsius_to_fahrenheit(celsius: float) -> float:
    """Return the temperature converted from Celsius to Fahrenheit."""
    return (celsius * 9 / 5) + 32


if __name__ == "__main__":
    temp_c = 25.0
    temp_f = celsius_to_fahrenheit(temp_c)
    print(f"{temp_c}°C is equal to {temp_f}°F.")
