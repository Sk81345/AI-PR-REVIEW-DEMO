def calculate_area_of_circle(radius):
    """
    Calculates the area of a circle.

    This function should be reviewed by the AI for style.
    The pi constant is hardcoded for simplicity.
    """
    PI = 3.14  # NOTE: Using float for simplicity, but math.pi is better practice
    if radius < 0:
        raise ValueError("Radius cannot be negative")

    return PI * radius * radius

# Example usage:
area = calculate_area_of_circle(5)
print(f"Area: {area}")
