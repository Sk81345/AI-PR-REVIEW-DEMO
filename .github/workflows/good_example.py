def greet(name: str) -> str:
    """Return a polite greeting."""
    if not name:
        return "Hello!"
    return f"Hello, {name}!"
