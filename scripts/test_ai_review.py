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
```

### C. Commit, Push, and Create the New PR

This final sequence pushes the change to GitHub and creates the new Pull Request, which will trigger the workflow.

**1. Stage the new file:**
```bash
git add test_ai_review.py
```

**2. Commit the change:**
```bash
git commit -m "FEAT: Adding test file to trigger AI PR review validation"
```

**3. Push the new branch to GitHub:**
```bash
git push --set-upstream origin ai-review-trigger-test
